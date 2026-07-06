import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/dashboard_viewmodel.dart';
import '../../deliveries/view/driver_delivery_screen.dart';
import '../../../shared/widgets/stat_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthViewModel>().state;
    final user = authState is Authenticated ? authState.user : null;
    final role = user?.role ?? 'worker';

    // Drivers don't get a stat dashboard — their home is the live list of
    // deliveries assigned to them, with all actions inline.
    if (role == UserRole.driver) {
      return const DriverDeliveryList();
    }

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
                      UserRole.owner ||
                      UserRole.office ||
                      UserRole.productionManager =>
                        _ManagerDashboard(data: data),
                      UserRole.worker => _WorkerDashboard(data: data),
                      UserRole.qcInspector => _QcDashboard(data: data),
                      UserRole.transportManager =>
                        _TransportDashboard(data: data),
                      _ => _ManagerDashboard(data: data),
                    },
                    // QC's dashboard intentionally drops the stock-inventory
                    // strip — they're not part of the stack-to-yard flow and
                    // the card is just noise on their card list.
                    if (role == UserRole.owner ||
                        role == UserRole.office ||
                        role == UserRole.transportManager ||
                        role == UserRole.productionManager ||
                        role == UserRole.sales)
                      const _StockInventoryCard(),
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
    final l = AppLocalizations.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? l.dashboardGoodMorning
        : hour < 17
            ? l.dashboardGoodAfternoon
            : l.dashboardGoodEvening;

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
            user?.name ?? l.commonUser,
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
    final l = AppLocalizations.of(context);
    // The switch above falls through to _ManagerDashboard for roles without
    // their own dashboard (sales / parts / office / driver). Some tiles
    // deep-link into QC-only screens — hide those for non-managers so they
    // don't tap a tile that immediately bounces them via the /qc redirect.
    final authState = context.watch<AuthViewModel>().state;
    final role = authState is Authenticated ? authState.user.role : null;
    final canSeeQcTiles = role == UserRole.owner ||
        role == UserRole.office ||
        role == UserRole.productionManager;
    // Health Check tile is hidden for QC (they have their own dashboard
    // anyway, but this dashboard renders for the manager / office / owner
    // tier and shouldn't expose Health Check to QC by accident).
    final canSeeProductionReport = role == UserRole.owner ||
        role == UserRole.office ||
        role == UserRole.productionManager;
    // Build tiles up-front by section so each section can decide whether
    // it renders at all (skip empty sections instead of leaving a
    // dangling heading with no cards under it — happens when a role
    // doesn't see any QC tile, for instance).
    final productionTiles = <Widget>[
      StatCard(
        title: l.dashStatActiveTrailers,
        value: '${data.activeTrailers}',
        icon: Icons.precision_manufacturing,
        color: AppColors.statusInProduction,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'status': 'in_production'},
        ),
      ),
      StatCard(
        title: 'Pending production',
        value: '${data.pendingProduction}',
        icon: Icons.schedule_outlined,
        color: AppColors.statusPending,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'status': 'pending_production'},
        ),
      ),
      StatCard(
        title: l.dashStatHotTrailers,
        value: '${data.hotTrailers}',
        icon: Icons.local_fire_department,
        color: AppColors.error,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'hot': 'true'},
        ),
        badge: data.hotTrailers > 0
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(l.dashStatHotBadge,
                    style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              )
            : null,
      ),
      StatCard(
        title: l.dashStatStalledSteps,
        value: '${data.stalledSteps}',
        icon: Icons.warning_amber,
        color: AppColors.warning,
        onTap: () => context.goNamed(
          RouteNames.productionQueue,
          queryParameters: {'filter': 'stalled'},
        ),
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
        title: l.dashStatReadyForDelivery,
        value: '${data.readyForDelivery}',
        icon: Icons.local_shipping,
        color: AppColors.success,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'status': 'ready_for_delivery'},
        ),
      ),
      StatCard(
        title: l.dashStatCompletedThisWeek,
        value: '${data.weeklyCompleted}',
        icon: Icons.check_circle_outline,
        color: AppColors.statusDelivered,
        // Deep-link to the trailer list scoped to deliveries that
        // landed since the previous Sunday 00:00 UTC. Backend
        // matches on Delivery.deliveredAt so a stale record edit
        // doesn't shift a trailer into the window.
        onTap: () {
          final now = DateTime.now().toUtc();
          // weekday: Mon=1 … Sat=6, Sun=7 → 0 days back from Sunday.
          final daysBack = now.weekday % 7;
          final sunday =
              DateTime.utc(now.year, now.month, now.day - daysBack);
          context.goNamed(
            RouteNames.trailerList,
            queryParameters: {
              'status': 'delivered',
              'completedSince': sunday.toIso8601String(),
            },
          );
        },
      ),
      StatCard(
        title: 'Total trailers',
        value: '${data.totalTrailers}',
        icon: Icons.inventory_2_outlined,
        color: AppColors.navy,
        onTap: () => context.goNamed(RouteNames.trailerList),
      ),
      // Archived: deep-link to the trailers list with the Delivered
      // chip on. The list view already auto-hides delivered units
      // from other filters, so this is the one screen they show up
      // on — perfect "see every trailer we've ever shipped" entry.
      StatCard(
        title: 'Archived',
        value: '${data.archivedTotal}',
        icon: Icons.inventory_2_outlined,
        color: AppColors.disabled,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'status': 'delivered'},
        ),
      ),
    ];

    // QC fail rate: managers + owner see two tiles — today and
    // 30-day rolling — both with the raw fraction beside the percent so
    // a 100% rate off 1 inspection reads differently from 100% off 200.
    final qualityTiles = <Widget>[
      if (canSeeQcTiles)
        StatCard(
          title: 'QC fail today',
          value: data.inspectionsToday > 0
              ? '${data.failRateToday.toStringAsFixed(1)}% · '
                  '${data.failsToday}/${data.inspectionsToday}'
              : '0% · 0/0',
          icon: Icons.today_outlined,
          color:
              data.failRateToday > 20 ? AppColors.error : AppColors.navy,
          onTap: () => context.goNamed(RouteNames.qcFailed),
        ),
      if (canSeeQcTiles)
        StatCard(
          title: 'QC fail (30d)',
          value: data.qcFailRateInspections > 0
              ? '${data.qcFailRate.toStringAsFixed(1)}% · '
                  '${data.qcFailRateFails}/${data.qcFailRateInspections}'
              : '0% · 0/0',
          icon: Icons.analytics_outlined,
          color: data.qcFailRate > 15 ? AppColors.error : AppColors.navy,
          onTap: () => context.goNamed(RouteNames.qcFailed),
        ),
      if (canSeeQcTiles)
        StatCard(
          title: l.dashStatReworkQueue,
          value: '${data.reworkQueue}',
          icon: Icons.build_circle_outlined,
          color: data.reworkQueue > 0
              ? AppColors.amber
              : AppColors.navy,
          onTap: () => context.goNamed(RouteNames.qcRework),
        ),
    ];

    // Mulberry logistics — everyone on this dashboard sees both.
    final logisticsTiles = <Widget>[
      StatCard(
        title: 'Mulberry → Yards',
        value: '${data.mulberryStockTotal}',
        icon: Icons.local_shipping_outlined,
        color: AppColors.navy,
        onTap: () => _showMulberryYardSheet(context, data),
      ),
      StatCard(
        title: 'Customer Pickups @ Mulberry',
        value: '${data.mulberryCustomerPickups}',
        icon: Icons.directions_car_outlined,
        color: AppColors.amber,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {
            'status': 'ready_for_delivery',
            'currentLocationCode': 'MULBERRY',
            'isStockBuild': 'false',
            // Restrict to formally-sold customer orders so we
            // don't surface limbo trailers (built for a customer
            // but saleStatus still 'available' / 'sale_pending').
            // Matches the count query.
            'saleStatus': 'sold',
          },
        ),
      ),
    ];

    // Health Check deep-link — owner + production_manager only.
    // pushNamed so Back pops cleanly back to the dashboard instead
    // of falling through to /admin (which is now guarded and would
    // just bounce back to /dashboard anyway).
    final reportTiles = <Widget>[
      if (canSeeProductionReport)
        StatCard(
          title: 'Health Check',
          value: '${data.activeTrailers}',
          icon: Icons.monitor_heart_outlined,
          color: AppColors.statusInProduction,
          onTap: () => context.pushNamed(RouteNames.productionReport),
        ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.pagePadding),
      child: Column(
        children: [
          _DashSection(label: 'Production', tiles: productionTiles),
          _DashSection(label: 'Quality', tiles: qualityTiles),
          _DashSection(label: 'Logistics', tiles: logisticsTiles),
          _DashSection(label: 'Reports', tiles: reportTiles),
        ],
      ),
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
    final l = AppLocalizations.of(context);
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
                title: l.navMyQueue,
                value: '${data.myQueueCount}',
                icon: Icons.queue,
                color: AppColors.navy,
                onTap: () => context.goNamed(RouteNames.productionQueue),
              ),
              StatCard(
                title: l.dashStatPointsToday,
                value: data.myPointsToday.toStringAsFixed(1),
                icon: Icons.star,
                color: AppColors.amber,
                onTap: () => context.goNamed(RouteNames.workerPoints),
              ),
              StatCard(
                title: l.dashStatPointsThisWeek,
                value: data.myPointsWeek.toStringAsFixed(1),
                icon: Icons.emoji_events,
                color: AppColors.success,
                onTap: () => context.goNamed(RouteNames.workerPoints),
              ),
            ],
          ),
        ),
        if (data.nextTrailerSo != null)
          WideStatCard(
            title: l.dashStatNextTrailer,
            value: data.nextTrailerSo!,
            subtitle: data.nextTrailerColor,
            icon: Icons.arrow_forward,
            color: AppColors.navy,
            onTap: () => context.goNamed(RouteNames.productionQueue),
          ),
      ],
    );
  }
}

