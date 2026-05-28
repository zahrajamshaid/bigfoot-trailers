import 'package:flutter/material.dart';

import '../../../data/models/delivery.dart';
import '../../../l10n/generated/app_localizations.dart';

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
        setState(() =>
            _error = AppLocalizations.of(context).payrollDrValidNumber);
        return;
      }
    }
    Navigator.pop(context, CompleteDeliveryResult(paymentCollected: collected));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = widget.delivery;
    final balanceDue = d.balanceDue ?? 0;

    return AlertDialog(
      title: Text(l.completeDeliveryDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l.deliveryDetailSo(d.soNumber)} → ${d.destinationLabel}',
          ),
          if (balanceDue > 0) ...[
            const SizedBox(height: 12),
            Text(
              '${l.deliveryDetailSectionBalance}: \$${balanceDue.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _collectedCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l.completeDeliveryPaymentLabel,
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
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(l.driverMarkDelivered),
        ),
      ],
    );
  }
}
