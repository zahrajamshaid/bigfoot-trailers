import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/user.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/payroll_viewmodel.dart';

class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  bool _loading = true;
  String? _error;
  dynamic _report;
  DateTime _weekStart = DateTime.now().toUtc();
  bool _locking = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<PayrollViewModel>();
    _weekStart = c.weekStartSunday(DateTime.now().toUtc());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final week = _fmt(_weekStart);
      final report = await context.read<PayrollViewModel>().getWeeklyReport(week);
      if (!mounted) return;
      setState(() => _report = report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>().state;
    final role = auth is Authenticated ? auth.user.role : '';
    final canLock = role == UserRole.owner;

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Payroll Report')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _error != null
              ? _ErrorBody(message: _error!, onRetry: _load)
              : _ReportBody(
                  report: _report,
                  weekStart: _weekStart,
                  onPrev: () {
                    setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
                    _load();
                  },
                  onNext: () {
                    setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
                    _load();
                  },
                  canLock: canLock,
                  locking: _locking,
                  onLock: () async {
                    final cubit = context.read<PayrollViewModel>();
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Lock Payroll Week'),
                            content: Text(
                              'Lock payroll for ${_fmt(_weekStart)}? This cannot be undone.',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lock')),
                            ],
                          ),
                        ) ??
                        false;
                    if (!mounted) return;
                    if (!ok) return;

                    setState(() => _locking = true);
                    try {
                      await cubit.lockWeek(_fmt(_weekStart));
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Payroll week locked')),
                      );
                      _load();
                    } catch (e) {
                      if (!mounted) return;
                      final msg = e.toString();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            msg.contains('PAYROLL_WEEK_LOCKED')
                                ? 'Already locked'
                                : msg.contains('INVALID_WEEK_START')
                                    ? 'Date must be a Sunday'
                                    : 'Failed to lock week: $e',
                          ),
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _locking = false);
                    }
                  },
                  onExportCsv: () {
                    final csv = _buildCsv(_report);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('CSV prepared (${csv.length} chars)')),
                    );
                  },
                ),
    );
  }

  String _fmt(DateTime d) => d.toIso8601String().split('T').first;

  String _buildCsv(dynamic report) {
    final buffer = StringBuffer('Name,Total Points,Steps,Reworks,Gross Pay\n');
    for (final w in report.workers as List<dynamic>) {
      buffer.writeln(
        '"${w.fullName}",${w.totalPoints},${w.totalStepsCompleted},${w.totalReworkCount},${w.totalGrossPay}',
      );
    }
    return buffer.toString();
  }
}

class _ReportBody extends StatelessWidget {
  final dynamic report;
  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool canLock;
  final bool locking;
  final VoidCallback onLock;
  final VoidCallback onExportCsv;

  const _ReportBody({
    required this.report,
    required this.weekStart,
    required this.onPrev,
    required this.onNext,
    required this.canLock,
    required this.locking,
    required this.onLock,
    required this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) {
    final workers = report.workers as List<dynamic>;
    final totalPoints = workers.fold<double>(0, (s, w) => s + (w.totalPoints as double));
    final totalGross = workers.fold<double>(0, (s, w) => s + (w.totalGrossPay as double));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Center(
                child: Text(
                  '${report.weekStartDate} - ${report.weekEndDate}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ],
        ),
        const SizedBox(height: 8),
        if (report.isLocked)
          const Row(
            children: [
              Icon(Icons.lock, size: 16, color: AppColors.navy),
              SizedBox(width: 6),
              Text('Week is locked'),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: onExportCsv,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
            ),
            const SizedBox(width: 8),
            if (canLock)
              FilledButton.icon(
                onPressed: report.isLocked || locking ? null : onLock,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Lock Week'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(12),
            color: AppColors.white,
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Expanded(flex: 3, child: Text('Name', style: TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(child: Text('Points', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(child: Text('Steps', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(child: Text('Reworks', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(child: Text('Gross', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w700))),
                ],
              ),
              const Divider(),
              ...workers.map(
                (w) => ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Row(
                    children: [
                      Expanded(flex: 3, child: Text(w.fullName)),
                      Expanded(child: Text(w.totalPoints.toStringAsFixed(2), textAlign: TextAlign.end)),
                      Expanded(child: Text('${w.totalStepsCompleted}', textAlign: TextAlign.end)),
                      Expanded(child: Text('${w.totalReworkCount}', textAlign: TextAlign.end)),
                      Expanded(
                        child: Text(
                          r'$ ${w.totalGrossPay.toStringAsFixed(2)}',
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  children: [
                    ...((w.departments as List<dynamic>).map(
                      (d) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text('${d.departmentCode} - ${d.departmentName}')),
                            Text(
                              '${d.totalPoints.toStringAsFixed(2)} pts • '
                              '${d.stepsCompleted} steps • '
                              '${d.reworkCount} rw • '
                              r'$ ${d.grossPay.toStringAsFixed(2)}',
                            ),
                          ],
                        ),
                      ),
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Totals: ${totalPoints.toStringAsFixed(2)} points • '
            '\$ ${totalGross.toStringAsFixed(2)}',
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
