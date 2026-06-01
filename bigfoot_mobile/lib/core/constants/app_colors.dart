import 'package:flutter/material.dart';

/// Bigfoot Trailers brand color palette.
abstract final class AppColors {
  // ── Brand ───────────────────────────────────────────────────────────────
  static const Color navy = Color(0xFF1B3A4B);
  static const Color amber = Color(0xFFF4A300);
  static const Color white = Color(0xFFFFFFFF);

  // ── Semantic ────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF388E3C);
  static const Color warning = Color(0xFFFFA000);
  static const Color disabled = Color(0xFF9E9E9E);

  // ── Series badges ───────────────────────────────────────────────────────
  static const Color seriesXp = Color(0xFF1976D2);
  static const Color seriesYeti = Color(0xFF7B1FA2);
  static const Color seriesDeckOver = Color(0xFF388E3C);
  static const Color seriesGooseneck = Color(0xFFE65100);
  // Inventory-only (Triple Crown / Enclosed / Misc) — neutral teal so it
  // reads as "different category" without colliding with the four build series.
  static const Color seriesInventory = Color(0xFF00897B);
  // Gooseneck Yeti — magenta so it stands apart from the orange gooseneck
  // and the purple yeti, while still reading as part of the build-series
  // colour family (saturated, not neutral).
  static const Color seriesGooseneckYeti = Color(0xFFC2185B);

  // ── Status chips ────────────────────────────────────────────────────────
  static const Color statusPending = Color(0xFF9E9E9E);
  static const Color statusInProduction = Color(0xFF1976D2);
  static const Color statusReady = Color(0xFF388E3C);
  static const Color statusInTransit = Color(0xFFF4A300);
  static const Color statusDelivered = Color(0xFF00897B);
  static const Color statusOnHold = Color(0xFFD32F2F);

  // ── Surfaces ────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE0E0E0);
}
