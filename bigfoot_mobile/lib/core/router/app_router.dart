import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/view/admin_dashboard_screen.dart';
import '../../features/admin/view/audit_log_screen.dart';
import '../../features/admin/view/production_cost_matrix_screen.dart';
import '../../features/admin/view/production_report_screen.dart';
import '../../features/announcements/view/announcements_admin_screen.dart';
import '../../features/admin/view/department_config_screen.dart';
import '../../features/admin/view/user_management_screen.dart';
import '../../features/admin/view/workflow_viewer_screen.dart';
import '../../features/auth/view/login_screen.dart';
import '../../features/auth/view/splash_screen.dart';
import '../../features/auth/viewmodel/auth_viewmodel.dart';
import '../../features/dashboard/view/dashboard_screen.dart';
import '../../features/help/view/sales_guide_screen.dart';
import '../../features/deliveries/view/batch_screen.dart';
import '../../features/deliveries/view/create_delivery_screen.dart';
import '../../features/deliveries/view/delivery_detail_screen.dart';
import '../../features/deliveries/view/delivery_list_screen.dart';
import '../../features/deliveries/view/driver_delivery_screen.dart';
import '../../features/deliveries/view/stock_inventory_screen.dart';
import '../../features/notifications/view/message_screen.dart';
import '../../features/notifications/view/notification_center.dart';
import '../../features/payroll/view/dollar_rates_screen.dart';
import '../../features/payroll/view/point_matrix_screen.dart';
import '../../features/payroll/view/weekly_report_screen.dart';
import '../../features/payroll/view/worker_points_screen.dart';
import '../../features/production/view/all_queues_screen.dart';
import '../../features/production/view/queue_screen.dart';
import '../../features/qc/view/checklist_management_screen.dart';
import '../../features/qc/view/inspection_detail_screen.dart';
import '../../features/qc/view/inspection_form_screen.dart';
import '../../features/qc/view/qc_failed_screen.dart';
import '../../features/qc/view/qc_rework_screen.dart';
import '../../features/qc/view/qc_queue_screen.dart';
import '../../features/qc/viewmodel/qc_viewmodel.dart';
import '../../domain/repositories/qc_repository.dart';
import '../websocket/ws_client.dart';
import '../../features/settings/view/settings_screen.dart';
import '../../features/shell/view/app_shell.dart';
import '../../data/models/trailer.dart';
import '../../features/trailers/view/create_trailer_screen.dart';
import '../../features/trailers/view/edit_trailer_screen.dart';
import '../../features/trailers/view/trailer_detail_screen.dart';
import '../../features/trailers/view/trailer_list_screen.dart';
import '../../shared/widgets/pdf_viewer_screen.dart';
import '../../shared/widgets/secure_screen.dart';
import 'route_names.dart';

