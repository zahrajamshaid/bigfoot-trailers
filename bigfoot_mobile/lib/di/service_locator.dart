import '../core/camera/camera_service.dart';
import '../core/network/auth_interceptor.dart';
import '../core/network/dio_client.dart';
import '../core/storage/secure_storage.dart';
import '../core/websocket/ws_client.dart';
import '../data/repositories/admin_repository_impl.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/customer_repository_impl.dart';
import '../data/repositories/dashboard_repository_impl.dart';
import '../data/repositories/delivery_repository_impl.dart';
import '../data/repositories/location_repository_impl.dart';
import '../data/repositories/message_repository_impl.dart';
import '../data/repositories/notification_repository_impl.dart';
import '../data/repositories/payroll_repository_impl.dart';
import '../data/repositories/production_repository_impl.dart';
import '../data/repositories/qc_repository_impl.dart';
import '../data/repositories/storage_repository_impl.dart';
import '../data/repositories/announcement_repository_impl.dart';
import '../domain/repositories/announcement_repository.dart';
import '../data/repositories/trailer_repository_impl.dart';
import '../domain/repositories/admin_repository.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/customer_repository.dart';
import '../domain/repositories/dashboard_repository.dart';
import '../domain/repositories/delivery_repository.dart';
import '../domain/repositories/location_repository.dart';
import '../domain/repositories/message_repository.dart';
import '../domain/repositories/notification_repository.dart';
import '../domain/repositories/payroll_repository.dart';
import '../domain/repositories/production_repository.dart';
import '../domain/repositories/qc_repository.dart';
import '../domain/repositories/storage_repository.dart';
import '../domain/repositories/trailer_repository.dart';
import '../services/desktop_notification_service.dart';
import '../services/push_notification_service.dart';

/// Simple, constructor-based service locator for the app's shared dependencies.
///
/// Consumers (primarily `BigfootApp`) build a single [ServiceLocator] at startup
/// and then pull repositories out to wire up view models via Bloc providers.
class ServiceLocator {
  ServiceLocator._({
    required this.dioClient,
    required this.wsClient,
    required this.secureStorage,
    required this.cameraService,
    required this.pushNotificationService,
    required this.desktopNotificationService,
    required this.authRepository,
    required this.dashboardRepository,
    required this.trailerRepository,
    required this.productionRepository,
    required this.qcRepository,
    required this.deliveryRepository,
    required this.payrollRepository,
    required this.adminRepository,
    required this.customerRepository,
    required this.locationRepository,
    required this.messageRepository,
    required this.notificationRepository,
    required this.storageRepository,
    required this.announcementRepository,
  });

  // Infrastructure
  final DioClient dioClient;
  final WsClient wsClient;
  final SecureStorage secureStorage;
  final CameraService cameraService;
  final PushNotificationService pushNotificationService;
  final DesktopNotificationService desktopNotificationService;

  // Domain repositories (contracts)
  final AuthRepository authRepository;
  final DashboardRepository dashboardRepository;
  final TrailerRepository trailerRepository;
  final ProductionRepository productionRepository;
  final QcRepository qcRepository;
  final DeliveryRepository deliveryRepository;
  final PayrollRepository payrollRepository;
  final AdminRepository adminRepository;
  final CustomerRepository customerRepository;
  final LocationRepository locationRepository;
  final MessageRepository messageRepository;
  final NotificationRepository notificationRepository;
  final StorageRepository storageRepository;
  final AnnouncementRepository announcementRepository;

  /// Builds the full dependency graph. `onAuthExpired` is called by the auth
  /// interceptor when refresh fails so the app can redirect to login.
  factory ServiceLocator.build({
    required String apiBaseUrl,
    required String wsUrl,
    required void Function() onAuthExpired,
  }) {
    final secureStorage = SecureStorage();
    final wsClient = WsClient(url: wsUrl, storage: secureStorage);
    final dioClient = DioClient(
      baseUrl: apiBaseUrl,
      interceptors: [
        AuthInterceptor(
          storage: secureStorage,
          baseUrl: apiBaseUrl,
          onAuthExpired: onAuthExpired,
        ),
      ],
    );

    final locationRepository = LocationRepositoryImpl(api: dioClient);

    return ServiceLocator._(
      dioClient: dioClient,
      wsClient: wsClient,
      secureStorage: secureStorage,
      cameraService: CameraService(),
      pushNotificationService: PushNotificationService(),
      desktopNotificationService: DesktopNotificationService(),
      authRepository: AuthRepositoryImpl(api: dioClient, storage: secureStorage),
      dashboardRepository: DashboardRepositoryImpl(api: dioClient),
      trailerRepository: TrailerRepositoryImpl(api: dioClient),
      productionRepository: ProductionRepositoryImpl(api: dioClient),
      qcRepository: QcRepositoryImpl(api: dioClient),
      deliveryRepository: DeliveryRepositoryImpl(
        api: dioClient,
        locationRepository: locationRepository,
      ),
      payrollRepository: PayrollRepositoryImpl(api: dioClient),
      adminRepository: AdminRepositoryImpl(api: dioClient),
      customerRepository: CustomerRepositoryImpl(api: dioClient),
      locationRepository: locationRepository,
      messageRepository: MessageRepositoryImpl(api: dioClient),
      notificationRepository: NotificationRepositoryImpl(api: dioClient),
      storageRepository: StorageRepositoryImpl(api: dioClient),
      announcementRepository: AnnouncementRepositoryImpl(api: dioClient),
    );
  }

  Future<void> dispose() async {
    wsClient.dispose();
    await storageRepository.dispose();
  }
}
