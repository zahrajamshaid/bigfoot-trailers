import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/location.dart' as loc_model;
import '../../../data/models/user.dart';
import '../../../domain/repositories/location_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/trailers_viewmodel.dart';
import '../../../shared/widgets/hover_tap.dart';
import '../../../shared/widgets/status_badge.dart';

class TrailerListScreen extends StatefulWidget {
  /// Optional status filter applied on first load — set by dashboard deep
  /// links such as `?status=ready_for_delivery`.
  final String? initialStatus;
  final String? initialCompletedSince;

  /// When true the list opens with the "Hot Only" filter applied
  /// (`?hot=true` deep link).
  final bool initialHotOnly;

  const TrailerListScreen({
    super.key,
    this.initialStatus,
    this.initialHotOnly = false,
    this.initialCompletedSince,
  });

  @override
  State<TrailerListScreen> createState() => _TrailerListScreenState();
}

class _TrailerListScreenState extends State<TrailerListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  // Cached on first build via LocationRepository — used to render the
  // location filter chips (Mul / Jax / VA / GA / TAL).
  List<loc_model.Location> _locations = const [];

  @override
  void initState() {
    super.initState();
    context.read<TrailersViewModel>().load(
          status: widget.initialStatus,
          hotOnly: widget.initialHotOnly,
          completedSince: widget.initialCompletedSince,
        );
    _scrollController.addListener(_onScroll);
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      // Use getAllLocations (not stock-only) so the factory chip — Mul for
      // Mulberry — also appears as a filter alongside the yards.
      final items =
          await context.read<LocationRepository>().getAllLocations();
      if (!mounted) return;
      setState(() => _locations = items);
    } catch (_) {
      // Filters are non-critical — silently skip if the fetch fails.
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<TrailersViewModel>().loadMore();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final authState = context.watch<AuthViewModel>().state;
    // Mirror the backend gate (trailers.controller.ts POST /trailers):
    // owner + production_manager + sales. Sales lands customer orders and
    // drops the SO into production directly.
    final canCreate = authState is Authenticated &&
        (authState.user.role == UserRole.owner ||
            authState.user.role == UserRole.productionManager ||
            authState.user.role == UserRole.sales);

    return Scaffold(
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (q) => context.read<TrailersViewModel>().searchDebounced(q),
              decoration: InputDecoration(
                hintText: loc.trailersSearchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          context.read<TrailersViewModel>().searchDebounced('');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),

          // Filter chips
          BlocBuilder<TrailersViewModel, TrailersState>(
            builder: (context, state) {
              final cubit = context.read<TrailersViewModel>();
              final statusFilter =
                  state is TrailersLoaded ? state.statusFilter : null;
              final seriesFilter =
                  state is TrailersLoaded ? state.seriesFilter : null;
              final locationFilter =
                  state is TrailersLoaded ? state.locationFilter : null;
              final saleStatusFilter =
                  state is TrailersLoaded ? state.saleStatusFilter : null;
              final hotOnly =
                  state is TrailersLoaded ? state.hotOnly : false;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    _FilterChip(
                      label: loc.trailersFilterHotOnly,
                      icon: Icons.local_fire_department,
                      selected: hotOnly,
                      color: AppColors.error,
                      onTap: cubit.toggleHotOnly,
                    ),
                    const SizedBox(width: 6),
                    ..._statusFilters(loc).map((f) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _FilterChip(
                            label: f.label,
                            selected: statusFilter == f.value,
                            color: f.color,
                            onTap: () => cubit.setStatusFilter(
                                statusFilter == f.value ? null : f.value),
                          ),
                        )),
                    const SizedBox(width: 4),
                    ..._seriesFilters.map((f) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _FilterChip(
                            label: f.label,
                            selected: seriesFilter == f.value,
                            color: f.color,
                            onTap: () => cubit.setSeriesFilter(
                                seriesFilter == f.value ? null : f.value),
                          ),
                        )),
                    const SizedBox(width: 4),
                    ..._saleFilters(loc).map((f) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _FilterChip(
                            label: f.label,
                            icon: f.icon,
                            selected: saleStatusFilter == f.value,
                            color: f.color,
                            onTap: () => cubit.setSaleStatusFilter(
                                saleStatusFilter == f.value ? null : f.value),
                          ),
                        )),
                    if (_locations.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      ..._locations.map((locItem) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _FilterChip(
                              label: locItem.chipLabel,
                              icon: Icons.location_on_outlined,
                              selected: locationFilter == locItem.id,
                              color: AppColors.navy,
                              onTap: () => cubit.setLocationFilter(
                                  locationFilter == locItem.id
                                      ? null
                                      : locItem.id),
                            ),
                          )),
                    ],
                  ],
                ),
              );
            },
          ),

          const Divider(height: 1),

          // Trailer list
          Expanded(
            child: BlocBuilder<TrailersViewModel, TrailersState>(
              builder: (context, state) {
                return switch (state) {
                  TrailersInitial() ||
                  TrailersLoading() =>
                    const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.amber)),
                  TrailersError(message: final msg) => SingleChildScrollView(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: AppColors.error),
                            const SizedBox(height: 12),
                            Text(msg),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  context.read<TrailersViewModel>().load(),
                              child: Text(loc.commonRetry),
                            ),
                          ],
                        ),
                      ),
                    ),
                  TrailersLoaded(
                    trailers: final trailers,
                    isLoadingMore: final loadingMore,
                    fromCache: final fromCache,
                    lastUpdated: final lastUpdated,
                  ) =>
                    trailers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_shipping_outlined,
                                    size: 56, color: AppColors.disabled),
                                const SizedBox(height: 12),
                                Text(loc.trailersEmpty,
                                    style: const TextStyle(
                                        color: AppColors.disabled)),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.amber,
                            onRefresh: () =>
                                context.read<TrailersViewModel>().load(),
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(
                                  top: 4, bottom: 80),
                              itemCount:
                                  trailers.length +
                                      (loadingMore ? 1 : 0) +
                                      (fromCache ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (fromCache && i == 0) {
                                  return _CacheInfoBanner(lastUpdated: lastUpdated);
                                }

                                final trailerIndex = fromCache ? i - 1 : i;

                                if (trailerIndex >= trailers.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                  );
                                }
                                return _TrailerCard(
                                  trailer: trailers[trailerIndex],
                                  onTap: () => context.push(
                                      '/trailers/${trailers[trailerIndex].id}'),
                                );
                              },
                            ),
                          ),
                };
              },
            ),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => context.push('/trailers/create'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _CacheInfoBanner extends StatelessWidget {
  const _CacheInfoBanner({required this.lastUpdated});

  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final minutes = lastUpdated == null
        ? null
        : now.difference(lastUpdated!).inMinutes;
    final updatedText = minutes == null
        ? l.cacheBannerUnknownTime
        : minutes <= 0
            ? l.cacheBannerJustNow
            : l.cacheBannerMinutesAgo(minutes);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_outlined, size: 18, color: AppColors.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.cacheBannerMessage(updatedText),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Trailer card ─────────────────────────────────────────────────────────────

class _TrailerCard extends StatelessWidget {
  final dynamic trailer; // Trailer model
  final VoidCallback onTap;

  const _TrailerCard({required this.trailer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = trailer;
    final series = t.trailerModel?.series ?? '';
    final modelName = t.trailerModel?.displayName ?? '';
    final customerName = t.customer?.name ??
        (t.soldToName as String?) ??
        (t.isStockBuild ? l.trailersStockBuild : '');

    // A customer trailer is sold by definition; otherwise use the stored flag.
    final saleStatus = t.customer != null
        ? 'sold'
        : ((t.saleStatus as String?) ?? 'available');

    // Active production step (now populated by the list endpoint).
    String stepIndicator = '';
    if (t.productionSteps != null && (t.productionSteps as List).isNotEmpty) {
      final steps = t.productionSteps as List;
      final activeStep = steps.where((s) => s.status == 'active').toList();
      if (activeStep.isNotEmpty) {
        final s = activeStep.first;
        final dept =
            (s.departmentName ?? s.departmentCode ?? '') as String;
        stepIndicator = l.trailersStepIndicator(s.stepOrder as int, 12, dept);
      }
    }

    // Location + short label (Mul / Jax / VA / GA / TAL).
    final loc = t.currentLocation;
    final locShort = loc?.shortLabel as String?;
    final locName = loc?.name as String?;

    final notes = (t.optionsNotes as String?)?.trim();
    final special = (t.specialNote as String?)?.trim();
    final hasNotes = notes != null && notes.isNotEmpty;
    final hasSpecial = special != null && special.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: t.isHot
                ? const Border(left: BorderSide(color: AppColors.error, width: 4))
                : null,
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: SO# + series badge + hot icon + priority
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.soNumber,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  if (series.isNotEmpty) ...[
                    SeriesBadge(series: series),
                    const SizedBox(width: 6),
                  ],
                  if (t.isHot)
                    const Icon(Icons.local_fire_department,
                        color: AppColors.error, size: 20),
                  if (t.globalPriority < 9999) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#${t.globalPriority}',
                        style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),

              // Row 2: Model + sale-status badge + production status badge
              Row(
                children: [
                  if (modelName.isNotEmpty) ...[
                    Expanded(
                      child: Text(modelName,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.disabled)),
                    ),
                  ] else
                    const Spacer(),
                  if (saleStatus != 'available') ...[
                    SaleStatusBadge(saleStatus: saleStatus),
                    const SizedBox(width: 6),
                  ],
                  StatusBadge(status: t.status),
                ],
              ),

              // Row 3: Customer + color/size summary
              if (customerName.isNotEmpty ||
                  t.color != null ||
                  t.size != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (customerName.isNotEmpty)
                      Expanded(
                        child: Text(
                          customerName,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (t.color != null || t.size != null)
                      Text(
                        [t.color, t.size]
                            .where((e) => e != null)
                            .join(' / '),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.disabled),
                      ),
                  ],
                ),
              ],

              // Row 4: Active step (department) — newly populated by the
              // expanded list select on the backend.
              if (stepIndicator.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.play_circle_outline,
                        size: 14, color: AppColors.statusInProduction),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        stepIndicator,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.statusInProduction,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              // Row 5: Yard / location with short-label badge.
              if (locName != null && locName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: AppColors.navy),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        locName,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (locShort != null && locShort.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: AppColors.navy.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          locShort,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // Options/notes — clipped to 2 lines.
              if (hasNotes) ...[
                const SizedBox(height: 8),
                _NotesLine(
                  icon: Icons.notes_outlined,
                  text: notes,
                  color: AppColors.navy,
                ),
              ],

              // Special note — amber accent so it stands out.
              if (hasSpecial) ...[
                const SizedBox(height: 6),
                _NotesLine(
                  icon: Icons.sticky_note_2_outlined,
                  text: special,
                  color: AppColors.amber,
                  emphasized: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact, two-line note row for the trailer card. Long content is clipped
/// with an ellipsis so the card height stays bounded — the full text is on
/// the trailer detail Info tab.
class _NotesLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool emphasized;

  const _NotesLine({
    required this.icon,
    required this.text,
    required this.color,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: emphasized ? AppColors.navy : null,
              fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Filter chip ──────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? color : AppColors.disabled),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? color : AppColors.disabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter data ──────────────────────────────────────────────────────────────

List<({String label, String value, Color color})> _statusFilters(
    AppLocalizations l) {
  return [
    (label: l.statusPending, value: 'pending_production', color: AppColors.statusPending),
    (label: l.statusInProduction, value: 'in_production', color: AppColors.statusInProduction),
    (label: l.statusReady, value: 'ready_for_delivery', color: AppColors.statusReady),
    (label: l.statusInTransit, value: 'in_transit', color: AppColors.statusInTransit),
    (label: l.statusDelivered, value: 'delivered', color: AppColors.statusDelivered),
  ];
}

// Series labels are brand/product identifiers — kept as-is in both locales.
// "Inventory" covers the workflow-less models (Triple Crown / Enclosed /
// Misc) so admin / sales can filter to just those types.
const _seriesFilters = [
  (label: 'XP', value: 'xp', color: AppColors.seriesXp),
  (label: 'Yeti', value: 'yeti', color: AppColors.seriesYeti),
  (label: 'Deck Over', value: 'deck_over', color: AppColors.seriesDeckOver),
  (label: 'Gooseneck', value: 'gooseneck_dump', color: AppColors.seriesGooseneck),
  (label: 'GN Yeti', value: 'gooseneck_yeti', color: AppColors.seriesGooseneckYeti),
  (label: 'Inventory', value: 'inventory', color: AppColors.seriesInventory),
];

List<({String label, String value, Color color, IconData icon})> _saleFilters(
    AppLocalizations l) {
  return [
    (
      label: l.saleStatusAvailable,
      value: 'available',
      color: AppColors.disabled,
      icon: Icons.inventory_2_outlined,
    ),
    (
      label: l.saleStatusSalePendingLong,
      value: 'sale_pending',
      color: AppColors.warning,
      icon: Icons.pending_actions,
    ),
    (
      label: l.saleStatusSoldLong,
      value: 'sold',
      color: AppColors.success,
      icon: Icons.sell,
    ),
  ];
}
