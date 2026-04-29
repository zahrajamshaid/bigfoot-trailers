import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/router/route_names.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_event_stream.dart';
import '../../../data/models/user.dart';
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
    return BlocBuilder<AuthViewModel, AuthState>(
      builder: (context, state) {
        final user = state is Authenticated ? state.user : null;
        final tabs = _tabsForRole(user?.role ?? UserRole.worker);
        final currentIndex = _currentIndex(context, tabs);

        return StreamBuilder<WsConnectionState>(
          stream: context.read<WsClient>().connectionState,
          initialData: context.read<WsClient>().currentState,
          builder: (context, snapshot) {
            final connectionState = snapshot.data ?? WsConnectionState.disconnected;

            final r = context.responsive;
            final useRail = r.isTablet && tabs.length > 1;
            final useDrawer = !useRail && tabs.length > 5;
            final useBottom = !useRail && !useDrawer && tabs.length > 1;

            // Wrap routed content in a centred max-width container on tablet+
            // so forms/lists don't stretch ugly across wide screens. On phones
            // (compact width) maxContentWidth is infinity — no visual change.
            final routedChild = r.isCompact
                ? widget.child
                : Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: r.maxContentWidth),
                      child: widget.child,
                    ),
                  );

            final body = Column(
              children: [
                if (connectionState != WsConnectionState.connected)
                  const _OfflineBanner(),
                Expanded(child: routedChild),
              ],
            );

            return Scaffold(
              drawer: useDrawer ? _NavDrawer(tabs: tabs, currentIndex: currentIndex) : null,
              appBar: AppBar(
                titleSpacing: 12,
                title: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        color: AppColors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        r.isCompact ? 'Bigfoot' : 'Bigfoot Trailers',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ConnectionDot(state: connectionState, compact: r.isCompact),
                  ],
                ),
                actions: [
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
                          child: const Icon(Icons.notifications_outlined, size: 24),
                        ),
                        onPressed: () => context.pushNamed(RouteNames.notificationsCenter),
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
                          (user?.name.isNotEmpty == true) ? user!.name[0].toUpperCase() : '?',
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
                        NavigationRail(
                          selectedIndex: currentIndex.clamp(0, tabs.length - 1),
                          onDestinationSelected: (index) => context.go(tabs[index].path),
                          labelType: r.isExpanded || r.isLarge
                              ? NavigationRailLabelType.all
                              : NavigationRailLabelType.selected,
                          extended: r.isLarge,
                          destinations: tabs
                              .map(
                                (tab) => NavigationRailDestination(
                                  icon: Icon(tab.icon),
                                  selectedIcon: Icon(tab.selectedIcon),
                                  label: Text(tab.label),
                                ),
                              )
                              .toList(),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: body),
                      ],
                    )
                  : body,
              bottomNavigationBar: useBottom
                  ? NavigationBar(
                      selectedIndex: currentIndex.clamp(0, tabs.length - 1),
                      onDestinationSelected: (index) => context.go(tabs[index].path),
                      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
                      height: 64,
                      destinations: tabs
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
            );
          },
        );
      },
    );
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
        final target = event.data['reworkTargetDepartment']?.toString() ??
            event.data['rework_target_department']?.toString() ??
            'rework';
        return 'QC failed - $so sent to $target';
      case WsEventType.trailerReady:
        return '$so ready for delivery';
      case WsEventType.trailerStalled:
        final dept = event.data['departmentName']?.toString() ??
            event.data['department_name']?.toString() ??
            'unknown step';
        final hours = event.data['stallHours']?.toString() ??
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

  List<_NavTab> _tabsForRole(String role) {
    switch (role) {
      case UserRole.owner:
        return const [
          _NavTab('/dashboard', 'Dashboard', Icons.dashboard_outlined, Icons.dashboard),
          _NavTab('/trailers', 'Trailers', Icons.local_shipping_outlined, Icons.local_shipping),
          _NavTab('/production', 'Production', Icons.precision_manufacturing_outlined, Icons.precision_manufacturing),
          _NavTab('/qc', 'QC', Icons.checklist_outlined, Icons.checklist),
          _NavTab('/payroll', 'Payroll', Icons.payments_outlined, Icons.payments),
          _NavTab('/deliveries', 'Deliveries', Icons.delivery_dining_outlined, Icons.delivery_dining),
          _NavTab('/admin', 'Admin', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings),
          _NavTab('/customers', 'Customers', Icons.people_outline, Icons.people),
        ];
      case UserRole.productionManager:
        return const [
          _NavTab('/dashboard', 'Dashboard', Icons.dashboard_outlined, Icons.dashboard),
          _NavTab('/trailers', 'Trailers', Icons.local_shipping_outlined, Icons.local_shipping),
          _NavTab('/production', 'Production', Icons.precision_manufacturing_outlined, Icons.precision_manufacturing),
          _NavTab('/qc', 'QC', Icons.checklist_outlined, Icons.checklist),
          _NavTab('/payroll', 'Payroll', Icons.payments_outlined, Icons.payments),
        ];
      case UserRole.transportManager:
        return const [
          _NavTab('/dashboard', 'Dashboard', Icons.dashboard_outlined, Icons.dashboard),
          _NavTab('/deliveries', 'Deliveries', Icons.delivery_dining_outlined, Icons.delivery_dining),
        ];
      case UserRole.qcInspector:
        return const [
          _NavTab('/dashboard', 'Dashboard', Icons.dashboard_outlined, Icons.dashboard),
          _NavTab('/qc', 'QC', Icons.checklist_outlined, Icons.checklist),
        ];
      case UserRole.worker:
        return const [
          _NavTab('/production', 'My Queue', Icons.queue_outlined, Icons.queue),
          _NavTab('/payroll', 'My Points', Icons.star_outline, Icons.star),
        ];
      case UserRole.driver:
        return const [
          _NavTab('/deliveries', 'My Deliveries', Icons.delivery_dining_outlined, Icons.delivery_dining),
        ];
      case UserRole.office:
        return const [
          _NavTab('/deliveries', 'Deliveries', Icons.delivery_dining_outlined, Icons.delivery_dining),
          _NavTab('/customers', 'Customers', Icons.people_outline, Icons.people),
        ];
      case UserRole.sales:
        return const [
          _NavTab('/trailers', 'Trailers', Icons.local_shipping_outlined, Icons.local_shipping),
          _NavTab('/customers', 'Customers', Icons.people_outline, Icons.people),
        ];
      default:
        return const [
          _NavTab('/dashboard', 'Dashboard', Icons.dashboard_outlined, Icons.dashboard),
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
    final color = switch (state) {
      WsConnectionState.connected => AppColors.success,
      WsConnectionState.connecting => AppColors.warning,
      WsConnectionState.disconnected => AppColors.error,
    };

    final label = switch (state) {
      WsConnectionState.connected => 'Connected',
      WsConnectionState.connecting => 'Connecting',
      WsConnectionState.disconnected => 'Offline',
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
      child: const Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: AppColors.error, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline - real-time updates paused',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
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