import 'package:flutter/material.dart';

import '../../../data/models/delivery.dart';

/// Outcome of the complete-delivery dialog. A non-null result means the driver
/// confirmed; [paymentCollected] is the optional balance they recorded.
class CompleteDeliveryResult {
  final double? paymentCollected;
  const CompleteDeliveryResult({this.paymentCollected});
}

/// One-tap completion dialog with an optional "balance collected" field.
/// Returns `null` if the driver cancelled.
Future<CompleteDeliveryResult?> showCompleteDeliveryDialog(
  BuildContext context,
  Delivery delivery,
) {
  return showDialog<CompleteDeliveryResult>(
    context: context,
    builder: (_) => _CompleteDeliveryDialog(delivery: delivery),
  );
}

class _CompleteDeliveryDialog extends StatefulWidget {
  final Delivery delivery;
  const _CompleteDeliveryDialog({required this.delivery});

  @override
  State<_CompleteDeliveryDialog> createState() =>
      _CompleteDeliveryDialogState();
}

class _CompleteDeliveryDialogState extends State<_CompleteDeliveryDialog> {
  final _collectedCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _collectedCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final raw = _collectedCtrl.text.trim();
    double? collected;
    if (raw.isNotEmpty) {
      collected = double.tryParse(raw);
      if (collected == null || collected < 0) {
        setState(() => _error = 'Enter a valid amount, or leave blank');
        return;
      }
    }
    Navigator.pop(context, CompleteDeliveryResult(paymentCollected: collected));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    final balanceDue = d.balanceDue ?? 0;

    return AlertDialog(
      title: const Text('Complete Delivery'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm trailer ${d.soNumber} was delivered to ${d.destinationLabel}.',
          ),
          if (balanceDue > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Balance due: \$${balanceDue.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _collectedCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Balance Collected (optional)',
              prefixText: r'$ ',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Mark Delivered'),
        ),
      ],
    );
  }
}
