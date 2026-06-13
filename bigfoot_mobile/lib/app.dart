import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/config/app_environment.dart';
import 'core/constants/app_theme.dart';
import 'core/i18n/locale_cubit.dart';
import 'core/network/dio_client.dart';
import 'core/platform/platform_support.dart';
import 'core/router/app_router.dart';
import 'core/security/mobile_security.dart';
import 'core/security/pin_storage.dart';
import 'core/websocket/realtime_cubits.dart';
import 'core/websocket/ws_client.dart';
import 'features/auth/view/pin_lock_screen.dart';
import 'l10n/generated/app_localizations.dart';
import 'data/models/app_notification.dart';
import 'di/service_locator.dart';
import 'domain/repositories/storage_repository.dart';
import 'features/admin/viewmodel/admin_viewmodel.dart';
import 'features/auth/viewmodel/auth_viewmodel.dart';
import 'features/customers/viewmodel/customers_viewmodel.dart';
import 'features/dashboard/viewmodel/dashboard_viewmodel.dart';
import 'features/deliveries/viewmodel/deliveries_viewmodel.dart';
import 'features/notifications/viewmodel/messages_viewmodel.dart';
import 'features/notifications/viewmodel/notifications_viewmodel.dart';
import 'features/payroll/viewmodel/payroll_viewmodel.dart';
import 'features/trailers/viewmodel/trailers_viewmodel.dart';

class BigfootApp extends StatefulWidget {
  const BigfootApp({super.key});

  @override
  State<BigfootApp> createState() => _BigfootAppState();
}

class _BigfootAppState extends State<BigfootApp> with WidgetsBindingObserver {
  late final ServiceLocator _sl;

  late final AuthViewModel _authViewModel;
  late final DashboardViewModel _dashboardViewModel;
  late final TrailersViewModel _trailersViewModel;
  late final DeliveriesViewModel _deliveriesViewModel;
  late final PayrollViewModel _payrollViewModel;
  late final AdminViewModel _adminViewModel;
  late final CustomersViewModel _customersViewModel;
  late final MessagesViewModel _messagesViewModel;
  late final NotificationsViewModel _notificationsViewModel;

  late final DepartmentQueueRealtimeCubit _departmentQueueRealtimeCubit;
  late final TrailerDetailRealtimeCubit _trailerDetailRealtimeCubit;
  late final DashboardStatsRealtimeCubit _dashboardStatsRealtimeCubit;
  late final NotificationCountCubit _notificationCountCubit;
  late final LocaleCubit _localeCubit;

  late final AppRouter _appRouter;
  late final StreamSubscription<AuthState> _authSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _securityBlocked = false;

  // ── PIN lock state ─────────────────────────────────────────────────────
  // Re-evaluated on auth changes + every lifecycle resume. When [_pinEnabled]
  // is true and [_pinLocked] is true, the MaterialApp.router builder swaps
  // the navigator for a full-screen [PinLockScreen] gate.
  final PinStorage _pinStorage = PinStorage();
  bool _pinEnabled = false;
  bool _pinLocked = false;

  bool get _isAuthenticated => _authViewModel.state is Authenticated;

  void _kickWsIfStale() {
    if (!_isAuthenticated) return;
    final ws = _sl.wsClient;
    if (ws.currentState != WsConnectionState.connected) {
      ws.forceReconnect();
    }
  }