// ── QC Inspector ─────────────────────────────────────────────────────────────
//
// QC sits in the production-admin tier so they see the same shop-floor
// stats production_manager / owner do (in-production count, hot trailers,
// stalled steps, completed-this-week, archived). On top of that they keep
// their original QC-specific tiles: ready-for-inspection, inspections-
// today, today's fail rate, rework queue.
//
// Intentionally left out:
//   • Ready-for-delivery + Health Check  — QC has no action on these and
//     the user asked for them to be hidden on this dashboard.
//   • Total trailers + Pending production — kept (counts they routinely
//     look at while triaging).

class _QcDashboard extends StatelessWidget {
  final DashboardData data;
  const _QcDashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final l = AppLocalizations.of(context);

    // QC tiles the inspector cares about first thing every morning — the
    // work queue and the two rate/rework signals.
    final qualityTiles = <Widget>[
      StatCard(
        title: l.dashStatReadyForInspection,
        value: '${data.readyForInspection}',
        icon: Icons.fact_check,
        color: AppColors.navy,
        onTap: () => context.goNamed(RouteNames.qcQueue),
      ),
      StatCard(
        title: l.dashStatInspectionsToday,
        value: '${data.inspectionsToday}',
        icon: Icons.checklist,
        color: AppColors.success,
        onTap: () => context.goNamed(RouteNames.qcQueue),
      ),
      StatCard(
        title: l.dashStatFailRateToday,
        value: data.inspectionsToday > 0
            ? '${data.failRateToday.toStringAsFixed(1)}% · '
                '${data.failsToday}/${data.inspectionsToday}'
            : '0% · 0/0',
        icon: Icons.trending_down,
        color:
            data.failRateToday > 20 ? AppColors.error : AppColors.navy,
        onTap: () => context.goNamed(RouteNames.qcFailed),
      ),
      StatCard(
        title: l.dashStatQcFailRate,
        value: data.qcFailRateInspections > 0
            ? '${data.qcFailRate.toStringAsFixed(1)}% · '
                '${data.qcFailRateFails}/${data.qcFailRateInspections}'
            : '${data.qcFailRate.toStringAsFixed(1)}%',
        icon: Icons.analytics_outlined,
        color: data.qcFailRate > 15 ? AppColors.error : AppColors.navy,
        onTap: () => context.goNamed(RouteNames.qcFailed),
      ),
      StatCard(
        title: l.dashStatReworkQueue,
        value: '${data.reworkQueue}',
        icon: Icons.replay,
        color: AppColors.warning,
        onTap: () => context.goNamed(RouteNames.qcRework),
      ),
    ];