/// Application router with auth redirect and role-based guards.
class AppRouter {
  final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');
  final GlobalKey<NavigatorState> _shellNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'shell');

  late final GoRouter router;

  AppRouter() {
    router = GoRouter(
      navigatorKey: _rootNavigatorKey,
      debugLogDiagnostics: true,
      initialLocation: '/',
      redirect: _authRedirect,
      routes: [
        // ── Splash ─────────────────────────────────────────────────────
        GoRoute(
          path: '/',
          name: RouteNames.splash,
          builder: (context, state) => const SplashScreen(),
        ),

        // ── Login ──────────────────────────────────────────────────────
        GoRoute(
          path: '/login',
          name: RouteNames.login,
          builder: (context, state) => const LoginScreen(),
        ),

        // ── App Shell (authenticated) ──────────────────────────────────
        ShellRoute(
          navigatorKey: _shellNavigatorKey,
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              name: RouteNames.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: '/trailers',
              name: RouteNames.trailerList,
              builder: (context, state) {
                final q = state.uri.queryParameters;
                return TrailerListScreen(
                  initialStatus: q['status'],
                  initialHotOnly: q['hot'] == 'true',
                  initialCompletedSince: q['completedSince'],
                );
              },
              routes: [
                GoRoute(
                  path: 'create',
                  name: RouteNames.trailerCreate,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const CreateTrailerScreen(),
                ),
                GoRoute(
                  path: ':id',
                  name: RouteNames.trailerDetail,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) {
                    final id =
                        int.parse(state.pathParameters['id']!);
                    return TrailerDetailScreen(trailerId: id);
                  },
                ),
                GoRoute(
                  path: ':id/edit',
                  name: RouteNames.trailerEdit,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) {
                    final trailer = state.extra as Trailer;
                    return EditTrailerScreen(trailer: trailer);
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/production',
              name: RouteNames.productionQueue,
              builder: (context, state) => QueueScreen(
                initialStalledOnly:
                    state.uri.queryParameters['filter'] == 'stalled',
              ),
              routes: [
                GoRoute(
                  path: 'all',
                  name: RouteNames.productionAllQueues,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const AllQueuesScreen(),
                ),
              ],
            ),
            GoRoute(
              path: '/qc',
              name: RouteNames.qcQueue,
              redirect: _qcOnly,
              builder: (context, state) => QcQueueScreen(
                initialReworkOnly:
                    state.uri.queryParameters['filter'] == 'rework',
              ),
              routes: [
                GoRoute(
                  path: 'failed',
                  name: RouteNames.qcFailed,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const QcFailedScreen(),
                ),
                GoRoute(
                  path: 'rework',
                  name: RouteNames.qcRework,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const QcReworkScreen(),
                ),
                GoRoute(
                  path: 'inspect/:stepId',
                  name: RouteNames.qcInspectionForm,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) {
                    final item = state.extra as QcQueueItem;
                    return BlocProvider(
                      create: (ctx) => QcViewModel(
                        repository: ctx.read<QcRepository>(),
                        ws: ctx.read<WsClient>(),
                      ),
                      child: InspectionFormScreen(item: item),
                    );
                  },
                ),
                GoRoute(
                  path: 'inspection/:id',
                  name: RouteNames.qcInspectionDetail,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) {
                    final id = int.parse(state.pathParameters['id']!);
                    return InspectionDetailScreen(inspectionId: id);
                  },
                ),
                GoRoute(
                  path: 'checklist',
                  name: 'qcChecklistManagement',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) =>
                      const ChecklistManagementScreen(),
                ),
              ],
            ),
            GoRoute(
              path: '/deliveries',
              name: RouteNames.deliveryList,
              builder: (context, state) {
                final auth = context.read<AuthViewModel>().state;
                if (auth is Authenticated && auth.user.role == 'driver') {
                  return const DriverDeliveryScreen();
                }
                return DeliveryListScreen(
                  initialStatus: state.uri.queryParameters['status'],
                );
              },
              routes: [
                GoRoute(
                  path: 'create',
                  name: RouteNames.deliveryCreate,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => CreateDeliveryScreen(
                    startInBatchMode:
                        state.uri.queryParameters['mode'] == 'batch',
                  ),
                ),
                GoRoute(
                  path: 'stock-inventory',
                  name: RouteNames.stockInventory,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const StockInventoryScreen(),
                ),
                GoRoute(
                  path: 'batches',
                  name: RouteNames.deliveryBatches,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const BatchScreen(),
                ),
                GoRoute(
                  path: 'driver',
                  name: RouteNames.deliveryDriver,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const DriverDeliveryScreen(),
                ),
                // The dynamic :id route must be declared LAST — otherwise it
                // greedily matches literal child paths (batches, driver) and
                // int.parse() throws a FormatException on "batches".
                GoRoute(
                  path: ':id',
                  name: RouteNames.deliveryDetail,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) {
                    final id = int.parse(state.pathParameters['id']!);
                    return DeliveryDetailScreen(deliveryId: id);
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/payroll',
              name: RouteNames.workerPoints,
              builder: (context, state) =>
                  const SecureScreen(child: WorkerPointsScreen()),
              routes: [
                GoRoute(
                  path: 'weekly-report',
                  name: RouteNames.weeklyReport,
                  parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) =>
                        const SecureScreen(child: WeeklyReportScreen()),
                ),
                GoRoute(
                  path: 'point-matrix',
                  name: RouteNames.pointMatrix,
                  parentNavigatorKey: _rootNavigatorKey,
                  redirect: _ownerOnly,
                    builder: (context, state) =>
                        const SecureScreen(child: PointMatrixScreen()),
                ),
                GoRoute(
                  path: 'dollar-rates',
                  name: RouteNames.dollarRates,
                  parentNavigatorKey: _rootNavigatorKey,
                  redirect: _ownerOnly,
                    builder: (context, state) =>
                        const SecureScreen(child: DollarRatesScreen()),
                ),
              ],
            ),
            GoRoute(
              path: '/admin',
              name: RouteNames.adminDashboard,
              redirect: _adminOnly,
              builder: (context, state) => const AdminDashboardScreen(),
              routes: [
                GoRoute(
                  path: 'users',
                  name: RouteNames.userManagement,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const UserManagementScreen(),
                ),
                GoRoute(
                  path: 'departments',
                  name: RouteNames.departmentConfig,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const DepartmentConfigScreen(),
                ),
                GoRoute(
                  path: 'workflows',
                  name: RouteNames.workflowViewer,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const WorkflowViewerScreen(),
                ),
                GoRoute(
                  path: 'audit-log',
                  name: RouteNames.auditLog,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const AuditLogScreen(),
                ),
                GoRoute(
                  path: 'announcements',
                  name: RouteNames.announcementsAdmin,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const AnnouncementsAdminScreen(),
                ),
                GoRoute(
                  path: 'production-costs',
                  name: RouteNames.productionCostMatrix,
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) =>
                      const ProductionCostMatrixScreen(),
                ),
              ],
            ),
            // Production report lives outside /admin so production_manager can
            // open it without crossing the admin guard, and so popping back
            // never lands them on the admin dashboard. Owner reaches it from
            // either the main dashboard or the admin nav tile — both work
            // because pushNamed records the actual prior route.
            GoRoute(
              path: '/production-report',
              name: RouteNames.productionReport,
              redirect: _productionReportAccess,
              builder: (context, state) => const ProductionReportScreen(),
            ),
            GoRoute(
              path: '/settings',
              name: RouteNames.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
            GoRoute(
              path: '/sales-guide',
              name: RouteNames.salesGuide,
              builder: (context, state) => const SalesGuideScreen(),
            ),
          ],
        ),

        // ── Full-screen routes (outside shell) ─────────────────────────
        GoRoute(
          path: '/notifications',
          name: RouteNames.notificationsCenter,
          builder: (context, state) => const NotificationCenter(),
        ),
        GoRoute(
          path: '/messages/:trailerId',
          name: RouteNames.workerMessages,
          builder: (context, state) {
            final trailerId = int.parse(state.pathParameters['trailerId']!);
            return MessageScreen(trailerId: trailerId);
          },
        ),
        GoRoute(
          path: '/pdf-viewer',
          name: RouteNames.pdfViewer,
          builder: (context, state) => PdfViewerScreen(
            args: state.extra! as PdfViewerArgs,
          ),
        ),
      ],
    );
  }

  /// Redirect unauthenticated users to login, authenticated users away from login.
  String? _authRedirect(BuildContext context, GoRouterState state) {
    final authState = context.read<AuthViewModel>().state;
    final isAuthenticated = authState is Authenticated;
    final isOnSplash = state.matchedLocation == '/';
    final isOnLogin = state.matchedLocation == '/login';

    if (isOnSplash) return null;

    if (!isAuthenticated && !isOnLogin) return '/login';

    if (isAuthenticated && isOnLogin) return '/dashboard';

    return null;
  }

  /// Guards payroll-config screens (point matrix + dollar rates). Owner
  /// and production_manager both have full payroll powers on the backend
  /// (POST / PATCH point-values, POST dollar-rates, week lock); the UI
  /// gate now mirrors that. Everyone else is bounced back to the payroll
  /// landing page so they never see the screen.
  String? _ownerOnly(BuildContext context, GoRouterState state) {
    final authState = context.read<AuthViewModel>().state;
    if (authState is Authenticated &&
        (authState.user.role == 'owner' ||
            authState.user.role == 'production_manager')) {
      return null;
    }
    return '/payroll';
  }

  /// Guards the /admin area — owner-only. Without this guard a Forbidden
  /// response inside an /admin/* child screen left the user one Back press
  /// away from the unguarded admin dashboard. Anyone else lands back on the
  /// general dashboard.
  String? _adminOnly(BuildContext context, GoRouterState state) {
    final authState = context.read<AuthViewModel>().state;
    if (authState is Authenticated && authState.user.role == 'owner') {
      return null;
    }
    return '/dashboard';
  }

  /// Production report is visible to owner + production_manager. Anyone
  /// else gets bounced to their normal home dashboard (the report tile is
  /// already hidden for those roles; this guard catches deep links + Back
  /// pops).
  String? _productionReportAccess(BuildContext context, GoRouterState state) {
    final authState = context.read<AuthViewModel>().state;
    if (authState is Authenticated &&
        (authState.user.role == 'owner' ||
            authState.user.role == 'production_manager')) {
      return null;
    }
    return '/dashboard';
  }

  /// Guards the QC area (queue, failed list, rework list, inspect form,
  /// inspection detail). Mirrors the backend's `@Roles` on `POST /qc/inspections`
  /// and `GET /qc/*` — qc_inspector + production_manager + owner only.
  ///
  /// Sits on the parent `/qc` route so it fires on direct hits AND when a
  /// child screen pops back onto the queue. Without this, tapping the
  /// QC-fail-rate tile from a sales dashboard bounced through the failed
  /// screen's "permission denied" and dropped the user on the unguarded
  /// queue — letting them browse trailers waiting on inspection.
  String? _qcOnly(BuildContext context, GoRouterState state) {
    final authState = context.read<AuthViewModel>().state;
    if (authState is Authenticated &&
        (authState.user.role == 'owner' ||
            authState.user.role == 'production_manager' ||
            authState.user.role == 'qc_inspector')) {
      return null;
    }
    return '/dashboard';
  }
}
