import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
    final auth = context.watch<AuthViewModel>().state;
    final role = auth is Authenticated ? auth.user.role : '';
    final canLock = role == UserRole.owner;

    return Scaffold(
      appBar: AppBar(title: Text(l.payrollWeeklyReportTitle)),
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
                            title: Text(l.payrollLockTitle),
                            content: Text(l.payrollLockBody(_fmt(_weekStart))),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: Text(l.commonCancel)),
                              FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(l.payrollLockConfirm)),
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
                        SnackBar(content: Text(l.payrollWeekLocked)),
                      );
                      _load();
                    } catch (e) {
                      if (!mounted) return;
                      final msg = e.toString();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            msg.contains('PAYROLL_WEEK_LOCKED')
                                ? l.payrollAlreadyLocked
                                : msg.contains('INVALID_WEEK_START')
                                    ? l.payrollDateMustBeSunday
                                    : l.payrollLockFailed('$e'),
                          ),
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _locking = false);
                    }
                  },
                  onExportCsv: () => _exportCsv(context, l),
                ),
    );
  }

  String _fmt(DateTime d) => d.toIso8601String().split('T').first;

  String _buildCsv(dynamic report) {
    final buffer = StringBuffer('Name,Total Points,Steps,Reworks,Gross Pay\n');
    for (final w in report.workers as List<dynamic>) {
      // Escape any embedded double-quotes per RFC 4180 so the CSV opens
      // cleanly in Excel / Numbers / Google Sheets.
      final safeName = w.fullName.toString().replaceAll('"', '""');
      buffer.writeln(
        '"$safeName",${w.totalPoints},${w.totalStepsCompleted},${w.totalReworkCount},${w.totalGrossPay}',
      );
    }
    return buffer.toString();
  }

  /// Write the CSV to a temp file and hand it to the platform share sheet.
  /// On web, fall back to a synthesised download because file paths aren't
  /// shareable in the browser. Snackbar on success / error so the user gets
  /// feedback either way.
  Future<void> _exportCsv(
    BuildContext context,
    AppLocalizations l,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = _buildCsv(_report);
      final filename = 'bigfoot-payroll-${_fmt(_weekStart)}.csv';

      if (kIsWeb) {
        // share_plus on web only handles text, not files — push the
        // serialised CSV as text so the user can paste it into a sheet.
        await SharePlus.instance.share(
          ShareParams(
            text: csv,
            subject: filename,
          ),
        );
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsString(csv, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/csv', name: filename)],
            subject: filename,
          ),
        );
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l.payrollCsvPrepared(csv.length))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('CSV export failed: $e')),
      );
    }
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
    final l = AppLocalizations.of(context);
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
          Row(
            children: [
              const Icon(Icons.lock, size: 16, color: AppColors.navy),
              const SizedBox(width: 6),
              Text(l.payrollWeekIsLocked),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: onExportCsv,
              icon: const Icon(Icons.download_outlined),
              label: Text(l.payrollExportCsv),
            ),
            const SizedBox(width: 8),
            if (canLock)
              FilledButton.icon(
                onPressed: report.isLocked || locking ? null : onLock,
                icon: const Icon(Icons.lock_outline),
                label: Text(l.payrollLockWeek),
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
              Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text(l.payrollColName,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(
                      child: Text(l.payrollColPoints,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(
                      child: Text(l.payrollSteps,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(
                      child: Text(l.payrollColReworks,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(
                      child: Text(l.payrollColGross,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
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
            l.payrollTotals(
                totalPoints.toStringAsFixed(2), totalGross.toStringAsFixed(2)),
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
    final l = AppLocalizations.of(context);
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
            OutlinedButton(
                onPressed: onRetry, child: Text(l.commonRetry)),
          ],
        ),
      ),
    );
  }
}
