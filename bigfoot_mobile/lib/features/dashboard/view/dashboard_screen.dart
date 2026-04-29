import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/layout/responsive.dart';
import '../../../data/models/user.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/dashboard_viewmodel.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/activity_feed.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthViewModel>().state;
    final user = authState is Authenticated ? authState.user : null;
    final role = user?.role ?? 'worker';

    return BlocBuilder<DashboardViewModel, DashboardState>(
      builder: (context, state) {
        return RefreshIndicator(
          color: AppColors.amber,
          onRefresh: () => context.read<DashboardViewModel>().refresh(),
          child: switch (state) {
            DashboardInitial() || DashboardLoading() => const Center(
                child: CircularProgressIndicator(color: AppColors.amber),
              ),
            DashboardError(message: final msg) => _ErrorView(
                message: msg,
                onRetry: () => context.read<DashboardViewModel>().load(),
              ),
            DashboardLoaded(data: final data) => ResponsiveContent(
                padding: EdgeInsets.zero,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _Greeting(user: user),
                    switch (role) {
                      UserRole.owner || UserRole.productionManager =>
                        _ManagerDashboard(data: data),
                      UserRole.worker => _WorkerDashboard(data: data),
                      UserRole.qcInspector => _QcDashboard(data: data),
                      UserRole.driver => _DriverDashboard(data: data),
                      UserRole.transportManager =>
                        _TransportDashboard(data: data),
                      _ => _ManagerDashboard(data: data),
                    },
                    if (role == UserRole.owner ||
                        role == UserRole.productionManager)
                      ActivityFeed(items: data.recentActivity),
                  ],
                ),
              ),
          },
        );
      },
    );
  }
}

// ── Greeting header ──────────────────────────────────────────────────────────

class _Greeting extends StatelessWidget {
  final User? user;
  const _Greeting({this.user});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$greeting,',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.disabled,
                ),
          ),
          Text(
            user?.name ?? 'User',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Owner / Production Manager ───────────────────────────────────────────────

class _ManagerDashboard extends StatelessWidget {
  final DashboardData data;
  const _ManagerDashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: r.pagePadding),
          child: GridView.count(
            crossAxisCount: r.gridColumns(compact: 2, medium: 3, expanded: 4, large: 4),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: r.statCardAspectRatio,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              StatCard(
                title: 'Active Trailers',
                value: '${data.activeTrailers}',
                icon: Icons.precision_manufacturing,
                color: AppColors.statusInProduction,
              ),
              StatCard(
                title: 'Ready for Delivery',
                value: '${data.readyForDelivery}',
                icon: Icons.local_shipping,
                color: AppColors.success,
              ),
              StatCard(
                title: 'Hot Trailers',
                value: '${data.hotTrailers}',
                icon: Icons.local_fire_department,
                color: AppColors.error,
                badge: data.hotTrailers > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('HOT',
                            style: TextStyle(
                                color: AppColors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      )
                    : null,
              ),
              StatCard(
                title: 'Stalled Steps',
                value: '${data.stalledSteps}',
                icon: Icons.warning_amber,
                color: AppColors.warning,
                badge: data.stalledSteps > 0
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.warning,
                        ),
                      )
                    : null,
              ),
              StatCard(
                title: 'Completed This Week',
                value: '${data.weeklyCompleted}',
                icon: Icons.check_circle_outline,
                color: AppColors.statusDelivered,
              ),
              StatCard(
                title: 'QC Fail Rate',
                value: '${data.qcFailRate.toStringAsFixed(1)}%',
                icon: Icons.analytics_outlined,
                color: data.qcFailRate > 15 ? AppColors.error : AppColors.navy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Worker ────────────────────────────────────────────────────────────────────

class _WorkerDashboard extends StatelessWidget {
  final DashboardData data;
  const _WorkerDashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: r.pagePadding),
          child: GridView.count(
            crossAxisCount: r.gridColumns(compact: 2, medium: 3, expanded: 3, large: 3),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: r.statCardAspectRatio,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              StatCard(
                title: 'My Queue',
                value: '${data.myQueueCount}',
                icon: Icons.queue,
                color: AppColors.navy,
              ),
              StatCard(
                title: 'Points Today',
                value: data.myPointsToday.toStringAsFixed(1),
                icon: Icons.star,
                color: AppColors.amber,
              ),
              StatCard(
                title: 'Points This Week',
                value: data.myPointsWeek.toStringAsFixed(1),
                icon: Icons.emoji_events,
                color: AppColors.success,
              ),
            ],
          ),
        ),
        if (data.nextTrailerSo != null)
          WideStatCard(
            title: 'Next Trailer',
            value: data.nextTrailerSo!,
            subtitle: data.nextTrailerColor,
            icon: Icons.arrow_forward,
            color: AppColors.navy,
          ),
      ],
    );
  }
}

