import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/stock_inventory.dart';
import '../viewmodel/deliveries_viewmodel.dart';

/// Stock inventory — trailers currently parked at each stock-location yard.
/// A trailer lands here when a delivery to that yard is marked complete, and
/// drops off once it is delivered out again.
class StockInventoryScreen extends StatefulWidget {
  const StockInventoryScreen({super.key});

  @override
  State<StockInventoryScreen> createState() => _StockInventoryScreenState();
}

class _StockInventoryScreenState extends State<StockInventoryScreen> {
  bool _loading = true;
  String? _error;
  List<StockLocationGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups =
          await context.read<DeliveriesViewModel>().getStockInventory();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load stock inventory: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock Inventory')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.amber));
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 44, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (_groups.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 140),
          Center(
            child: Text(
              'No trailers in stock at any yard.\nPull down to refresh.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _groups.length,
      itemBuilder: (_, i) => _LocationSection(group: _groups[i]),
    );
  }
}

/// A collapsible yard — tap the header to expand the list of trailers parked
/// there.
class _LocationSection extends StatelessWidget {
  final StockLocationGroup group;
  const _LocationSection({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Drop the ExpansionTile's default divider lines.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.warehouse_outlined, color: AppColors.navy),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${group.count}',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          subtitle: group.city.isNotEmpty
              ? Text(
                  '${group.city}, ${group.state}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.disabled),
                )
              : null,
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          children: group.trailers
              .map((t) => _StockTrailerCard(trailer: t))
              .toList(),
        ),
      ),
    );
  }
}

class _StockTrailerCard extends StatelessWidget {
  final StockTrailer trailer;
  const _StockTrailerCard({required this.trailer});

  @override
  Widget build(BuildContext context) {
    final t = trailer;
    final date = t.deliveredAt != null
        ? DateFormat('MMM d, yyyy').format(t.deliveredAt!.toLocal())
        : 'Unknown date';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // Tapping a trailer opens its full detail screen.
          onTap: () => context.pushNamed(
            RouteNames.trailerDetail,
            pathParameters: {'id': t.trailerId.toString()},
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.soNumber,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 20, color: AppColors.disabled),
                  ],
                ),
                if ((t.model ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(t.model!,
                      style: const TextStyle(color: AppColors.disabled)),
                ],
                const SizedBox(height: 8),
                _InfoRow(
                    icon: Icons.event_outlined, label: 'Delivered', value: date),
                if ((t.deliveredBy ?? '').isNotEmpty)
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: 'Delivered by',
                    value: t.deliveredBy!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.disabled),
          const SizedBox(width: 6),
          Text('$label: ',
              style: const TextStyle(fontSize: 13, color: AppColors.disabled)),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
