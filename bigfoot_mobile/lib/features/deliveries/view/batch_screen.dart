import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/delivery_batch.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../viewmodel/deliveries_viewmodel.dart';

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  bool _loading = true;
  int? _busyBatchId;
  List<DeliveryBatch> _batches = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<DeliveriesViewModel>().getBatches();
      if (!mounted) return;
      setState(() => _batches = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteBatch(DeliveryBatch b) async {
    final l = AppLocalizations.of(context);
    final count = (b.deliveries ?? const []).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.batchScreenDeleteTitle),
        content: Text(l.batchScreenDeleteBody(b.batchNumber, count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyBatchId = b.id);
    try {
      await context.read<DeliveriesViewModel>().deleteBatch(b.id);
      if (mounted) await _load();
      messenger.showSnackBar(
        SnackBar(content: Text(l.batchScreenDeleted(b.batchNumber))),
      );
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.batchScreenDeleteFail('$e'))));
    } finally {
      if (mounted) setState(() => _busyBatchId = null);
    }
  }

  Future<void> _completeBatch(DeliveryBatch b) async {
    final l = AppLocalizations.of(context);
    final count = (b.deliveries ?? const []).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deliveryDetailCompleteBatchTitle),
        content: Text(l.deliveryDetailCompleteBatchBody(count, b.batchNumber)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.deliveryDetailMarkAllDelivered),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyBatchId = b.id);
    try {
      await context.read<DeliveriesViewModel>().completeBatch(b.id);
      if (mounted) await _load();
      messenger.showSnackBar(
        SnackBar(content: Text(l.deliveryDetailBatchAllDelivered(b.batchNumber))),
      );
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.batchScreenCompleteFail('$e'))));
    } finally {
      if (mounted) setState(() => _busyBatchId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.batchScreenTitle),
        actions: [
          IconButton(
            onPressed: _openCreate,
            icon: const Icon(Icons.add),
            tooltip: l.batchScreenNewBatch,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemBuilder: (_, i) {
                  final b = _batches[i];
                  final deliveries = b.deliveries ?? const [];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  b.batchNumber,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                              ),
                              Chip(label: Text(b.statusLabel)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(l.batchScreenTypeLabel(b.batchType)),
                          Text(l.batchScreenDriverLabel(b.driverUser?.fullName ?? '-')),
                          Text(l.batchScreenDestinationLabel(b.destinationLocation?.name ?? b.destinationName ?? '-')),
                          const SizedBox(height: 8),
                          Text(l.batchScreenTrailersLabel(deliveries.length)),
                          if (deliveries.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: deliveries
                                    .map((d) => Chip(
                                          label: Text(d.trailer?.soNumber ?? '#${d.trailerId}'),
                                        ))
                                    .toList(),
                              ),
                            ),
                          const SizedBox(height: 10),
                          _BatchActions(
                            batch: b,
                            busy: _busyBatchId == b.id,
                            onUpdate: () => _openUpdate(b),
                            onComplete: () => _completeBatch(b),
                            onDelete: () => _deleteBatch(b),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: _batches.length,
              ),
            ),
    );
  }

  Future<void> _openCreate() async {
    // Batch creation lives in the Create Delivery screen's "Batch" mode.
    await context.pushNamed(
      RouteNames.deliveryCreate,
      queryParameters: {'mode': 'batch'},
    );
    if (mounted) _load();
  }

  Future<void> _openUpdate(DeliveryBatch batch) async {
    final form = await context.read<DeliveriesViewModel>().getCreateFormData();
    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BatchEditDialog(batch: batch, form: form),
    );
    if (saved == true && mounted) _load();
  }
}

/// Stateful dialog body for batch editing. Encapsulates the driver +
/// destination updates, removal of existing trailers via × buttons, and
/// adding new ready trailers via a multi-select picker — all in one save.
class _BatchEditDialog extends StatefulWidget {
  final DeliveryBatch batch;
  final DeliveryFormData form;

  const _BatchEditDialog({required this.batch, required this.form});

  @override
  State<_BatchEditDialog> createState() => _BatchEditDialogState();
}

class _BatchEditDialogState extends State<_BatchEditDialog> {
  late int? _driverId = widget.batch.driverUserId;
  late int? _destinationLocationId = widget.batch.destinationLocationId;
  late final TextEditingController _destinationNameCtrl =
      TextEditingController(text: widget.batch.destinationName ?? '');

  /// Delivery IDs the user has flagged for removal from the batch.
  final Set<int> _removeDeliveryIds = <int>{};

  /// Trailer IDs the user has flagged for addition to the batch.
  final Set<int> _addTrailerIds = <int>{};

  bool _saving = false;

