import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/delivery_batch.dart';
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
    final count = (b.deliveries ?? const []).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Batch'),
        content: Text(
          'Delete ${b.batchNumber}? This removes the batch and its '
          '$count delivery record(s). Trailers not yet delivered are returned '
          'to the ready-for-delivery pool.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
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
        SnackBar(content: Text('${b.batchNumber} deleted.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    } finally {
      if (mounted) setState(() => _busyBatchId = null);
    }
  }

  Future<void> _completeBatch(DeliveryBatch b) async {
    final count = (b.deliveries ?? const []).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Batch'),
        content: Text(
          'Mark all $count trailer(s) in ${b.batchNumber} as delivered? '
          'This completes the whole batch in one step.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark All Delivered'),
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
        SnackBar(content: Text('${b.batchNumber} — all trailers delivered.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to complete: $e')));
    } finally {
      if (mounted) setState(() => _busyBatchId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Batches'),
        actions: [
          IconButton(
            onPressed: _openCreate,
            icon: const Icon(Icons.add),
            tooltip: 'Create Batch',
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
                          Text('Type: ${b.batchType}'),
                          Text('Driver: ${b.driverUser?.fullName ?? '-'}'),
                          Text('Destination: ${b.destinationLocation?.name ?? b.destinationName ?? '-'}'),
                          const SizedBox(height: 8),
                          Text('Trailers: ${deliveries.length}'),
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

    int? driverId = batch.driverUserId;
    int? destinationLocationId = batch.destinationLocationId;
    final destinationNameCtrl = TextEditingController(text: batch.destinationName ?? '');
    final addTrailerCtrl = TextEditingController();
    final removeDeliveryCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update ${batch.batchNumber}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: driverId,
                decoration: const InputDecoration(labelText: 'Driver'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Unassigned')),
                  ...form.drivers.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))),
                ],
                onChanged: (v) => driverId = v,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: destinationLocationId,
                decoration: const InputDecoration(labelText: 'Destination Location'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Custom destination name')),
                  ...form.locations.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))),
                ],
                onChanged: (v) => destinationLocationId = v,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: destinationNameCtrl,
                decoration: const InputDecoration(labelText: 'Destination Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: addTrailerCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Add Trailer ID (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: removeDeliveryCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Remove Delivery ID (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await context.read<DeliveriesViewModel>().updateBatch(
                    batchId: batch.id,
                    driverUserId: driverId,
                    destinationLocationId: destinationLocationId,
                    destinationName: destinationNameCtrl.text.trim(),
                    addTrailerIds: int.tryParse(addTrailerCtrl.text.trim()) == null
                        ? null
                        : [int.parse(addTrailerCtrl.text.trim())],
                    removeDeliveryIds: int.tryParse(removeDeliveryCtrl.text.trim()) == null
                        ? null
                        : [int.parse(removeDeliveryCtrl.text.trim())],
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    destinationNameCtrl.dispose();
    addTrailerCtrl.dispose();
    removeDeliveryCtrl.dispose();
    if (mounted) _load();
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
      label: const Text('Delete'),
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isComplete)
          Row(
            children: const [
              Icon(Icons.check_circle, color: AppColors.success, size: 18),
              SizedBox(width: 6),
              Expanded(
                child: Text('Batch completed — all trailers delivered.'),
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
              label: const Text('Complete Batch'),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (batch.status == 'building')
              OutlinedButton.icon(
                onPressed: busy ? null : onUpdate,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Update'),
              ),
            deleteButton,
          ],
        ),
      ],
    );
  }
}
