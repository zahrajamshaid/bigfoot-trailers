import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';

/// Payroll landing. Admins (owner/office/PM) get the config shortcuts + a REAL
/// shop-wide current-week summary. Payroll is gated on the backend, so workers
/// see a clean placeholder.
class WorkerPointsScreen extends StatelessWidget {
  const WorkerPointsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = context.watch<AuthViewModel>().state;
    final user = auth is Authenticated ? auth.user : null;
    final isManager = user != null &&
        (user.role == UserRole.owner ||
            user.role == UserRole.office ||
            user.role == UserRole.productionManager);

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
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy),
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.pushNamed(RouteNames.weeklyReport),
                icon: const Icon(Icons.table_chart_outlined),
                label: Text(l.payrollWeeklyReport),
              ),
              OutlinedButton.icon(
                onPressed: () => context.pushNamed(RouteNames.stageRatesMatrix),
                icon: const Icon(Icons.grid_view_outlined),
                label: const Text('Pay matrix'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.pushNamed(RouteNames.stageCrews),
                icon: const Icon(Icons.groups_outlined),
                label: const Text('Stage crews'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    context.pushNamed(RouteNames.payrollAdjustments),
                icon: const Icon(Icons.tune),
                label: const Text('Adjustments'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _ShopWeekSummary(),
        ],
      ),
    );
  }
}

/// Real shop-wide current-week payroll: total gross pay, steps, workers, and a
/// per-day bar chart — all from the payout data.
class _ShopWeekSummary extends StatefulWidget {
  const _ShopWeekSummary();

  @override
  State<_ShopWeekSummary> createState() => _ShopWeekSummaryState();
}

class _ShopWeekSummaryState extends State<_ShopWeekSummary> {
  bool _loading = true;
  String? _error;
  double _total = 0;
  int _workers = 0;
  int _steps = 0;
  List<double> _daily = const [0, 0, 0, 0, 0, 0, 0];
  String _weekStart = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await context.read<DioClient>().get<Map<String, dynamic>>(
            ApiEndpoints.payrollCurrentWeekSummary,
            fromJson: (d) => d as Map<String, dynamic>,
          );
      final d = resp.data ?? const {};
      if (mounted) {
        setState(() {
          _total = (d['totalGrossPay'] as num?)?.toDouble() ?? 0;
          _workers = (d['workerCount'] as num?)?.toInt() ?? 0;
          _steps = (d['stepsCompleted'] as num?)?.toInt() ?? 0;
          _daily = ((d['daily'] as List<dynamic>?) ?? const [])
              .map((e) => (e as num?)?.toDouble() ?? 0)
              .toList();
          if (_daily.length != 7) _daily = List<double>.filled(7, 0);
          _weekStart = d['weekStartDate'] as String? ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: AppColors.amber)),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          const SizedBox(height: 20),
          Text('Could not load this week', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total pay hero card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.navy, Color(0xFF2C5364)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This week\'s pay${_weekStart.isNotEmpty ? ' · from $_weekStart' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              Text('\$${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: AppColors.white, fontSize: 32, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _pill('$_steps steps'),
                  const SizedBox(width: 8),
                  _pill('$_workers workers'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Pay per day',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
        const SizedBox(height: 8),
        _DailyBars(daily: _daily),
        const SizedBox(height: 12),
        Text(
          'Tap "Weekly report" above for the per-worker breakdown.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 12)),
      );
}

class _DailyBars extends StatelessWidget {
  final List<double> daily;
  const _DailyBars({required this.daily});

  static const _labels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  @override
  Widget build(BuildContext context) {
    final max = daily.fold<double>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final v = i < daily.length ? daily[i] : 0.0;
          final h = max <= 0 ? 0.0 : (v / max) * 100;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (v > 0)
                  Text(v.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 10, color: AppColors.navy)),
                const SizedBox(height: 2),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: h + 2,
                  decoration: BoxDecoration(
                    color: v > 0 ? AppColors.amber : AppColors.disabled.withValues(alpha: 0.3),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(_labels[i], style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          );
        }),
      ),
    );
  }
}
