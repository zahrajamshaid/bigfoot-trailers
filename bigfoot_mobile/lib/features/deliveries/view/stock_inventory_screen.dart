import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/est_clock.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/stock_inventory.dart';
import '../viewmodel/deliveries_viewmodel.dart';

/// Stock inventory — trailers currently parked at each stock-location yard.
/// A trailer lands here when a delivery to that yard is marked complete, and
/// drops off once it is delivered out again.
class StockInventoryScreen extends StatefulWidget {
  const StockInventoryScreen({super.key});

  @override
  State<StockInventoryScreen> createState() => _StockInventoryScreenState();
}

class _StockInventoryScreenState extends State<StockInventoryScreen> {
  bool _loading = true;
  String? _error;
  List<StockLocationGroup> _groups = const [];

  // ── Filters ──────────────────────────────────────────────────────────────
  // All applied client-side against the in-memory groups so refresh stays
  // free and the result is instant. Null/empty = no filter.
  final _searchController = TextEditingController();
  String _search = '';
  int? _locationFilter; // location id
  String? _seriesFilter; // 'xp' | 'yeti' | ...
  String? _saleStatusFilter; // 'available' | 'sold'
  bool _hotOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups =
          await context.read<DeliveriesViewModel>().getStockInventory();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).stockInventoryLoadFail('$e');
        _loading = false;
      });
    }
  }

  /// Apply the active filter chips + search box to the loaded groups.
  /// Returns a fresh list of groups, each containing only the trailers
  /// that match; groups with no matching trailers are dropped.
  List<StockLocationGroup> _filteredGroups() {
    final s = _search.trim().toLowerCase();
    final out = <StockLocationGroup>[];
    for (final g in _groups) {
      if (_locationFilter != null && g.locationId != _locationFilter) continue;
      final filteredTrailers = g.trailers.where((t) {
        if (_seriesFilter != null && t.series != _seriesFilter) return false;
        if (_saleStatusFilter != null && t.saleStatus != _saleStatusFilter) {
          return false;
        }
        if (_hotOnly && !t.isHot) return false;
        if (s.isNotEmpty) {
          final hay = [
            t.soNumber,
            t.model ?? '',
            t.customerName ?? '',
            t.sizeFt ?? '',
          ].join(' ').toLowerCase();
          if (!hay.contains(s)) return false;
        }
        return true;
      }).toList();
      if (filteredTrailers.isEmpty) continue;
      out.add(StockLocationGroup(
        locationId: g.locationId,
        code: g.code,
        name: g.name,
        city: g.city,
        state: g.state,
        count: filteredTrailers.length,
        trailers: filteredTrailers,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).stockInventoryTitle)),
      body: Column(
        children: [
          _FilterBar(
            controller: _searchController,
            search: _search,
            onSearchChanged: (v) => setState(() => _search = v),
            groups: _groups,
            locationFilter: _locationFilter,
            seriesFilter: _seriesFilter,
            saleStatusFilter: _saleStatusFilter,
            hotOnly: _hotOnly,
            onLocationChanged: (id) => setState(() => _locationFilter = id),
            onSeriesChanged: (s) => setState(() => _seriesFilter = s),
            onSaleStatusChanged: (s) => setState(() => _saleStatusFilter = s),
            onHotToggle: () => setState(() => _hotOnly = !_hotOnly),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.amber));
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 44, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: Text(AppLocalizations.of(context).commonRetry),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final groups = _filteredGroups();
    if (groups.isEmpty) {
      final emptyAfterFilters = _groups.isNotEmpty;
      return ListView(
        children: [
          const SizedBox(height: 140),
          Center(
            child: Text(
              emptyAfterFilters
                  ? 'No trailers match the current filters.'
                  : AppLocalizations.of(context).stockInventoryEmptyBody,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (_, i) => _LocationSection(group: groups[i]),
    );
  }
}

/// Filter bar above the stock inventory list. Search box + chip rows for
/// yard, series, sale status, and Hot-only. All filtering runs in-memory
/// against the already-loaded groups, so no network round-trips.
class _FilterBar extends StatelessWidget {
  final TextEditingController controller;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final List<StockLocationGroup> groups;
  final int? locationFilter;
  final String? seriesFilter;
  final String? saleStatusFilter;
  final bool hotOnly;
  final ValueChanged<int?> onLocationChanged;
  final ValueChanged<String?> onSeriesChanged;
  final ValueChanged<String?> onSaleStatusChanged;
  final VoidCallback onHotToggle;

  const _FilterBar({
    required this.controller,
    required this.search,
    required this.onSearchChanged,
    required this.groups,
    required this.locationFilter,
    required this.seriesFilter,
    required this.saleStatusFilter,
    required this.hotOnly,
    required this.onLocationChanged,
    required this.onSeriesChanged,
    required this.onSaleStatusChanged,
    required this.onHotToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search SO, model, customer, size…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        controller.clear();
                        onSearchChanged('');
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _Chip(
                  label: 'Hot only',
                  icon: Icons.local_fire_department,
                  selected: hotOnly,
                  color: AppColors.error,
                  onTap: onHotToggle,
                ),
                const SizedBox(width: 6),
                // Yards — built from whatever loaded so we never offer a
                // yard with zero trailers.
                ..._yardChips(),
                const SizedBox(width: 6),
                ..._seriesChips(),
                const SizedBox(width: 6),
                _Chip(
                  label: 'Available',
                  selected: saleStatusFilter == 'available',
                  color: AppColors.disabled,
                  onTap: () => onSaleStatusChanged(
                      saleStatusFilter == 'available' ? null : 'available'),
                ),
                const SizedBox(width: 6),
                _Chip(
                  label: 'Sold',
                  icon: Icons.sell,
                  selected: saleStatusFilter == 'sold',
                  color: AppColors.success,
                  onTap: () => onSaleStatusChanged(
                      saleStatusFilter == 'sold' ? null : 'sold'),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _yardChips() {
    return [
      for (final g in groups) ...[
        _Chip(
          label: g.code.isNotEmpty ? g.code : g.name,
          icon: Icons.warehouse_outlined,
          selected: locationFilter == g.locationId,
          color: AppColors.navy,
          onTap: () => onLocationChanged(
              locationFilter == g.locationId ? null : g.locationId),
        ),
        const SizedBox(width: 6),
      ],
    ];
  }

  List<Widget> _seriesChips() {
    const series = [
      ('XP', 'xp'),
      ('Yeti', 'yeti'),
      ('Deck Over', 'deck_over'),
      ('Gooseneck', 'gooseneck_dump'),
      ('GN Yeti', 'gooseneck_yeti'),
      ('Inventory', 'inventory'),
    ];
    return [
      for (final (label, value) in series) ...[
        _Chip(
          label: label,
          selected: seriesFilter == value,
          color: AppColors.navy,
          onTap: () =>
              onSeriesChanged(seriesFilter == value ? null : value),
        ),
        const SizedBox(width: 6),
      ],
    ];
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color.withValues(alpha: 0.15) : Colors.transparent;
    final border = selected ? color : AppColors.divider;
    final fg = selected ? color : AppColors.disabled;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// A collapsible yard — tap the header to expand the list of trailers parked
/// there.
class _LocationSection extends StatelessWidget {
  final StockLocationGroup group;
  const _LocationSection({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Drop the ExpansionTile's default divider lines.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.warehouse_outlined, color: AppColors.navy),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${group.count}',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          subtitle: group.city.isNotEmpty
              ? Text(
                  '${group.city}, ${group.state}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.disabled),
                )
              : null,
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          children: group.trailers
              .map((t) => _StockTrailerCard(trailer: t))
              .toList(),
        ),
      ),
    );
  }
}

class _StockTrailerCard extends StatelessWidget {
  final StockTrailer trailer;
  const _StockTrailerCard({required this.trailer});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = trailer;
    final date = t.deliveredAt != null
        ? EstClock.date(t.deliveredAt!)
        : l.stockInventoryUnknownDate;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // Tapping a trailer opens its full detail screen.
          onTap: () => context.pushNamed(
            RouteNames.trailerDetail,
            pathParameters: {'id': t.trailerId.toString()},
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.soNumber,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 20, color: AppColors.disabled),
                  ],
                ),
                if ((t.model ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      t.model!,
                      if ((t.sizeFt ?? '').isNotEmpty) '${t.sizeFt}ft',
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.disabled),
                  ),
                ] else if ((t.sizeFt ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('${t.sizeFt}ft',
                      style: const TextStyle(color: AppColors.disabled)),
                ],
                const SizedBox(height: 8),
                _InfoRow(
                    icon: Icons.event_outlined,
                    label: l.stockInventoryDelivered,
                    value: date),
                if ((t.deliveredBy ?? '').isNotEmpty)
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: l.stockInventoryDeliveredBy,
                    value: t.deliveredBy!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.disabled),
          const SizedBox(width: 6),
          Text('$label: ',
              style: const TextStyle(fontSize: 13, color: AppColors.disabled)),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
