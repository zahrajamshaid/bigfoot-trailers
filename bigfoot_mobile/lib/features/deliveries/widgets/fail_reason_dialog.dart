import 'package:flutter/material.dart';

/// Prompts for a delivery-failure reason.
///
/// Returns the trimmed reason, or `null` if the user cancelled. The Confirm
/// button stays disabled until a reason is typed, so this never returns an
/// empty string — the backend rejects a blank reason, and an empty-confirm
/// previously looked like "nothing happened".
Future<String?> showFailReasonDialog(
  BuildContext context, {
  required String title,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final controller = TextEditingController();
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final hasText = controller.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
              onChanged: (_) => setLocal(() {}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: hasText
                    ? () => Navigator.pop(ctx, controller.text.trim())
                    : null,
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      );
    },
  );
}
