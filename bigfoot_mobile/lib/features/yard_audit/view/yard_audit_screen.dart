import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/stock_inventory.dart';
import '../../../data/models/yard_audit.dart';
import '../../../domain/repositories/delivery_repository.dart';
import '../../../domain/repositories/yard_audit_repository.dart';

/// Walk-the-lot reconciliation for sales / admin / owner.
///
/// Pick a yard → the app shows the trailers it lists there (the Inventory tab
/// set) → uncheck any you can't physically find → optionally add trailers you
/// DID find that weren't listed → submit. Every discrepancy becomes a problem
/// report in the support inbox (one per trailer).
class YardAuditScreen extends StatefulWidget {
  const YardAuditScreen({super.key});

  @override
  State<YardAuditScreen> createState() => _YardAuditScreenState();
}

class _YardAuditScreenState extends State<YardAuditScreen> {
  bool _loading = true;
  String? _error;
  List<StockLocationGroup> _yards = const [];

  StockLocationGroup? _selected;
  // Trailer ids the auditor marked as NOT physically present (default: present).
  final Set<int> _missing = {};
  final List<AuditExtra> _extras = [];
  bool _submitting = false;

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
      final yards = await context.read<DeliveryRepository>().getStockInventory();
      if (!mounted) return;
      setState(() {
        _yards = yards;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _selectYard(StockLocationGroup g) {
    setState(() {
      _selected = g;
      _missing.clear();
      _extras.clear();
    });
  }

  void _backToYards() {
    setState(() {
      _selected = null;
      _missing.clear();
      _extras.clear();
    });
  }

  int get _discrepancyCount =>
      _missing.length + _extras.where((e) => !e.isEmpty).length;

  Future<void> _submit() async {
    final yard = _selected;
    if (yard == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit yard audit?'),
        content: Text(
          _discrepancyCount == 0
              ? 'No discrepancies found at ${yard.name}. Submit a clean audit?'
              : 'This opens $_discrepancyCount problem report'
                  '${_discrepancyCount == 1 ? '' : 's'} for ${yard.name} '
                  '(${_missing.length} missing, '
                  '${_extras.where((e) => !e.isEmpty).length} extra).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final result = await context.read<YardAuditRepository>().submit(
            locationId: yard.locationId,
            missingTrailerIds: _missing.toList(),
            extras: _extras.where((e) => !e.isEmpty).toList(),
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.fact_check_outlined,
              color: AppColors.success, size: 32),
          title: const Text('Audit submitted'),
          content: Text(
            result.totalReported == 0
                ? '${result.locationName}: no discrepancies reported.'
                : '${result.locationName}: ${result.totalReported} report'
                    '${result.totalReported == 1 ? '' : 's'} opened '
                    '(${result.missingReported} missing, '
                    '${result.extrasReported} extra). '
                    'They\'re now in the problem reports inbox.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) _backToYards();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _addExtra() async {
    final extra = await showModalBottomSheet<AuditExtra>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ExtraSheet(),
    );
    if (extra != null && !extra.isEmpty) {
      setState(() => _extras.add(extra));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected == null ? 'Yard Audit' : 'Audit ${_selected!.name}'),
        leading: _selected != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _backToYards,
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _selected == null
                  ? _YardPicker(yards: _yards, onPick: _selectYard)
                  : _AuditList(
                      yard: _selected!,
                      missing: _missing,
                      extras: _extras,
                      onToggle: (id, present) => setState(() {
                        present ? _missing.remove(id) : _missing.add(id);
                      }),
                      onAddExtra: _addExtra,
                      onRemoveExtra: (i) => setState(() => _extras.removeAt(i)),
                    ),
      bottomNavigationBar: _selected == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  label: Text(_discrepancyCount == 0
                      ? 'Submit clean audit'
                      : 'Submit — report $_discrepancyCount'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Yard picker ──────────────────────────────────────────────────────────────
class _YardPicker extends StatelessWidget {
  final List<StockLocationGroup> yards;
  final ValueChanged<StockLocationGroup> onPick;

  const _YardPicker({required this.yards, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (yards.isEmpty) {
      return const _ErrorState(
        message: 'No inventory at any yard right now.',
        icon: Icons.inventory_2_outlined,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text(
            'Pick a yard to walk. You\'ll check the app\'s list against what\'s '
            'actually on the lot.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ),
        for (final y in yards)
          Card(
            child: ListTile(
              leading: const Icon(Icons.warehouse_outlined,
                  color: AppColors.navy),
              title: Text(y.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${y.city}, ${y.state}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${y.count} in app'),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => onPick(y),
            ),
          ),
      ],
    );
  }
}

// ── Audit list for a chosen yard ─────────────────────────────────────────────
class _AuditList extends StatefulWidget {
  final StockLocationGroup yard;
  final Set<int> missing;
  final List<AuditExtra> extras;
  final void Function(int trailerId, bool present) onToggle;
  final VoidCallback onAddExtra;
  final ValueChanged<int> onRemoveExtra;

  const _AuditList({
    required this.yard,
    required this.missing,
    required this.extras,
    required this.onToggle,
    required this.onAddExtra,
    required this.onRemoveExtra,
  });

  @override
  State<_AuditList> createState() => _AuditListState();
}

class _AuditListState extends State<_AuditList> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yard = widget.yard;
    final missing = widget.missing;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? yard.trailers
        : yard.trailers.where((t) {
            return t.soNumber.toLowerCase().contains(q) ||
                (t.model?.toLowerCase().contains(q) ?? false);
          }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.checklist, color: AppColors.navy),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Toggle OFF any trailer you can\'t find on the lot. '
                  '${missing.length} marked missing.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Search by SO number or model — handy on a big lot.
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search SO or model',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (yard.trailers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('The app lists no trailers at ${yard.name}.',
                style: TextStyle(color: Colors.grey.shade600)),
          )
        else if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No trailers match "$_query".',
                style: TextStyle(color: Colors.grey.shade600)),
          ),
        for (final t in filtered)
          _TrailerRow(
            trailer: t,
            present: !missing.contains(t.trailerId),
            onChanged: (v) => widget.onToggle(t.trailerId, v),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.add_location_alt_outlined,
                size: 18, color: AppColors.navy),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Found something not listed here?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: widget.onAddExtra,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        for (var i = 0; i < widget.extras.length; i++)
          Card(
            color: AppColors.navy.withValues(alpha: 0.04),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.help_outline, color: AppColors.amber),
              title: Text(widget.extras[i].soNumber.trim().isEmpty
                  ? 'Unknown trailer'
                  : 'SO ${widget.extras[i].soNumber.trim()}'),
              subtitle: widget.extras[i].note.trim().isEmpty
                  ? null
                  : Text(widget.extras[i].note.trim()),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => widget.onRemoveExtra(i),
              ),
            ),
          ),
      ],
    );
  }
}

