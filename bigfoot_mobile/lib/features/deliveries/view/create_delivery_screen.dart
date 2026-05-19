import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/stock_location_chips.dart';
import '../viewmodel/deliveries_viewmodel.dart';

/// Where a trailer is currently parked, e.g. "Jacksonville" — shown so the
/// person picking a ready trailer can see which yard it's stocked at.
/// Returns null when the trailer carries no location.
String? _trailerLocationLabel(Map<String, dynamic> t) {
  final loc = t['currentLocation'] as Map<String, dynamic>?;
  if (loc == null) return null;
  return (loc['name'] as String?) ??
      (loc['shortLabel'] as String?) ??
      (loc['city'] as String?);
}

/// Create-delivery entry point. A toggle at the top switches between:
///  • Single Delivery — one ready trailer, optionally added to a batch.
///  • Batch Delivery  — a named batch with several ready trailers selected.
class CreateDeliveryScreen extends StatefulWidget {
  /// When true the screen opens straight into Batch mode (used by the
  /// Batches screen "+" button).
  final bool startInBatchMode;

  const CreateDeliveryScreen({super.key, this.startInBatchMode = false});

  @override
  State<CreateDeliveryScreen> createState() => _CreateDeliveryScreenState();
}

class _CreateDeliveryScreenState extends State<CreateDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Single-delivery fields ────────────────────────────────────────────────
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _pickedUpByCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  int? _trailerId;
  int? _driverId;
  int? _destinationLocationId;
  int? _batchId;
  String _deliveryType = 'single_pull';

  // ── Batch-delivery fields ─────────────────────────────────────────────────
  final _batchNumberCtrl = TextEditingController();
  final _batchDestNameCtrl = TextEditingController();
  final Set<int> _selectedTrailerIds = <int>{};
  String _batchType = 'dealer';
  int? _batchDriverId;
  int? _batchDestinationLocationId;

  late bool _batchMode = widget.startInBatchMode;
  bool _submitting = false;
  DeliveryFormData? _formData;
  String? _loadError;

  bool get _isFactoryPickup => _deliveryType == 'factory_pickup';

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
    _phoneCtrl.dispose();
    _balanceCtrl.dispose();
    _pickedUpByCtrl.dispose();
    _amountCtrl.dispose();
    _batchNumberCtrl.dispose();
    _batchDestNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _formData;
    return Scaffold(
      appBar: AppBar(
        title: Text(_batchMode ? 'Create Batch Delivery' : 'Create Delivery'),
      ),
      body: data == null
          ? _loadError != null
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 44, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(_loadError!, textAlign: TextAlign.center),
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
              : const Center(
                  child: CircularProgressIndicator(color: AppColors.amber))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<bool>(
                    // Each segment carries its own icon — suppress the extra
                    // selected-state checkmark so the row never overflows on
                    // narrow screens or with large text scaling.
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Single'),
                        icon: Icon(Icons.local_shipping_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Batch'),
                        icon: Icon(Icons.inventory_2_outlined, size: 18),
                      ),
                    ],
                    selected: {_batchMode},
                    onSelectionChanged: _submitting
                        ? null
                        : (s) => setState(() => _batchMode = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (_batchMode)
                    ..._batchFields(data)
                  else
                    ..._singleFields(data),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_batchMode
                            ? Icons.inventory_2_outlined
                            : _isFactoryPickup
                                ? Icons.task_alt_outlined
                                : Icons.local_shipping_outlined),
                    label: Text(_batchMode
                        ? 'Create Batch'
                        : _isFactoryPickup
                            ? 'Record Pickup'
                            : 'Create Delivery'),
                  ),
                ],
              ),
            ),
    );
  }

  // ===========================================================================
  // SINGLE DELIVERY
  // ===========================================================================
  List<Widget> _singleFields(DeliveryFormData data) {
    return [
      DropdownButtonFormField<int>(
        value: _trailerId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Ready Trailer',
          border: OutlineInputBorder(),
        ),
        validator: (v) => v == null ? 'Trailer is required' : null,
        items: data.trailers.map((t) {
          final model =
              (t['trailerModel'] as Map<String, dynamic>?)?['displayName'] ??
                  'Model';
          final loc = _trailerLocationLabel(t);
          return DropdownMenuItem<int>(
            value: t['id'] as int,
            child: Text(
              loc == null
                  ? '${t['soNumber']} • $model'
                  : '${t['soNumber']} • $model  ·  $loc',
              overflow: TextOverflow.ellipsis,
            ),
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

      // A factory pickup is the customer collecting the trailer at the
      // factory — no driver, destination or batch.
      if (_isFactoryPickup) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Recorded as picked up immediately — the customer collects the '
            'trailer at the factory.',
            style: TextStyle(fontSize: 12, color: AppColors.disabled),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _pickedUpByCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Picked up by (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount Collected (optional)',
            prefixText: r'$ ',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
      ],

      if (!_isFactoryPickup) ...[
        DropdownButtonFormField<int>(
          value: _driverId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Assign Driver',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int>(
                value: null, child: Text('Unassigned')),
            ...data.drivers.map(
              (d) => DropdownMenuItem<int>(
                value: d.id,
                child: Text(d.name, overflow: TextOverflow.ellipsis),
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
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Contact Phone (optional)',
            helperText: 'The driver texts this number',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
      ],

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

      // A single delivery can join an existing batch — new batches are made
      // with the "Batch" mode toggle above, not here.
      if (!_isFactoryPickup)
        DropdownButtonFormField<int>(
          value: _batchId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Add to Existing Batch (optional)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int>(value: null, child: Text('No batch')),
            ...data.batches
                .where((b) => b.status == 'building' || b.status == 'scheduled')
                .map(
                  (b) => DropdownMenuItem<int>(
                    value: b.id,
                    child: Text(
                      '${b.batchNumber} (${b.status})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
          ],
          onChanged:
              _submitting ? null : (v) => setState(() => _batchId = v),
        ),
    ];
  }

  Widget _typeChip(String value, String label) {
    final selected = _deliveryType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected:
          _submitting ? null : (_) => setState(() => _deliveryType = value),
    );
  }

  // ===========================================================================
  // BATCH DELIVERY
  // ===========================================================================
  List<Widget> _batchFields(DeliveryFormData data) {
    return [
      TextFormField(
        controller: _batchNumberCtrl,
        enabled: !_submitting,
        decoration: const InputDecoration(
          labelText: 'Batch Number',
          border: OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty)
            ? 'Batch number is required'
            : null,
      ),
      const SizedBox(height: 12),
      const Text('Batch Type', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _batchTypeChip('dealer', 'Dealer'),
          _batchTypeChip('bf_location', 'Bigfoot Location'),
        ],
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        value: _batchDriverId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Assign Driver',
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem<int>(value: null, child: Text('Unassigned')),
          ...data.drivers.map(
            (d) => DropdownMenuItem<int>(value: d.id, child: Text(d.name)),
          ),
        ],
        onChanged: (v) => setState(() => _batchDriverId = v),
      ),
      const SizedBox(height: 12),
      StockLocationChips(
        labelText: 'Destination Location',
        selectedLocationId: _batchDestinationLocationId,
        enabled: !_submitting,
        onChanged: (l) => setState(() {
          _batchDestinationLocationId = l.id;
          _batchDestNameCtrl.clear();
        }),
        helperText:
            'Pick a yard, or leave unselected and enter a destination name below.',
      ),
      if (_batchDestinationLocationId != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _submitting
                ? null
                : () => setState(() => _batchDestinationLocationId = null),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Clear yard, use custom name'),
          ),
        ),
      ],
      const SizedBox(height: 12),
      TextFormField(
        controller: _batchDestNameCtrl,
        enabled: _batchDestinationLocationId == null && !_submitting,
        decoration: const InputDecoration(
          labelText: 'Destination Name (for dealers)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Trailers  (${_selectedTrailerIds.length} selected)',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      _BatchTrailerPicker(
        trailers: data.trailers,
        selected: _selectedTrailerIds,
        enabled: !_submitting,
        onToggle: (id, on) => setState(() {
          if (on) {
            _selectedTrailerIds.add(id);
          } else {
            _selectedTrailerIds.remove(id);
          }
        }),
      ),
    ];
  }

  Widget _batchTypeChip(String value, String label) {
    final selected = _batchType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected:
          _submitting ? null : (_) => setState(() => _batchType = value),
    );
  }

  // ===========================================================================
  // SUBMIT
  // ===========================================================================
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_batchMode && _selectedTrailerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one trailer for the batch.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final vm = context.read<DeliveriesViewModel>();
      if (_batchMode) {
        await vm.createBatch(
          batchNumber: _batchNumberCtrl.text.trim(),
          batchType: _batchType,
          driverUserId: _batchDriverId,
          destinationLocationId: _batchDestinationLocationId,
          destinationName: _batchDestNameCtrl.text.trim(),
          trailerIds: _selectedTrailerIds.toList(),
        );
      } else {
        await vm.createDelivery(
          trailerId: _trailerId!,
          deliveryType: _deliveryType,
          driverUserId: _isFactoryPickup ? null : _driverId,
          destinationLocationId:
              _isFactoryPickup ? null : _destinationLocationId,
          customerDeliveryAddress:
              _isFactoryPickup || _destinationLocationId != null
                  ? null
                  : _addressCtrl.text.trim(),
          contactPhone: _isFactoryPickup ? null : _phoneCtrl.text.trim(),
          balanceDue: double.tryParse(_balanceCtrl.text.trim()),
          deliveryBatchId: _isFactoryPickup ? null : _batchId,
          pickedUpByName: _isFactoryPickup ? _pickedUpByCtrl.text.trim() : null,
          paymentCollected: _isFactoryPickup
              ? double.tryParse(_amountCtrl.text.trim())
              : null,
        );
      }
      if (!mounted) return;
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().contains('DELIVERY_NOT_DISPATCHABLE')
              ? 'A selected trailer is not ready for delivery'
              : 'Failed to create: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

/// Scrollable checklist of ready-for-delivery trailers for batch creation.
class _BatchTrailerPicker extends StatelessWidget {
  final List<Map<String, dynamic>> trailers;
  final Set<int> selected;
  final bool enabled;
  final void Function(int id, bool on) onToggle;

  const _BatchTrailerPicker({
    required this.trailers,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: Theme.of(context).dividerColor);

    if (trailers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            border: border, borderRadius: BorderRadius.circular(8)),
        child: const Text(
          'No ready-for-delivery trailers available.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration:
          BoxDecoration(border: border, borderRadius: BorderRadius.circular(8)),
      child: Scrollbar(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: trailers.length,
          itemBuilder: (_, i) {
            final t = trailers[i];
            final id = (t['id'] as num?)?.toInt();
            if (id == null) return const SizedBox.shrink();
            final so = (t['soNumber'] as String?) ?? 'SO-$id';
            final model =
                (t['trailerModel'] as Map<String, dynamic>?)?['displayName']
                    as String?;
            final loc = _trailerLocationLabel(t);
            return CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                model == null ? so : '$so — $model',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: loc == null
                  ? null
                  : Text('Stocked at $loc',
                      style: const TextStyle(fontSize: 12)),
              value: selected.contains(id),
              onChanged:
                  enabled ? (v) => onToggle(id, v ?? false) : null,
            );
          },
        ),
      ),
    );
  }
}
