import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/stock_location_chips.dart';
import '../viewmodel/deliveries_viewmodel.dart';

class CreateDeliveryScreen extends StatefulWidget {
  const CreateDeliveryScreen({super.key});

  @override
  State<CreateDeliveryScreen> createState() => _CreateDeliveryScreenState();
}

class _CreateDeliveryScreenState extends State<CreateDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();

  int? _trailerId;
  int? _driverId;
  int? _destinationLocationId;
  int? _batchId;
  String _deliveryType = 'single_pull';
  bool _submitting = false;
  DeliveryFormData? _formData;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _formData = null;
    });
    try {
      final data = await context.read<DeliveriesViewModel>().getCreateFormData();
      if (!mounted) return;
      setState(() => _formData = data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Failed to load delivery form data: $e';
      });
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _formData;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Delivery')),
      body: data == null
          ? _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 44, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<int>(
                    value: _trailerId,
                    decoration: const InputDecoration(
                      labelText: 'Ready Trailer',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null ? 'Trailer is required' : null,
                    items: data.trailers.map((t) {
                      final model = (t['trailerModel'] as Map<String, dynamic>?)?['displayName'] ?? 'Model';
                      return DropdownMenuItem<int>(
                        value: t['id'] as int,
                        child: Text('${t['soNumber']} • $model'),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _trailerId = v),
                  ),
                  const SizedBox(height: 12),
                  const Text('Delivery Type', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _typeChip('factory_pickup', 'Factory Pickup'),
                      _typeChip('single_pull', 'Single Pull'),
                      _typeChip('stack_to_dealer', 'Stack to Dealer'),
                      _typeChip('stack_to_location', 'Stack to Location'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _driverId,
                    decoration: const InputDecoration(
                      labelText: 'Assign Driver',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('Unassigned')),
                      ...data.drivers.map(
                        (d) => DropdownMenuItem<int>(
                          value: d.id,
                          child: Text(d.name),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _driverId = v),
                  ),
                  const SizedBox(height: 12),
                  StockLocationChips(
                    labelText: 'Destination Location',
                    selectedLocationId: _destinationLocationId,
                    enabled: !_submitting,
                    onChanged: (l) => setState(() {
                      _destinationLocationId = l.id;
                      _addressCtrl.clear();
                    }),
                    helperText:
                        'Pick a yard, or leave unselected and enter a custom address below.',
                  ),
                  if (_destinationLocationId != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _destinationLocationId = null),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Clear yard, use custom address'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    enabled: _destinationLocationId == null,
                    decoration: const InputDecoration(
                      labelText: 'Custom Destination Address',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _balanceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Balance Due',
                      prefixText: r'$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _batchId,
                    decoration: const InputDecoration(
                      labelText: 'Add to Batch (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('No batch')),
                      ...data.batches.map(
                        (b) => DropdownMenuItem<int>(
                          value: b.id,
                          child: Text('${b.batchNumber} (${b.status})'),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _batchId = v),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.local_shipping_outlined),
                    label: const Text('Create Delivery'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _typeChip(String value, String label) {
    final selected = _deliveryType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _deliveryType = value),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await context.read<DeliveriesViewModel>().createDelivery(
            trailerId: _trailerId!,
            deliveryType: _deliveryType,
            driverUserId: _driverId,
            destinationLocationId: _destinationLocationId,
            customerDeliveryAddress:
                _destinationLocationId == null ? _addressCtrl.text.trim() : null,
            balanceDue: double.tryParse(_balanceCtrl.text.trim()),
            deliveryBatchId: _batchId,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().contains('DELIVERY_NOT_DISPATCHABLE')
              ? 'Trailer is not ready for delivery'
              : 'Failed to create delivery: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
