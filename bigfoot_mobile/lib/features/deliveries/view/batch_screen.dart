import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/delivery_batch.dart';
import '../viewmodel/deliveries_viewmodel.dart';

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  bool _loading = true;
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
                              Chip(label: Text(b.status)),
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
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _openUpdate(b),
                                child: const Text('Update'),
                              ),
                              FilledButton(
                                onPressed: b.status == 'building' || b.status == 'scheduled'
                                    ? () async {
                                        await context
                                            .read<DeliveriesViewModel>()
                                            .dispatchBatch(b.id);
                                        if (mounted) _load();
                                      }
                                    : null,
                                child: const Text('Dispatch Batch'),
                              ),
                            ],
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
    final form = await context.read<DeliveriesViewModel>().getCreateFormData();
    if (!mounted) return;

    final batchNoCtrl = TextEditingController();
    String batchType = 'dealer';
    int? driverId;
    int? destinationLocationId;
    final destinationNameCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Batch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: batchNoCtrl,
                decoration: const InputDecoration(labelText: 'Batch Number'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: batchType,
                decoration: const InputDecoration(labelText: 'Batch Type'),
                items: const [
                  DropdownMenuItem(value: 'dealer', child: Text('Dealer')),
                  DropdownMenuItem(value: 'bf_location', child: Text('Bigfoot Location')),
                ],
                onChanged: (v) => batchType = v ?? 'dealer',
              ),
              const SizedBox(height: 8),
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
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await context.read<DeliveriesViewModel>().createBatch(
                    batchNumber: batchNoCtrl.text.trim(),
                    batchType: batchType,
                    driverUserId: driverId,
                    destinationLocationId: destinationLocationId,
                    destinationName: destinationNameCtrl.text.trim(),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    batchNoCtrl.dispose();
    destinationNameCtrl.dispose();
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