// ── QC Inspector ─────────────────────────────────────────────────────────────

class _QcDashboard extends StatelessWidget {
  final DashboardData data;
  const _QcDashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.pagePadding),
      child: GridView.count(
        crossAxisCount: r.gridColumns(compact: 2, medium: 4, expanded: 4, large: 4),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: r.statCardAspectRatio,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          StatCard(
            title: 'Pending Inspections',
            value: '${data.pendingInspections}',
            icon: Icons.pending_actions,
            color: AppColors.navy,
          ),
          StatCard(
            title: 'Inspections Today',
            value: '${data.inspectionsToday}',
            icon: Icons.checklist,
            color: AppColors.success,
          ),
          StatCard(
            title: 'Fail Rate Today',
            value: '${data.failRateToday.toStringAsFixed(1)}%',
            icon: Icons.trending_down,
            color: data.failRateToday > 20 ? AppColors.error : AppColors.navy,
          ),
          StatCard(
            title: 'Rework Queue',
            value: '${data.reworkQueue}',
            icon: Icons.replay,
            color: AppColors.warning,
          ),
        ],
      ),
    );
  }
}

// ── Driver ────────────────────────────────────────────────────────────────────

class _DriverDashboard extends StatelessWidget {
  final DashboardData data;
  const _DriverDashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Column(
      children: [
        WideStatCard(
          title: 'Active Delivery',
          value: data.activeDeliveries > 0 ? 'In Transit' : 'None',
          subtitle: '${data.activeDeliveries} active',
          icon: Icons.local_shipping,
          color:
              data.activeDeliveries > 0 ? AppColors.amber : AppColors.disabled,
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: r.pagePadding),
          child: GridView.count(
            crossAxisCount: r.gridColumns(compact: 2, medium: 2, expanded: 4, large: 4),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: r.statCardAspectRatio,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              StatCard(
                title: 'Upcoming',
                value: '${data.upcomingDeliveries}',
                icon: Icons.schedule,
                color: AppColors.navy,
              ),
              StatCard(
                title: 'Completed This Week',
                value: '${data.completedThisWeek}',
                icon: Icons.check_circle_outline,
                color: AppColors.success,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Transport Manager ────────────────────────────────────────────────────────

class _TransportDashboard extends StatelessWidget {
  final DashboardData data;
  const _TransportDashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.pagePadding),
      child: GridView.count(
        crossAxisCount: r.gridColumns(compact: 2, medium: 3, expanded: 3, large: 3),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: r.statCardAspectRatio,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          StatCard(
            title: 'Scheduled',
            value: '${data.scheduledDeliveries}',
            icon: Icons.event_note,
            color: AppColors.navy,
          ),
          StatCard(
            title: 'In Transit',
            value: '${data.inTransitCount}',
            icon: Icons.local_shipping,
            color: AppColors.amber,
          ),
          StatCard(
            title: 'Ready for Pickup',
            value: '${data.readyForPickup}',
            icon: Icons.inventory,
            color: AppColors.success,
          ),
        ],
      ),
    );
  }
}

// ── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