  @override
  void dispose() {
    _destinationNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final deliveries = widget.batch.deliveries ?? const [];

    return AlertDialog(
      title: Text(l.batchScreenUpdateTitle(widget.batch.batchNumber)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int?>(
                value: _driverId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.batchScreenDriverField),
                items: [
                  DropdownMenuItem<int?>(
                      value: null, child: Text(l.deliveryDetailUnassigned)),
                  ...widget.form.drivers.map(
                    (d) => DropdownMenuItem<int?>(value: d.id, child: Text(d.name)),
                  ),
                ],
                onChanged: _saving ? null : (v) => setState(() => _driverId = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                value: _destinationLocationId,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: l.createDeliveryDestinationLocation),
                items: [
                  DropdownMenuItem<int?>(
                      value: null, child: Text(l.batchScreenCustomDestination)),
                  ...widget.form.locations.map(
                    (loc) =>
                        DropdownMenuItem<int?>(value: loc.id, child: Text(loc.name)),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _destinationLocationId = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _destinationNameCtrl,
                enabled: !_saving,
                decoration:
                    InputDecoration(labelText: l.batchScreenDestinationName),
              ),
              const SizedBox(height: 16),

              // ── Currently in the batch ─────────────────────────────────
              Text(
                l.batchScreenTrailersInBatchLabel(deliveries.length),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              if (deliveries.isEmpty)
                Text(l.batchScreenNoTrailersInBatch,
                    style: const TextStyle(fontSize: 13, color: AppColors.disabled))
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: deliveries.map((d) {
                      final marked = _removeDeliveryIds.contains(d.id);
                      return ListTile(
                        dense: true,
                        title: Text(
                          d.trailer?.soNumber ?? '#${d.trailerId}',
                          style: TextStyle(
                            decoration:
                                marked ? TextDecoration.lineThrough : null,
                            color: marked ? AppColors.disabled : null,
                          ),
                        ),
                        subtitle: d.trailer?.trailerModel?.displayName == null
                            ? null
                            : Text(d.trailer!.trailerModel!.displayName),
                        trailing: IconButton(
                          tooltip: marked
                              ? l.batchScreenUndoRemove
                              : l.batchScreenRemoveTrailer,
                          icon: Icon(marked ? Icons.undo : Icons.close),
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                    if (marked) {
                                      _removeDeliveryIds.remove(d.id);
                                    } else {
                                      _removeDeliveryIds.add(d.id);
                                    }
                                  }),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              const SizedBox(height: 16),

              // ── Add new trailers ───────────────────────────────────────
              Text(
                l.batchScreenAddTrailersLabel(_addTrailerIds.length),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              if (widget.form.trailers.isEmpty)
                Text(l.createDeliveryNoReadyTrailers,
                    style: const TextStyle(fontSize: 13, color: AppColors.disabled))
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Scrollbar(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.form.trailers.length,
                      itemBuilder: (_, i) {
                        final t = widget.form.trailers[i];
                        final id = (t['id'] as num?)?.toInt();
                        if (id == null) return const SizedBox.shrink();
                        final so = (t['soNumber'] as String?) ?? 'SO-$id';
                        final model = (t['trailerModel']
                            as Map<String, dynamic>?)?['displayName'] as String?;
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _addTrailerIds.contains(id),
                          title: Text(
                            model == null ? so : '$so — $model',
                            style: const TextStyle(fontSize: 14),
                          ),
                          onChanged: _saving
                              ? null
                              : (v) => setState(() {
                                    if (v ?? false) {
                                      _addTrailerIds.add(id);
                                    } else {
                                      _addTrailerIds.remove(id);
                                    }
                                  }),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l.commonSave),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l = AppLocalizations.of(context);
    try {
      await context.read<DeliveriesViewModel>().updateBatch(
            batchId: widget.batch.id,
            driverUserId: _driverId,
            destinationLocationId: _destinationLocationId,
            destinationName: _destinationNameCtrl.text.trim(),
            addTrailerIds:
                _addTrailerIds.isEmpty ? null : _addTrailerIds.toList(),
            removeDeliveryIds: _removeDeliveryIds.isEmpty
                ? null
                : _removeDeliveryIds.toList(),
          );
      if (mounted) navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l.batchScreenUpdateFail('$e'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Status-aware action row for a batch card.
///  • not complete → Complete Batch (one tap delivers every trailer),
///                    plus Update (while building) and Delete
///  • complete     → read-only "Completed" note, plus Delete
class _BatchActions extends StatelessWidget {
  final DeliveryBatch batch;
  final bool busy;
  final VoidCallback onUpdate;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _BatchActions({
    required this.batch,
    required this.busy,
    required this.onUpdate,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final spinner = busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null;

    final isComplete = batch.status == 'complete';
    final hasTrailers = (batch.deliveries ?? const []).isNotEmpty;

    final deleteButton = OutlinedButton.icon(
      onPressed: busy ? null : onDelete,
      icon: const Icon(Icons.delete_outline, size: 18),
      label: Text(l.commonDelete),
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isComplete)
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l.batchScreenCompletedNote),
              ),
            ],
          )
        else
          // No separate dispatch step — a batch is completed in one tap.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: (busy || !hasTrailers) ? null : onComplete,
              icon: spinner ?? const Icon(Icons.task_alt_outlined),
              label: Text(l.deliveryDetailCompleteBatchTitle),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Mirror the backend gate (batches.service.ts update): editable
            // while building OR scheduled — once a batch is in_transit /
            // complete the trailers are on the move or delivered and the
            // backend rejects the PATCH with BATCH_NOT_BUILDING anyway.
            if (batch.status == 'building' || batch.status == 'scheduled')
              OutlinedButton.icon(
                onPressed: busy ? null : onUpdate,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l.batchScreenUpdate),
              ),
            deleteButton,
          ],
        ),
      ],
    );
  }
}
