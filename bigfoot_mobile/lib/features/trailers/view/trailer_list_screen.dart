import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/user.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/trailers_viewmodel.dart';
import '../../../shared/widgets/status_badge.dart';

class TrailerListScreen extends StatefulWidget {
  const TrailerListScreen({super.key});

  @override
  State<TrailerListScreen> createState() => _TrailerListScreenState();
}

class _TrailerListScreenState extends State<TrailerListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    context.read<TrailersViewModel>().load();
    _scrollController.addListener(_onScroll);
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
    final authState = context.watch<AuthViewModel>().state;
    final canCreate = authState is Authenticated &&
        (authState.user.role == UserRole.owner ||
            authState.user.role == UserRole.productionManager);

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
                hintText: 'Search by SO number...',
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
              final hotOnly =
                  state is TrailersLoaded ? state.hotOnly : false;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Hot Only',
                      icon: Icons.local_fire_department,
                      selected: hotOnly,
                      color: AppColors.error,
                      onTap: cubit.toggleHotOnly,
                    ),
                    const SizedBox(width: 6),
                    ..._statusFilters.map((f) => Padding(
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
                  TrailersError(message: final msg) => Center(
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
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  TrailersLoaded(
                    trailers: final trailers,
                    isLoadingMore: final loadingMore,
                  ) =>
                    trailers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_shipping_outlined,
                                    size: 56, color: AppColors.disabled),
                                const SizedBox(height: 12),
                                Text('No trailers found',
                                    style: TextStyle(color: AppColors.disabled)),
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
                                  trailers.length + (loadingMore ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i >= trailers.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                  );
                                }
                                return _TrailerCard(
                                  trailer: trailers[i],
                                  onTap: () => context.go(
                                      '/trailers/${trailers[i].id}'),
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
              onPressed: () => context.go('/trailers/create'),
              child: const Icon(Icons.add),
            )
          : null,
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
    final t = trailer;
    final series = t.trailerModel?.series ?? '';
    final modelName = t.trailerModel?.displayName ?? '';
    final customerName = t.customer?.name ?? (t.isStockBuild ? 'Stock Build' : '');

    // Find active step
    String stepIndicator = '';
    if (t.productionSteps != null && (t.productionSteps as List).isNotEmpty) {
      final steps = t.productionSteps as List;
      final activeStep = steps.where((s) => s.status == 'active').toList();
      if (activeStep.isNotEmpty) {
        final s = activeStep.first;
        stepIndicator =
            'Step ${s.stepOrder}/12 — ${s.departmentName ?? s.departmentCode ?? ''}';
      }
    }

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
              // Row 1: SO# + series badge + hot icon
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

              // Row 2: Model + status
              Row(
                children: [
                  if (modelName.isNotEmpty) ...[
                    Text(modelName,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.disabled)),
                    const Spacer(),
                  ],
                  StatusBadge(status: t.status),
                ],
              ),

              // Row 3: Customer + color/size
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
                          style: const TextStyle(fontSize: 13),
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

              // Row 4: Step indicator
              if (stepIndicator.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.play_circle_outline,
                        size: 14, color: AppColors.statusInProduction),
                    const SizedBox(width: 4),
                    Text(
                      stepIndicator,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.statusInProduction,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
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
    return GestureDetector(
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

const _statusFilters = [
  (label: 'Pending', value: 'pending_production', color: AppColors.statusPending),
  (label: 'In Production', value: 'in_production', color: AppColors.statusInProduction),
  (label: 'Ready', value: 'ready_for_delivery', color: AppColors.statusReady),
  (label: 'In Transit', value: 'in_transit', color: AppColors.statusInTransit),
  (label: 'Delivered', value: 'delivered', color: AppColors.statusDelivered),
];

const _seriesFilters = [
  (label: 'XP', value: 'xp', color: AppColors.seriesXp),
  (label: 'Yeti', value: 'yeti', color: AppColors.seriesYeti),
  (label: 'Deck Over', value: 'deck_over', color: AppColors.seriesDeckOver),
  (label: 'Gooseneck', value: 'gooseneck_dump', color: AppColors.seriesGooseneck),
];
