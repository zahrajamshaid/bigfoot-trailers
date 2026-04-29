import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../viewmodel/deliveries_viewmodel.dart';
import '../../../shared/widgets/photo_capture_widget.dart';

class DeliveryCompleteScreen extends StatefulWidget {
  final int deliveryId;

  const DeliveryCompleteScreen({super.key, required this.deliveryId});

  @override
  State<DeliveryCompleteScreen> createState() => _DeliveryCompleteScreenState();
}

class _DeliveryCompleteScreenState extends State<DeliveryCompleteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _signatureCtrl = TextEditingController();
  final _gpsLatCtrl = TextEditingController();
  final _gpsLngCtrl = TextEditingController();

  String _paymentMethod = 'cashiers_check';
  bool _tcAccepted = false;
  bool _submitting = false;
  List<String> _photoStorageKeys = [];
  int _pendingPhotoCount = 0;
  int? _trailerId;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDelivery();
  }

  Future<void> _loadDelivery() async {
    try {
      final delivery =
          await context.read<DeliveriesViewModel>().getById(widget.deliveryId);
      if (!mounted) return;
      setState(() => _trailerId = delivery.trailerId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Failed to load delivery: $e');
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _signatureCtrl.dispose();
    _gpsLatCtrl.dispose();
    _gpsLngCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Complete Delivery')),
        body: Center(child: Text(_loadError!)),
      );
    }
    if (_trailerId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Complete Delivery')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Delivery')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount Collected',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Amount is required';
                if (double.tryParse(v) == null) return 'Invalid amount';
                return null;
              },
            ),
            const SizedBox(height: 12),
            const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w700)),
            RadioListTile<String>(
              value: 'cashiers_check',
              groupValue: _paymentMethod,
              onChanged: (v) => setState(() => _paymentMethod = v!),
              title: const Text("Cashier's Check"),
            ),
            RadioListTile<String>(
              value: 'debit',
              groupValue: _paymentMethod,
              onChanged: (v) => setState(() => _paymentMethod = v!),
              title: const Text('Debit'),
            ),
            RadioListTile<String>(
              value: 'cash',
              groupValue: _paymentMethod,
              onChanged: (v) => setState(() => _paymentMethod = v!),
              title: const Text('Cash'),
            ),
            const SizedBox(height: 12),
            PhotoCaptureWidget(
              fileType: 'delivery_photo',
              title: 'Proof of Delivery Photos',
              trailerId: _trailerId!,
              minPhotoCount: 1,
              onChanged: (snapshot) {
                setState(() {
                  _photoStorageKeys = snapshot.storageKeys;
                  _pendingPhotoCount = snapshot.pendingCount;
                });
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _signatureCtrl,
              decoration: const InputDecoration(
                labelText: 'Digital Signature URL (scaffold)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _gpsLatCtrl,
                    decoration: const InputDecoration(
                      labelText: 'GPS Lat',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _gpsLngCtrl,
                    decoration: const InputDecoration(
                      labelText: 'GPS Lng',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _tcAccepted,
              onChanged: (v) => setState(() => _tcAccepted = v ?? false),
              title: const Text('I confirm terms & conditions were accepted'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Complete Delivery'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photoStorageKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one proof photo is required')),
      );
      return;
    }

    if (_pendingPhotoCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait for pending photo uploads to finish')),
      );
      return;
    }

    if (!_tcAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept terms & conditions')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await context.read<DeliveriesViewModel>().completeDelivery(
            deliveryId: widget.deliveryId,
            paymentCollected: double.parse(_amountCtrl.text.trim()),
            paymentMethod: _paymentMethod,
            tcAccepted: _tcAccepted,
            signatureUrl: _signatureCtrl.text.trim().isEmpty
                ? null
                : _signatureCtrl.text.trim(),
            gpsLat: double.tryParse(_gpsLatCtrl.text.trim()),
            gpsLng: double.tryParse(_gpsLngCtrl.text.trim()),
            photoStorageKeys: _photoStorageKeys,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery completed successfully')),);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete delivery: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