    // Production-floor context so a QC manager can see what's coming
    // and what's stuck, without leaving the dashboard.
    final productionTiles = <Widget>[
      StatCard(
        title: l.dashStatActiveTrailers,
        value: '${data.activeTrailers}',
        icon: Icons.precision_manufacturing,
        color: AppColors.statusInProduction,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'status': 'in_production'},
        ),
      ),
      StatCard(
        title: 'Pending production',
        value: '${data.pendingProduction}',
        icon: Icons.schedule_outlined,
        color: AppColors.statusPending,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'status': 'pending_production'},
        ),
      ),
      StatCard(
        title: l.dashStatHotTrailers,
        value: '${data.hotTrailers}',
        icon: Icons.local_fire_department,
        color: AppColors.error,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'hot': 'true'},
        ),
        badge: data.hotTrailers > 0
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(l.dashStatHotBadge,
                    style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              )
            : null,
      ),
      StatCard(
        title: l.dashStatStalledSteps,
        value: '${data.stalledSteps}',
        icon: Icons.warning_amber,
        color: AppColors.warning,
        onTap: () => context.goNamed(
          RouteNames.productionQueue,
          queryParameters: {'filter': 'stalled'},
        ),
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
        title: l.dashStatCompletedThisWeek,
        value: '${data.weeklyCompleted}',
        icon: Icons.check_circle_outline,
        color: AppColors.statusDelivered,
        onTap: () {
          final now = DateTime.now().toUtc();
          final daysBack = now.weekday % 7;
          final sunday =
              DateTime.utc(now.year, now.month, now.day - daysBack);
          context.goNamed(
            RouteNames.trailerList,
            queryParameters: {
              'status': 'delivered',
              'completedSince': sunday.toIso8601String(),
            },
          );
        },
      ),
      StatCard(
        title: 'Total trailers',
        value: '${data.totalTrailers}',
        icon: Icons.inventory_2_outlined,
        color: AppColors.navy,
        onTap: () => context.goNamed(RouteNames.trailerList),
      ),
      StatCard(
        title: 'Archived',
        value: '${data.archivedTotal}',
        icon: Icons.inventory_2_outlined,
        color: AppColors.disabled,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'status': 'delivered'},
        ),
      ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.pagePadding),
      child: Column(
        children: [
          _DashSection(label: 'Quality', tiles: qualityTiles),
          _DashSection(label: 'Production', tiles: productionTiles),
        ],
      ),
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
    final l = AppLocalizations.of(context);

    // What's flowing through transport right now — the three counts a
    // dispatcher opens the app to see.
    final deliveryTiles = <Widget>[
      StatCard(
        title: l.dashStatScheduled,
        value: '${data.scheduledDeliveries}',
        icon: Icons.event_note,
        color: AppColors.navy,
        onTap: () => context.goNamed(
          RouteNames.deliveryList,
          queryParameters: {'status': 'scheduled'},
        ),
      ),
      StatCard(
        title: 'In transit',
        value: '${data.inTransitCount}',
        icon: Icons.local_shipping_outlined,
        color: AppColors.statusInTransit,
        onTap: () => context.goNamed(
          RouteNames.deliveryList,
          queryParameters: {'status': 'in_transit'},
        ),
      ),
      StatCard(
        title: l.dashStatReadyForPickup,
        value: '${data.readyForPickup}',
        icon: Icons.inventory,
        color: AppColors.success,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {'status': 'ready_for_delivery'},
        ),
      ),
    ];

    // Mulberry outbound flow — the same tiles the manager dashboard
    // shows, since transport is the audience that plans the stack runs
    // and customer pickups from Mulberry.
    final logisticsTiles = <Widget>[
      StatCard(
        title: 'Mulberry → Yards',
        value: '${data.mulberryStockTotal}',
        icon: Icons.local_shipping_outlined,
        color: AppColors.navy,
        onTap: () => _showMulberryYardSheet(context, data),
      ),
      StatCard(
        title: 'Customer Pickups @ Mulberry',
        value: '${data.mulberryCustomerPickups}',
        icon: Icons.directions_car_outlined,
        color: AppColors.amber,
        onTap: () => context.goNamed(
          RouteNames.trailerList,
          queryParameters: {
            'status': 'ready_for_delivery',
            'currentLocationCode': 'MULBERRY',
            'isStockBuild': 'false',
            'saleStatus': 'sold',
          },
        ),
      ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.pagePadding),
      child: Column(
        children: [
          _DashSection(label: 'Deliveries', tiles: deliveryTiles),
          _DashSection(label: 'Logistics', tiles: logisticsTiles),
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
              label: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stock Inventory card ─────────────────────────────────────────────────────

/// A feature card on the dashboard that links to the full stock inventory.
class _StockInventoryCard extends StatelessWidget {
  const _StockInventoryCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 6),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF24506A), AppColors.navy, Color(0xFF112430)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.40),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            // push (not go) so the back button returns to the dashboard
            // rather than popping into the delivery list underneath.
            onTap: () => context.pushNamed(RouteNames.stockInventory),
            child: Stack(
              children: [
                // Faint watermark for depth.
                Positioned(
                  right: -20,
                  bottom: -28,
                  child: Icon(
                    Icons.warehouse_rounded,
                    size: 140,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(Icons.warehouse_rounded,
                            color: AppColors.amber, size: 28),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            AppLocalizations.of(context).dashStockInventory,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 19),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mulberry-Ready drill-down ────────────────────────────────────────────────
//
// Tapping the "Mulberry → Yards" tile opens a bottom sheet listing the four
// satellite yards (Jacksonville / Tappahannock / Tallahassee / Atlanta) with
// the count of stock builds at Mulberry destined for each. Tapping a row
// deep-links into the trailer list filtered to "at Mulberry AND intended
// for that yard" — the new currentLocationCode + intendedStockLocationCode
// query params on /trailers.

void _showMulberryYardSheet(BuildContext context, DashboardData data) {
  final yards = const [
    ('JACKSONVILLE', 'Jacksonville'),
    ('TAPPAHANNOCK', 'Tappahannock'),
    ('TALLAHASSEE', 'Tallahassee'),
    ('ATLANTA', 'Atlanta'),
  ];
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.local_shipping_outlined,
                    color: AppColors.navy),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Mulberry → Yards',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${data.mulberryStockTotal} ready',
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final (code, label) in yards)
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warehouse_outlined,
                    color: AppColors.navy),
              ),
              title: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Stock at Mulberry',
                  style: TextStyle(color: AppColors.disabled, fontSize: 12)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (data.mulberryStockByYard[code] ?? 0) > 0
                      ? AppColors.statusInProduction.withValues(alpha: 0.12)
                      : AppColors.disabled.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${data.mulberryStockByYard[code] ?? 0}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: (data.mulberryStockByYard[code] ?? 0) > 0
                        ? AppColors.statusInProduction
                        : AppColors.disabled,
                  ),
                ),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                context.goNamed(
                  RouteNames.trailerList,
                  queryParameters: {
                    'status': 'ready_for_delivery',
                    'currentLocationCode': 'MULBERRY',
                    'intendedStockLocationCode': code,
                  },
                );
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Collapsible labelled group of dashboard tiles. Renders a section
/// heading ("PRODUCTION", "QUALITY", ...) as a tappable row with an
/// animated chevron, followed by a responsive grid of [tiles]. Defaults
/// to expanded — the user can tap to collapse a section they don't
/// currently care about (e.g. sales rolling up the Production section
/// on a busy sales day). State is kept per-widget so collapsed
/// sections stay collapsed while the dashboard refreshes.
///
/// Yields nothing when [tiles] is empty — sections whose tiles are all
/// role-gated away don't leave a dangling heading behind.
class _DashSection extends StatefulWidget {
  final String label;
  final List<Widget> tiles;

  const _DashSection({required this.label, required this.tiles});

  @override
  State<_DashSection> createState() => _DashSectionState();
}

class _DashSectionState extends State<_DashSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.tiles.isEmpty) return const SizedBox.shrink();
    final r = context.responsive;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  // Navy — the app's primary brand color. Bumped from 11pt
                  // to 15pt with letter-spacing pulled down proportionally
                  // so headings hold their own next to the tile grid
                  // instead of getting swallowed by it.
                  Text(
                    widget.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Divider(
                      color: AppColors.navy.withValues(alpha: 0.25),
                      thickness: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0 : -0.25,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.navy,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GridView.count(
                      crossAxisCount: r.gridColumns(
                          compact: 2, medium: 3, expanded: 4, large: 4),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: r.statCardAspectRatio,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: widget.tiles,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
