import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/config/app_environment.dart';
import 'core/constants/app_theme.dart';
import 'core/network/dio_client.dart';
import 'core/router/app_router.dart';
import 'core/security/mobile_security.dart';
import 'core/websocket/realtime_cubits.dart';
import 'core/websocket/ws_client.dart';
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

  late final AppRouter _appRouter;
  late final StreamSubscription<AuthState> _authSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _securityBlocked = false;

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
    );

    _departmentQueueRealtimeCubit =
        DepartmentQueueRealtimeCubit(ws: _sl.wsClient);
    _trailerDetailRealtimeCubit =
        TrailerDetailRealtimeCubit(ws: _sl.wsClient);
    _dashboardStatsRealtimeCubit =
        DashboardStatsRealtimeCubit(ws: _sl.wsClient);
    _notificationCountCubit = NotificationCountCubit(ws: _sl.wsClient);

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
      }
    });

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
    }
  }

  Future<void> _initializeSecurityGuards() async {
    if (!AppEnvironment.isProduction) return;
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
          child: MaterialApp.router(
            title: 'Bigfoot Trailers',
            theme: AppTheme.light,
            debugShowCheckedModeBanner: false,
            routerConfig: _appRouter.router,
          ),
        ),
      ),
    );
  }
}
