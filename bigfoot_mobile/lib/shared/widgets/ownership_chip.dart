import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Visual category that drives an OwnershipChip's color + label.
enum OwnershipKind {
  /// Customer-order trailer (created with a customer attached).
  customer,
  /// Stock build that has been sold to a buyer (soldToName populated).
  soldStock,
  /// Stock build that has not been sold yet.
  openStock,
}

/// Resolves the right OwnershipKind for the given trailer signals. Pass
/// nullable strings + isStockBuild; callers don't need to write this branch
/// at every call site.
OwnershipKind resolveOwnership({
  required String? customerName,
  required bool isStockBuild,
  String? soldToName,
}) {
  if (customerName != null && customerName.trim().isNotEmpty) {
    return OwnershipKind.customer;
  }
  if (isStockBuild &&
      soldToName != null &&
      soldToName.trim().isNotEmpty) {
    return OwnershipKind.soldStock;
  }
  return OwnershipKind.openStock;
}

/// Compact pill identifying whether a trailer is a customer order, a sold
/// stock build, or an open stock build — plus the buyer/customer name when
/// one is present. Designed to read instantly on a queue tile so workers
/// don't have to drill into the trailer detail to know who they're building
/// for.
///
/// Use the [.fromSignals] constructor when you have the raw fields straight
/// from the queue item; the main constructor takes a pre-resolved [kind]
/// for callers that already know.
class OwnershipChip extends StatelessWidget {
  final OwnershipKind kind;
  /// Buyer / customer name to render on the pill. Optional — when null we
  /// fall back to the kind's static label ("STOCK" / "SOLD STOCK").
  final String? name;
  /// When true, drops the icon and tightens the padding for use inside
  /// already-busy header rows (e.g. the QC queue Wrap).
  final bool dense;

  const OwnershipChip({
    super.key,
    required this.kind,
    this.name,
    this.dense = false,
  });

  factory OwnershipChip.fromSignals({
    Key? key,
    required String? customerName,
    required bool isStockBuild,
    String? soldToName,
    bool dense = false,
  }) {
    final kind = resolveOwnership(
      customerName: customerName,
      isStockBuild: isStockBuild,
      soldToName: soldToName,
    );
    String? name;
    switch (kind) {
      case OwnershipKind.customer:
        name = customerName?.trim();
        break;
      case OwnershipKind.soldStock:
        name = soldToName?.trim();
        break;
      case OwnershipKind.openStock:
        name = null;
        break;
    }
    return OwnershipChip(key: key, kind: kind, name: name, dense: dense);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, label) = _styleFor(kind, name);
    final hPad = dense ? 6.0 : 8.0;
    final vPad = dense ? 2.0 : 3.0;
    final iconSize = dense ? 10.0 : 12.0;
    final fontSize = dense ? 10.0 : 11.0;
    return ConstrainedBox(
      // Soft cap so a long customer name doesn't push other badges off the
      // row; the ellipsis below kicks in when needed.
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!dense) ...[
              Icon(icon, size: iconSize, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  fontSize: fontSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, IconData, String) _styleFor(OwnershipKind k, String? name) {
    final trimmed = name?.trim();
    final hasName = trimmed != null && trimmed.isNotEmpty;
    switch (k) {
      case OwnershipKind.customer:
        return (
          AppColors.success,
          Icons.person_outline,
          hasName ? trimmed.toUpperCase() : 'CUSTOMER',
        );
      case OwnershipKind.soldStock:
        return (
          AppColors.amber,
          Icons.sell_outlined,
          hasName ? 'SOLD · ${trimmed.toUpperCase()}' : 'SOLD STOCK',
        );
      case OwnershipKind.openStock:
        return (
          AppColors.disabled,
          Icons.inventory_2_outlined,
          'STOCK',
        );
    }
  }
}
