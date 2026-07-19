import 'package:flutter/material.dart';

/// Coloured pill for a Sales Order lifecycle status. The underlying value is
/// still `approved` (DB + API), but sales sees it as "Quoted" — "approved" read
/// too close to the customer *accepting*, which is a different, later step.
/// draft → approved(=Quoted) → in_production → ready → delivered / cancelled.
class SoStatusChip extends StatelessWidget {
  final String status;
  const SoStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'draft' => ('Draft', Colors.grey),
      'approved' => ('Quoted', Colors.blue),
      'in_production' => ('In production', Colors.orange),
      'ready' => ('Ready', Colors.teal),
      'delivered' => ('Delivered', Colors.green),
      'cancelled' => ('Cancelled', Colors.red),
      _ => (status, Colors.grey),
    };
    return _pill(label, color);
  }
}

/// Coloured pill for the QuickBooks sync state (pending / synced / error).
class SyncStateChip extends StatelessWidget {
  final String state;
  const SyncStateChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      'synced' => ('QuickBooks', Colors.green, Icons.cloud_done_outlined),
      'error' => ('Sync error', Colors.red, Icons.sync_problem),
      _ => ('Not synced', Colors.grey, Icons.cloud_off_outlined),
    };
    return _pill(label, color, icon: icon);
  }
}

Widget _pill(String label, Color color, {IconData? icon}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      ],
    ),
  );
}