  @override
  void initState() {
    super.initState();

    _sl = ServiceLocator.build(
      apiBaseUrl: AppEnvironment.apiBaseUrl,
      wsUrl: AppEnvironment.wsUrl,
      onAuthExpired: () => _authViewModel.onAuthExpired(),
    );

    _authViewModel = AuthViewModel(
      repository: _sl.authRepository,
      storage: _sl.secureStorage,
      ws: _sl.wsClient,
    );
    _dashboardViewModel = DashboardViewModel(
      repository: _sl.dashboardRepository,
      ws: _sl.wsClient,
      role: 'owner',
    );
    _trailersViewModel = TrailersViewModel(
      repository: _sl.trailerRepository,
      ws: _sl.wsClient,
    );
    _deliveriesViewModel = DeliveriesViewModel(
      repository: _sl.deliveryRepository,
      ws: _sl.wsClient,
    );
    _payrollViewModel = PayrollViewModel(
      repository: _sl.payrollRepository,
      ws: _sl.wsClient,
    );
    _adminViewModel = AdminViewModel(repository: _sl.adminRepository);
    _customersViewModel = CustomersViewModel(repository: _sl.customerRepository);
    _messagesViewModel = MessagesViewModel(repository: _sl.messageRepository);
    _notificationsViewModel = NotificationsViewModel(
      repository: _sl.notificationRepository,
      ws: _sl.wsClient,
      pushService: _sl.pushNotificationService,
      desktopNotifier: _sl.desktopNotificationService,
    );
    // Register the desktop OS-toast channel (no-op on mobile/web). Fire and
    // forget — toasts only fire on later WS events, so we don't block startup.
    unawaited(_sl.desktopNotificationService.initialize());

    _departmentQueueRealtimeCubit =
        DepartmentQueueRealtimeCubit(ws: _sl.wsClient);
    _trailerDetailRealtimeCubit =
        TrailerDetailRealtimeCubit(ws: _sl.wsClient);
    _dashboardStatsRealtimeCubit =
        DashboardStatsRealtimeCubit(ws: _sl.wsClient);
    _notificationCountCubit = NotificationCountCubit(ws: _sl.wsClient);

    _localeCubit = LocaleCubit();
    _localeCubit.load();

    _appRouter = AppRouter();

    _authSub = _authViewModel.stream.listen((state) {
      if (state is Authenticated) {
        _dashboardViewModel.loadForUser(
          role: state.user.role,
          userId: state.user.id,
          departmentId: state.user.departmentId,
        );
        _notificationsViewModel.initializePush(onOpenPayload: _handlePushOpen);
        _notificationsViewModel.registerPushToken();
        _notificationsViewModel.loadHistory();
        // Lock the app immediately on a fresh auth — both for restored
        // sessions (cold start) and brand-new logins. The gate disappears
        // if the user has not enabled PIN lock in settings.
        // _pinEnabled is preloaded in initState so this is synchronous.
        if (_pinEnabled && !_pinLocked) {
          setState(() => _pinLocked = true);
        }
        // Re-check the flag in case settings changed since startup.
        _refreshPinLock(lockIfEnabled: true);
      } else {
        // Signed-out users don't need to face the PIN gate.
        if (_pinLocked) setState(() => _pinLocked = false);
      }
    });

    // Preload PIN-enabled flag so the gate is ready by the time auth
    // restoration finishes (avoids a flash of the dashboard).
    _refreshPinLock(lockIfEnabled: false);

    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        final hasNetwork = results.any((r) => r != ConnectivityResult.none);
        if (hasNetwork) _kickWsIfStale();
      },
    );

    _initializeSecurityGuards();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _kickWsIfStale();
      // Re-lock the app every time it comes back from the background. Reads
      // the latest enabled flag in case the user toggled it during the same
      // session (rare, but cheap to handle).
      if (_isAuthenticated) {
        _refreshPinLock(lockIfEnabled: true);
      }
    }
  }

  /// Loads the current PIN-enabled flag and optionally engages the lock.
  /// When [lockIfEnabled] is true and PIN lock is on, the gate is shown.
  Future<void> _refreshPinLock({required bool lockIfEnabled}) async {
    final enabled = await _pinStorage.isEnabled();
    if (!mounted) return;
    setState(() {
      _pinEnabled = enabled;
      if (lockIfEnabled && enabled) _pinLocked = true;
    });
  }

  void _onPinSuccess() {
    if (!mounted) return;
    setState(() => _pinLocked = false);
  }

  Future<void> _onPinSignOut() async {
    // Escape hatch when the user forgot their PIN. Wipes the stored hash so
    // they can set up a new PIN on their next session (otherwise re-logging
    // in on the same device would just land them on the same broken gate).
    // The auth listener clears [_pinLocked] once Unauthenticated arrives.
    await _pinStorage.disable();
    if (!mounted) return;
    setState(() {
      _pinEnabled = false;
      _pinLocked = false;
    });
    await _authViewModel.logout();
    if (!mounted) return;
    _appRouter.router.go('/login');
  }

  Future<void> _initializeSecurityGuards() async {
    if (!AppEnvironment.isProduction) return;
    // Root/jailbreak detection is a mobile-only platform channel; desktop has
    // no implementation, so skip it rather than swallow a MissingPluginException.
    if (!PlatformSupport.isMobile) return;
    try {
      final rooted = await MobileSecurity.isDeviceRooted();
      if (!mounted) return;
      if (rooted) {
        setState(() => _securityBlocked = true);
      }
    } catch (_) {
      // If platform security checks fail, keep app usable.
    }
  }

  Future<void> _handlePushOpen(Map<String, dynamic> payload) async {
    final type = payload['type']?.toString();
    final trailerId = payload['trailerId']?.toString() ??
        payload['trailer_id']?.toString();
    final deliveryId = payload['deliveryId']?.toString() ??
        payload['delivery_id']?.toString();

    if (type == 'worker_message' && trailerId != null) {
      _appRouter.router.go('/messages/$trailerId');
      return;
    }

    if (deliveryId != null) {
      _appRouter.router.go('/deliveries/$deliveryId');
      return;
    }

    if (trailerId != null) {
      _appRouter.router.go('/trailers/$trailerId');
      return;
    }

    _appRouter.router.go('/notifications');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _authSub.cancel();
    _trailersViewModel.close();
    _deliveriesViewModel.close();
    _payrollViewModel.close();
    _adminViewModel.close();
    _customersViewModel.close();
    _messagesViewModel.close();
    _notificationsViewModel.close();
    _departmentQueueRealtimeCubit.close();
    _trailerDetailRealtimeCubit.close();
    _dashboardStatsRealtimeCubit.close();
    _notificationCountCubit.close();
    _dashboardViewModel.close();
    _authViewModel.close();
    _localeCubit.close();
    _sl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_securityBlocked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.security, size: 52),
                    SizedBox(height: 12),
                    Text(
                      'Security Check Failed',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This app cannot run on rooted devices in production.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DioClient>.value(value: _sl.dioClient),
        RepositoryProvider<WsClient>.value(value: _sl.wsClient),
        RepositoryProvider<StorageRepository>.value(
            value: _sl.storageRepository),
        RepositoryProvider.value(value: _sl.cameraService),
        RepositoryProvider.value(value: _sl.trailerRepository),
        RepositoryProvider.value(value: _sl.productionRepository),
        RepositoryProvider.value(value: _sl.qcRepository),
        RepositoryProvider.value(value: _sl.deliveryRepository),
        RepositoryProvider.value(value: _sl.adminRepository),
        RepositoryProvider.value(value: _sl.customerRepository),
        RepositoryProvider.value(value: _sl.locationRepository),
        RepositoryProvider.value(value: _sl.payrollRepository),
        RepositoryProvider.value(value: _sl.messageRepository),
        RepositoryProvider.value(value: _sl.notificationRepository),
        RepositoryProvider.value(value: _sl.announcementRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthViewModel>.value(value: _authViewModel),
          BlocProvider<DashboardViewModel>.value(value: _dashboardViewModel),
          BlocProvider<TrailersViewModel>.value(value: _trailersViewModel),
          BlocProvider<DeliveriesViewModel>.value(value: _deliveriesViewModel),
          BlocProvider<PayrollViewModel>.value(value: _payrollViewModel),
          BlocProvider<AdminViewModel>.value(value: _adminViewModel),
          BlocProvider<CustomersViewModel>.value(value: _customersViewModel),
          BlocProvider<MessagesViewModel>.value(value: _messagesViewModel),
          BlocProvider<NotificationsViewModel>.value(
              value: _notificationsViewModel),
          BlocProvider<DepartmentQueueRealtimeCubit>.value(
              value: _departmentQueueRealtimeCubit),
          BlocProvider<TrailerDetailRealtimeCubit>.value(
              value: _trailerDetailRealtimeCubit),
          BlocProvider<DashboardStatsRealtimeCubit>.value(
              value: _dashboardStatsRealtimeCubit),
          BlocProvider<NotificationCountCubit>.value(
              value: _notificationCountCubit),
          BlocProvider<LocaleCubit>.value(value: _localeCubit),
        ],
        child: BlocListener<NotificationsViewModel, NotificationsState>(
          listenWhen: (previous, current) =>
              previous.bannerId != current.bannerId && current.bannerId != null,
          listener: (context, state) {
            final id = state.bannerId;
            if (id == null) return;
            AppNotification? item;
            for (final n in state.items) {
              if (n.id == id) {
                item = n;
                break;
              }
            }
            if (item == null) return;
            ScaffoldMessenger.of(context).showMaterialBanner(
              MaterialBanner(
                content: Text('${item.title}: ${item.body}'),
                actions: [
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context)
                          .hideCurrentMaterialBanner();
                      context
                          .read<NotificationsViewModel>()
                          .clearBanner(id);
                    },
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            );
          },
          child: BlocBuilder<LocaleCubit, Locale>(
            builder: (context, locale) => MaterialApp.router(
              title: 'Bigfoot Trailers',
              theme: AppTheme.light,
              debugShowCheckedModeBanner: false,
              routerConfig: _appRouter.router,
              locale: locale,
              supportedLocales: LocaleCubit.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              // Clamp the OS text-scale factor so a device set to a very large
              // accessibility font cannot blow fixed-height layouts (stat cards,
              // nav bar, list tiles) past their bounds and trigger bottom
              // overflow. 1.3 still gives a meaningful accessibility boost.
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                // PIN gate: when locked, render the lock screen above the
                // navigator. Keeping the navigator mounted underneath means
                // the user lands back where they were once they unlock.
                Widget content = child ?? const SizedBox.shrink();
                if (_isAuthenticated && _pinEnabled && _pinLocked) {
                  content = PinLockScreen(
                    pinStorage: _pinStorage,
                    onSuccess: _onPinSuccess,
                    onSignOut: _onPinSignOut,
                  );
                }
                return MediaQuery(
                  data: mq.copyWith(
                    textScaler: mq.textScaler.clamp(
                      minScaleFactor: 0.85,
                      maxScaleFactor: 1.3,
                    ),
                  ),
                  child: content,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
