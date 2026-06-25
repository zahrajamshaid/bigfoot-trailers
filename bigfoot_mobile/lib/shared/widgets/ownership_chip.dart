import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Visual category that drives an OwnershipChip's color + label.
enum OwnershipKind {
  /// Trailer is sold to a buyer — green chip with the buyer name.
  customer,
  /// Inventory at Mulberry / a yard — grey "STOCK" chip.
  openStock,
}

/// Compact pill identifying whether a trailer is a customer order (sold to
/// a buyer) or open stock. The backend now owns the decision: every queue
/// item + trailer-list row ships `isCustomerOrder` (bool) and `buyerName`
/// (String?) so the mobile renders directly without re-deriving the rule.
///
/// Rule, for reference (lives in production.service.ts and
/// trailers.service.ts → findAll):
///   isCustomerOrder = saleStatus === 'sold'
///   buyerName       = customer.name ?? soldToName
///
/// Use the [.fromSignals] adapter when you only have the raw fields handy
/// (older endpoints) — it falls back to the same client-side check so
/// no card has to plumb through both styles.
class OwnershipChip extends StatelessWidget {
  final bool isCustomerOrder;
  final String? buyerName;
  /// When true, drops the icon and tightens padding for header rows that
  /// already host other chips.
  final bool dense;

  const OwnershipChip({
    super.key,
    required this.isCustomerOrder,
    this.buyerName,
    this.dense = false,
  });

  /// Adapter for call sites that don't yet have the server-computed
  /// isCustomerOrder + buyerName fields. Mirrors the backend rule exactly
  /// so the visual is identical: saleStatus='sold' → customer, anything
  /// else → open stock.
  factory OwnershipChip.fromSignals({
    Key? key,
    required String? customerName,
    required bool isStockBuild,
    String? soldToName,
    String? saleStatus,
    bool dense = false,
  }) {
    final isCustomerOrder = saleStatus == 'sold';
    final buyer = (customerName?.trim().isNotEmpty == true
            ? customerName
            : soldToName)
        ?.trim();
    return OwnershipChip(
      key: key,
      isCustomerOrder: isCustomerOrder,
      buyerName: (buyer != null && buyer.isNotEmpty) ? buyer : null,
      dense: dense,
    );
  }

  OwnershipKind get _kind =>
      isCustomerOrder ? OwnershipKind.customer : OwnershipKind.openStock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, label) = _styleFor(_kind, buyerName);
    final hPad = dense ? 6.0 : 8.0;
    final vPad = dense ? 2.0 : 3.0;
    final iconSize = dense ? 10.0 : 12.0;
    final fontSize = dense ? 10.0 : 11.0;
    return ConstrainedBox(
      // Soft cap so a long buyer name doesn't push other badges off the
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
      case OwnershipKind.openStock:
        return (
          AppColors.disabled,
          Icons.inventory_2_outlined,
          'STOCK',
        );
    }
  }
}
