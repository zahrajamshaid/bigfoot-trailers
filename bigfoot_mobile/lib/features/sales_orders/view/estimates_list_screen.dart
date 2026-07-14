import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../data/sales_order_api.dart';
import 'configurator_screen.dart';
import 'estimate_detail_screen.dart';
import 'sales_order_status.dart';

/// QuickBooks-style estimates list: every Sales Order with its number,
/// customer, line count, total and status. Tap a row for the full estimate
/// with its actions (PDF / send / accept). The FAB starts a new estimate in
/// the configurator.
class EstimatesListScreen extends StatefulWidget {
  const EstimatesListScreen({super.key});

  @override
  State<EstimatesListScreen> createState() => _EstimatesListScreenState();
}

class _EstimatesListScreenState extends State<EstimatesListScreen> {
  late final SalesOrderApi _api;
  bool _loading = true;
  String? _error;
  List<SalesOrder> _items = const [];

  @override
  void initState() {
    super.initState();
    _api = SalesOrderApi(context.read<DioClient>());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.list();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail(SalesOrder so) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EstimateDetailScreen(id: so.id)),
    );
    if (mounted) _load();
  }

  Future<void> _newEstimate() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConfiguratorScreen()),
    );
    if (mounted) _load();
  }

  /// Slice 1 — pull models/options/fees + prices from QuickBooks. Idempotent:
  /// re-running updates prices in place and creates no duplicates.
  Future<void> _syncCatalog() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Syncing catalog from QuickBooks…')));
    try {
      final r = await _api.importCatalogFromQbo();
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Catalog synced — ${r['modelsLinked']} models linked, '
          '${r['optionsCreated']} new options, ${r['feesCreated']} new fees '
          '(${r['total']} QuickBooks items)',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Catalog sync failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estimates'),
        actions: [
          IconButton(
            tooltip: 'Sync catalog from QuickBooks',
            onPressed: _syncCatalog,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? _EmptyView(onNew: _newEstimate)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _EstimateCard(
                          so: _items[i],
                          onTap: () => _openDetail(_items[i]),
                        ),
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newEstimate,
        icon: const Icon(Icons.add),
        label: const Text('New estimate'),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  final SalesOrder so;
  final VoidCallback onTap;
  const _EstimateCard({required this.so, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final number = so.soNumber ?? 'Draft';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    so.customerName ?? 'Customer',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                Text('\$${so.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            Text('#$number · ${so.lineCount} line${so.lineCount == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.disabled, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                SoStatusChip(status: so.status),
                SyncStateChip(state: so.syncState),
                if (so.isSent)
                  const _MiniTag(label: 'Sent', color: Colors.teal),
                if (so.isConverted)
                  const _MiniTag(label: 'Work order', color: Colors.indigo),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyView({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.request_quote_outlined,
              size: 56, color: AppColors.disabled),
          const SizedBox(height: 12),
          const Text('No estimates yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Create one to push it to QuickBooks.',
              style: TextStyle(color: AppColors.disabled)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('New estimate'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