class _TrailerRow extends StatelessWidget {
  final StockTrailer trailer;
  final bool present;
  final ValueChanged<bool> onChanged;

  const _TrailerRow({
    required this.trailer,
    required this.present,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (trailer.model != null && trailer.model!.isNotEmpty) trailer.model!,
      if (trailer.sizeFt != null && trailer.sizeFt!.isNotEmpty)
        '${trailer.sizeFt}ft',
      if (trailer.saleStatus != null && trailer.saleStatus!.isNotEmpty)
        trailer.saleStatus!,
    ];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: present ? null : AppColors.error.withValues(alpha: 0.06),
      child: SwitchListTile(
        value: present,
        onChanged: onChanged,
        secondary: Icon(
          present ? Icons.check_circle : Icons.report_gmailerrorred,
          color: present ? AppColors.success : AppColors.error,
        ),
        title: Row(
          children: [
            Text('SO ${trailer.soNumber}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (trailer.isHot) ...[
              const SizedBox(width: 6),
              const Icon(Icons.local_fire_department,
                  size: 16, color: AppColors.error),
            ],
          ],
        ),
        subtitle: Text(
          present ? subtitleParts.join(' · ') : 'NOT FOUND — will be reported',
          style: TextStyle(
            fontSize: 12,
            color: present ? Colors.grey.shade600 : AppColors.error,
            fontWeight: present ? FontWeight.normal : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Add-extra bottom sheet ───────────────────────────────────────────────────
class _ExtraSheet extends StatefulWidget {
  const _ExtraSheet();

  @override
  State<_ExtraSheet> createState() => _ExtraSheetState();
}

class _ExtraSheetState extends State<_ExtraSheet> {
  final _soCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _soCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trailer found on the lot',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Not in the app\'s list for this yard.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          TextField(
            controller: _soCtrl,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'SO number (if legible)',
              border: OutlineInputBorder(),
            ),
            maxLength: 30,
          ),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Note (model, colour, where it sat)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            maxLength: 500,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final extra = AuditExtra(
                soNumber: _soCtrl.text,
                note: _noteCtrl.text,
              );
              Navigator.pop(context, extra.isEmpty ? null : extra);
            },
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: const Text('Add to audit'),
          ),
        ],
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const _ErrorState({
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.disabled),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
