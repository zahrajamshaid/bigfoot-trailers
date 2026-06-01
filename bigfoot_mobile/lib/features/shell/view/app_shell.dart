import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/i18n/language_toggle_button.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/router/route_names.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_event_stream.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/brand_logo_avatar.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../notifications/viewmodel/notifications_viewmodel.dart';

/// Main app shell with role-based bottom navigation.
class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<WsEvent>? _eventSub;
  WsClient? _wsClient;
  DateTime? _lastBackPress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = context.read<WsClient>();
    if (_wsClient == client) return;

    _eventSub?.cancel();
    _wsClient = client;
    _eventSub = client.events.listen(_onWsEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return BlocBuilder<AuthViewModel, AuthState>(
      builder: (context, state) {
        final user = state is Authenticated ? state.user : null;
        final tabs = _tabsForRole(user?.role ?? UserRole.worker, l);
        final currentIndex = _currentIndex(context, tabs);

        return StreamBuilder<WsConnectionState>(
          stream: context.read<WsClient>().connectionState,
          initialData: context.read<WsClient>().currentState,
          builder: (context, snapshot) {
            final connectionState =
                snapshot.data ?? WsConnectionState.disconnected;

            final r = context.responsive;
            final useRail = r.isTablet && tabs.length > 1;
            // On phones, always show BOTH a drawer (hamburger menu, full tab list)
            // AND a bottom navigation bar (top 5 tabs) — per UX request, mobiles
            // get both. The drawer is the source of truth when there are >5 tabs.
            final useDrawer = !useRail && tabs.length > 1;
            final useBottom = !useRail && tabs.length > 1;
            // Owner/admin requested that all drawer items be available in the
            // phone bottom bar. Keep truncation for other roles.
            final showAllBottomTabs = user?.role == UserRole.owner;
            final bottomTabs = showAllBottomTabs
                ? tabs
                : (tabs.length > 5 ? tabs.take(5).toList() : tabs);

            // Wrap routed content in a centred max-width container on tablet+
            // so forms/lists don't stretch ugly across wide screens. On phones
            // (compact width) maxContentWidth is infinity — no visual change.
            final innerChild = r.isCompact
                ? widget.child
                : Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: r.maxContentWidth),
                      child: widget.child,
                    ),
                  );

            // Cross-fade between shell tabs. GoRouter's ShellRoute hot-swaps
            // the child with no animation by default — on iOS especially
            // that hard cut reads as a stutter. Keying on the matched
            // location triggers AnimatedSwitcher every time the route
            // changes; same-route rebuilds (e.g. state updates) keep the
            // same key and don't animate.
            final routeKey = GoRouterState.of(context).matchedLocation;
            final routedChild = AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: KeyedSubtree(
                key: ValueKey(routeKey),
                child: innerChild,
              ),
            );

            final body = Column(
              children: [
                if (connectionState != WsConnectionState.connected)
                  const _OfflineBanner(),
                Expanded(child: routedChild),
              ],
            );

            final canNavigatorPop = GoRouter.of(context).canPop();

            return PopScope(
              canPop: canNavigatorPop,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                _handleBackPress(context);
              },
              child: Scaffold(
                drawer: useDrawer
                    ? _NavDrawer(tabs: tabs, currentIndex: currentIndex)
                    : null,
                appBar: AppBar(
                  // Explicit leading: when the shell has a drawer (always on
                  // phone/tablet with >1 tab), force the hamburger button so
                  // it's never hidden by AppBar's auto-imply logic deciding
                  // to show a back arrow instead.
                  leading: useDrawer
                      ? Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        )
                      : null,
                  titleSpacing: 12,
                  title: Row(
                    children: [
                      // Tappable brand logo — anywhere in the shell, tap to
                      // return to the dashboard. Fixes the "no way back to
                      // homepage" complaint without relying on the iOS swipe
                      // gesture or finding the right back chevron.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => context.go('/dashboard'),
                        child: const BrandLogoAvatar(
                          size: 32,
                          padding: EdgeInsets.all(0.1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context.go('/dashboard'),
                          child: Text(
                            r.isCompact ? l.appTitleShort : l.appTitle,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ConnectionDot(
                        state: connectionState,
                        compact: r.isCompact,
                      ),
                    ],
                  ),
                  actions: [
                    const LanguageToggleButton(
                        foregroundColor: AppColors.white),
                    BlocBuilder<NotificationsViewModel, NotificationsState>(
                      builder: (context, notificationState) {
                        final count = notificationState.unreadCount;
                        return IconButton(
                          icon: Badge(
                            isLabelVisible: count > 0,
                            label: Text(
                              '$count',
                              style: const TextStyle(fontSize: 9),
                            ),
                            backgroundColor: AppColors.error,
                            child: const Icon(
                              Icons.notifications_outlined,
                              size: 24,
                            ),
                          ),
                          onPressed: () =>
                              context.pushNamed(RouteNames.notificationsCenter),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => context.go('/settings'),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.amber,
                          child: Text(
                            (user?.name.isNotEmpty == true)
                                ? user!.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                body: useRail
                    ? Row(
                        children: [
                          // The rail can have more destinations than fit a
                          // short (landscape) viewport — let it scroll while
                          // still filling the height when there is room.
                          LayoutBuilder(
                            builder: (context, constraints) =>
                                SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: IntrinsicHeight(
                                  child: NavigationRail(
                                    selectedIndex: currentIndex.clamp(
                                      0,
                                      tabs.length - 1,
                                    ),
                                    onDestinationSelected: (index) =>
                                        context.go(tabs[index].path),
                                    labelType: r.isExpanded || r.isLarge
                                        ? NavigationRailLabelType.all
                                        : NavigationRailLabelType.selected,
                                    extended: r.isLarge,
                                    destinations: tabs
                                        .map(
                                          (tab) => NavigationRailDestination(
                                            icon: Icon(tab.icon),
                                            selectedIcon:
                                                Icon(tab.selectedIcon),
                                            label: Text(tab.label),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: body),
                        ],
                      )
                    : body,
                bottomNavigationBar: useBottom
                    ? NavigationBar(
                        selectedIndex: currentIndex.clamp(
                          0,
                          bottomTabs.length - 1,
                        ),
                        onDestinationSelected: (index) =>
                            context.go(bottomTabs[index].path),
                        labelBehavior:
                            NavigationDestinationLabelBehavior.onlyShowSelected,
                        destinations: bottomTabs
                            .map(
                              (tab) => NavigationDestination(
                                icon: Icon(tab.icon),
                                selectedIcon: Icon(tab.selectedIcon),
                                label: tab.label,
                              ),
                            )
                            .toList(),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  /// System back-button handler.
  /// - On any tab other than /dashboard: navigate to /dashboard.
  /// - On /dashboard: require a second back press within 2s to exit (so users
  ///   don't accidentally lose the app).
  Future<void> _handleBackPress(BuildContext context) async {
    final location = GoRouterState.of(context).matchedLocation;

    // If we're not on the dashboard, go there first.
    if (!location.startsWith('/dashboard')) {
      context.go('/dashboard');
      return;
    }

    // Already on dashboard — double-tap to exit.
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).backToExit),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    SystemNavigator.pop();
  }

  void _onWsEvent(WsEvent event) {
    if (!mounted || !_shouldToast(event)) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _toastColor(event),
        content: Text(_toastMessage(event)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _shouldToast(WsEvent event) {
    return const {
      WsEventType.qcFail,
      WsEventType.trailerReady,
      WsEventType.trailerStalled,
    }.contains(event.type);
  }

  Color _toastColor(WsEvent event) {
    switch (event.type) {
      case WsEventType.qcFail:
        return AppColors.error;
      case WsEventType.trailerReady:
        return AppColors.success;
      case WsEventType.trailerStalled:
        return AppColors.warning;
      default:
        return AppColors.navy;
    }
  }

  String _toastMessage(WsEvent event) {
    final so = event.soNumber ?? 'Trailer';
    switch (event.type) {
      case WsEventType.qcFail:
        final target =
            event.data['reworkTargetDepartment']?.toString() ??
            event.data['rework_target_department']?.toString() ??
            'rework';
        return 'QC failed - $so sent to $target';
      case WsEventType.trailerReady:
        return '$so ready for delivery';
      case WsEventType.trailerStalled:
        final dept =
            event.data['departmentName']?.toString() ??
            event.data['department_name']?.toString() ??
            'unknown step';
        final hours =
            event.data['stallHours']?.toString() ??
            event.data['stalledHours']?.toString() ??
            '';
        return '$so stalled at $dept${hours.isEmpty ? '' : ' ($hours h)'}';
      default:
        return event.type;
    }
  }

  int _currentIndex(BuildContext context, List<_NavTab> tabs) {
    final location = GoRouterState.of(context).matchedLocation;
    for (var i = 0; i < tabs.length; i++) {
      if (location.startsWith(tabs[i].path)) {
        return i;
      }
    }
    return 0;
  }

  List<_NavTab> _tabsForRole(String role, AppLocalizations l) {
    switch (role) {
      case UserRole.owner:
        return [
          _NavTab(
            '/dashboard',
            l.navDashboard,
            Icons.dashboard_outlined,
            Icons.dashboard,
          ),
          _NavTab(
            '/trailers',
            l.navTrailers,
            Icons.local_shipping_outlined,
            Icons.local_shipping,
          ),
          _NavTab(
            '/production',
            l.navProduction,
            Icons.precision_manufacturing_outlined,
            Icons.precision_manufacturing,
          ),
          _NavTab('/qc', l.navQc, Icons.checklist_outlined, Icons.checklist),
          _NavTab(
            '/payroll',
            l.navPayroll,
            Icons.payments_outlined,
            Icons.payments,
          ),
          _NavTab(
            '/deliveries',
            l.navDeliveries,
            Icons.delivery_dining_outlined,
            Icons.delivery_dining,
          ),
          _NavTab(
            '/admin',
            l.navAdmin,
            Icons.admin_panel_settings_outlined,
            Icons.admin_panel_settings,
          ),
        ];
      case UserRole.productionManager:
        return [
          _NavTab(
            '/dashboard',
            l.navDashboard,
            Icons.dashboard_outlined,
            Icons.dashboard,
          ),
          _NavTab(
            '/trailers',
            l.navTrailers,
            Icons.local_shipping_outlined,
            Icons.local_shipping,
          ),
          _NavTab(
            '/production',
            l.navProduction,
            Icons.precision_manufacturing_outlined,
            Icons.precision_manufacturing,
          ),
          _NavTab('/qc', l.navQc, Icons.checklist_outlined, Icons.checklist),
          _NavTab(
            '/payroll',
            l.navPayroll,
            Icons.payments_outlined,
            Icons.payments,
          ),
        ];
      case UserRole.transportManager:
        return [
          _NavTab(
            '/dashboard',
            l.navDashboard,
            Icons.dashboard_outlined,
            Icons.dashboard,
          ),
          _NavTab(
            '/deliveries',
            l.navDeliveries,
            Icons.delivery_dining_outlined,
            Icons.delivery_dining,
          ),
        ];
      case UserRole.qcInspector:
        return [
          _NavTab(
            '/dashboard',
            l.navDashboard,
            Icons.dashboard_outlined,
            Icons.dashboard,
          ),
          _NavTab('/qc', l.navQc, Icons.checklist_outlined, Icons.checklist),
        ];
      case UserRole.worker:
        return [
          _NavTab(
              '/production', l.navMyQueue, Icons.queue_outlined, Icons.queue),
          _NavTab('/payroll', l.navMyPoints, Icons.star_outline, Icons.star),
        ];
      case UserRole.driver:
        return [
          _NavTab(
            '/deliveries',
            l.navMyDeliveries,
            Icons.delivery_dining_outlined,
            Icons.delivery_dining,
          ),
        ];
      case UserRole.office:
        return [
          _NavTab(
            '/deliveries',
            l.navDeliveries,
            Icons.delivery_dining_outlined,
            Icons.delivery_dining,
          ),
        ];
      case UserRole.sales:
        // Sales drives the sold + create-delivery + customer-pickup flow,
        // so they need direct access to the deliveries list. Filtering by
        // type from inside that screen lets them watch all scheduled
        // factory pickups (and stack-to-location creates from sales now
        // mark the trailer as stock-build automatically).
        return [
          _NavTab(
            '/dashboard',
            l.navDashboard,
            Icons.dashboard_outlined,
            Icons.dashboard,
          ),
          _NavTab(
            '/trailers',
            l.navTrailers,
            Icons.local_shipping_outlined,
            Icons.local_shipping,
          ),
          _NavTab(
            '/deliveries',
            l.navDeliveries,
            Icons.delivery_dining_outlined,
            Icons.delivery_dining,
          ),
        ];
      case UserRole.purchasing:
        // Purchasing lands on trailers pre-filtered to pending_production so
        // they see the orders that haven't started building yet and can plan
        // parts ordering. Trailer list + detail already gate create/edit/
        // delete behind owner/production_manager — purchasing is read-only.
        //
        // Dashboard is included so the hamburger + bottom-nav render (both
        // require tabs.length > 1), giving an obvious "back to home"
        // affordance on iOS where there's no system back button.
        return [
          _NavTab(
            '/dashboard',
            l.navDashboard,
            Icons.dashboard_outlined,
            Icons.dashboard,
          ),
          _NavTab(
            '/trailers?status=pending_production',
            l.navTrailers,
            Icons.local_shipping_outlined,
            Icons.local_shipping,
          ),
        ];
      default:
        return [
          _NavTab(
            '/dashboard',
            l.navDashboard,
            Icons.dashboard_outlined,
            Icons.dashboard,
          ),
        ];
    }
  }
}

class _ConnectionDot extends StatelessWidget {
  final WsConnectionState state;
  final bool compact;

  const _ConnectionDot({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = switch (state) {
      WsConnectionState.connected => AppColors.success,
      WsConnectionState.connecting => AppColors.warning,
      WsConnectionState.disconnected => AppColors.error,
    };

    final label = switch (state) {
      WsConnectionState.connected => l.connectionConnected,
      WsConnectionState.connecting => l.connectionConnecting,
      WsConnectionState.disconnected => l.connectionOffline,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        if (!compact) ...[
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ],
    );
  }
}

class _NavDrawer extends StatelessWidget {
  final List<_NavTab> tabs;
  final int currentIndex;

  const _NavDrawer({required this.tabs, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView.builder(
          itemCount: tabs.length,
          itemBuilder: (context, i) {
            final tab = tabs[i];
            final selected = i == currentIndex;
            return ListTile(
              leading: Icon(selected ? tab.selectedIcon : tab.icon),
              title: Text(tab.label),
              selected: selected,
              onTap: () {
                Navigator.of(context).pop();
                context.go(tab.path);
              },
            );
          },
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined,
              color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).offlineBanner,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTab {
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _NavTab(this.path, this.label, this.icon, this.selectedIcon);
}
