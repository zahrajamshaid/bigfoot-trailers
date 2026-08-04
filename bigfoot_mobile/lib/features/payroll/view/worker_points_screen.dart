import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/payroll_viewmodel.dart';

class WorkerPointsScreen extends StatefulWidget {
  const WorkerPointsScreen({super.key});

  @override
  State<WorkerPointsScreen> createState() => _WorkerPointsScreenState();
}

class _WorkerPointsScreenState extends State<WorkerPointsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  bool _isManager() {
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) return false;
    final role = auth.user.role;
    return role == UserRole.owner ||
        role == UserRole.office ||
        role == UserRole.productionManager;
  }

  void _load() {
    // Payroll data is gated to owner/office/PM on the backend, so don't hit the
    // summary endpoint (it 403s) for a worker — they get a placeholder instead.
    if (!_isManager()) return;
    final auth = context.read<AuthViewModel>().state;
    if (auth is Authenticated) {
      context.read<PayrollViewModel>().loadWorkerSummary(auth.user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = context.watch<AuthViewModel>().state;
    final user = auth is Authenticated ? auth.user : null;
    final isManager = user != null &&
        (user.role == UserRole.owner ||
            user.role == UserRole.office ||
            user.role == UserRole.productionManager);

    // Payroll is gated to owner/office/PM. Workers see the tab (nav placeholder)
    // but not the numbers — a clean message instead of a 403.
    if (!isManager) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: AppColors.disabled),
                const SizedBox(height: 16),
                const Text(
                  'Payroll is managed by your admin',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your pay details aren\'t shown here yet. Talk to the office if you have questions.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: BlocBuilder<PayrollViewModel, PayrollState>(
          builder: (context, state) {
            if (state is PayrollLoading || state is PayrollInitial) {
              return ListView(
                children: const [
                  SizedBox(height: 280),
                  Center(
                    child: CircularProgressIndicator(color: AppColors.amber),
                  ),
                ],
              );
            }
            if (state is PayrollError) {
              return ListView(
                children: [
                  const SizedBox(height: 200),
                  const Icon(Icons.error_outline, color: AppColors.error, size: 42),
                  const SizedBox(height: 10),
                  Center(child: Text(state.message)),
                  const SizedBox(height: 10),
                  Center(
                    child: OutlinedButton(
                      onPressed: _load,
                      child: Text(l.commonRetry),
                    ),
                  ),
                ],
              );
            }

            final loaded = state as PayrollLoaded;
            final s = loaded.summary;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (isManager)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => context.pushNamed(RouteNames.weeklyReport),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: Text(l.payrollWeeklyReport),
                      ),
                      // Pay is now a flat rate per model+department (points
                      // retired). The pay + cost matrix and the stage crews are
                      // the payroll config screens now.
                      if (isManager)
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.pushNamed(RouteNames.stageRatesMatrix),
                          icon: const Icon(Icons.grid_view_outlined),
                          label: const Text('Pay & cost matrix'),
                        ),
                      if (isManager)
                        OutlinedButton.icon(
                          onPressed: () => context.pushNamed(RouteNames.stageCrews),
                          icon: const Icon(Icons.groups_outlined),
                          label: const Text('Stage crews'),
                        ),
                    ],
                  ),
                if (isManager) const SizedBox(height: 12),
                _SummaryCard(summary: s),
                const SizedBox(height: 12),
                _DailyChart(points: loaded.dailyPoints),
                const SizedBox(height: 12),
                _DepartmentBreakdown(summary: s),
                const SizedBox(height: 12),
                _HistoryCard(
                  historyUnavailable: loaded.historyUnavailable,
                  historyCount: loaded.history.length,
                  history: loaded.history,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final dynamic summary;

  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.payrollCurrentWeekSummary,
            style: const TextStyle(
                color: AppColors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            summary.totalPoints.toStringAsFixed(2),
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(l.payrollTotalPoints,
              style: const TextStyle(color: AppColors.white)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _mini(l.payrollProjected,
                  r'$ ' + summary.projectedEarnings.toStringAsFixed(2)),
              _mini(l.payrollSteps, '${summary.stepsCompleted}'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l.payrollReworks(summary.reworkCount as int),
                  style: const TextStyle(color: AppColors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: AppColors.white),
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  final List<double> points;

  const _DailyChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final days = [
      l.payrollDaySun,
      l.payrollDayMon,
      l.payrollDayTue,
      l.payrollDayWed,
      l.payrollDayThu,
      l.payrollDayFri,
      l.payrollDaySat,
    ];
    final max = points.fold<double>(0, (m, v) => v > m ? v : m);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.payrollDailyBreakdown,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final h = max == 0 ? 0.0 : (points[i] / max) * 90;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 18,
                        height: h + 4,
                        decoration: BoxDecoration(
                          color: AppColors.amber,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(days[i], style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.payrollEstimated,
            style: const TextStyle(fontSize: 11, color: AppColors.disabled),
          ),
        ],
      ),
    );
  }
}

class _DepartmentBreakdown extends StatelessWidget {
  final dynamic summary;

  const _DepartmentBreakdown({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final departments = summary.departments as List<dynamic>;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.payrollDeptBreakdown,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (departments.isEmpty)
            Text(l.payrollDeptEmpty)
          else
            ...departments.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text('${d.code} - ${d.name}')),
                    Text(l.payrollPtsSuffix(
                        (d.points as double).toStringAsFixed(2))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final bool historyUnavailable;
  final int historyCount;
  final List<dynamic> history;

  const _HistoryCard({
    required this.historyUnavailable,
    required this.historyCount,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.payrollHistory,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (historyUnavailable)
            Text(l.payrollHistoryNoAccess)
          else if (historyCount == 0)
            Text(l.payrollHistoryEmpty)
          else
            ...history.take(8).map(
              (r) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(r.department?.displayName ??
                    l.payrollDepartmentFallback),
                subtitle: Text(r.weekStartDate.toIso8601String().split('T').first),
                trailing: Text(r.totalPoints.toStringAsFixed(2)),
              ),
            ),
        ],
      ),
    );
  }
}
