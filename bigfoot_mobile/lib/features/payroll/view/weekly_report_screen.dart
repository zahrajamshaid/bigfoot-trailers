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
    // Backend RBAC was extended to let production_manager lock the week,
    // so mirror it here.
    final canLock =
        role == UserRole.owner || role == UserRole.productionManager;

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
    // CSV escape per RFC 4180 — quote-wrap any cell that contains a
    // comma / quote / newline and double any embedded quotes.
    String esc(Object? v) {
      final s = v == null ? '' : v.toString();
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final buffer = StringBuffer();

    // Summary block — one row per worker, easy to drop into a pivot.
    buffer.writeln('# Worker totals');
    buffer.writeln('Worker,Total Points,Steps,Reworks,Gross Pay');
    for (final w in report.workers as List<dynamic>) {
      buffer.writeln([
        esc(w.fullName),
        w.totalPoints,
        w.totalStepsCompleted,
        w.totalReworkCount,
        w.totalGrossPay,
      ].join(','));
    }

    // Detail block — one row per (worker, dept, trailer) so payroll can
    // reconcile against QB / order list. This is the part the team asked
    // for explicitly.
    buffer.writeln();
    buffer.writeln('# Trailer breakdown');
    buffer.writeln(
        'Worker,Department,SO,Size (ft),Model,Points,Rework,Gross Contribution');
    for (final w in report.workers as List<dynamic>) {
      final wname = esc(w.fullName);
      for (final d in (w.departments as List<dynamic>)) {
        final dept = esc('${d.departmentCode} · ${d.departmentName}');
        final dpp = (d.dollarPerPoint as num).toDouble();
        for (final t in (d.trailers as List<dynamic>?) ?? const []) {
          final pts = (t.points as num).toDouble();
          buffer.writeln([
            wname,
            dept,
            esc(t.soNumber),
            esc(t.sizeFt ?? ''),
            esc(t.modelName ?? ''),
            pts.toStringAsFixed(2),
            (t.isRework == true) ? 'yes' : 'no',
            (pts * dpp).toStringAsFixed(2),
          ].join(','));
        }
      }
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
    final workers = (report.workers as List<dynamic>);
    final totalPoints =
        workers.fold<double>(0, (s, w) => s + (w.totalPoints as double));
    final totalGross =
        workers.fold<double>(0, (s, w) => s + (w.totalGrossPay as double));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Week nav ────────────────────────────────────────────────────
        Row(
          children: [
            IconButton(
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous week',
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${report.weekStartDate}  –  ${report.weekEndDate}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next week',
            ),
          ],
        ),
        if (report.isLocked) ...[
          const SizedBox(height: 4),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 14, color: AppColors.navy),
                  const SizedBox(width: 4),
                  Text(l.payrollWeekIsLocked,
                      style: const TextStyle(
                          color: AppColors.navy, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),

        // ── Totals header ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      totalPoints.toStringAsFixed(2),
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    const Text('Total points',
                        style: TextStyle(color: AppColors.white, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 38,
                color: AppColors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\$${totalGross.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    const Text('Gross pay',
                        style: TextStyle(color: AppColors.white, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Action row ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onExportCsv,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(l.payrollExportCsv),
              ),
            ),
            if (canLock) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: report.isLocked || locking ? null : onLock,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: Text(l.payrollLockWeek),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        if (workers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'No completed steps this week.',
                style: TextStyle(color: AppColors.disabled),
              ),
            ),
          )
        else
          ...workers.map((w) => _WorkerCard(worker: w)),
      ],
    );
  }
}

/// One card per worker — header shows name + headline stats, expanding
/// reveals each department's breakdown and the trailers worked on.
class _WorkerCard extends StatelessWidget {
  final dynamic worker;
  const _WorkerCard({required this.worker});

  @override
  Widget build(BuildContext context) {
    final pts = (worker.totalPoints as double).toStringAsFixed(2);
    final gross = (worker.totalGrossPay as double).toStringAsFixed(2);
    final steps = worker.totalStepsCompleted;
    final reworks = worker.totalReworkCount;
    final depts = (worker.departments as List<dynamic>);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(
            worker.fullName,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _Pill(label: '$pts pts', color: AppColors.navy),
                _Pill(label: '\$$gross', color: AppColors.success),
                _Pill(label: '$steps steps', color: AppColors.disabled),
                if (reworks > 0)
                  _Pill(label: '$reworks rework', color: AppColors.warning),
              ],
            ),
          ),
          children: depts.map<Widget>((d) => _DeptTile(dept: d)).toList(),
        ),
      ),
    );
  }
}

/// One section per department for a worker — expanding reveals the trailers.
class _DeptTile extends StatelessWidget {
  final dynamic dept;
  const _DeptTile({required this.dept});

  @override
  Widget build(BuildContext context) {
    final pts = (dept.totalPoints as double).toStringAsFixed(2);
    final gross = (dept.grossPay as double).toStringAsFixed(2);
    final steps = dept.stepsCompleted;
    final reworks = dept.reworkCount;
    final trailers = (dept.trailers as List<dynamic>?) ?? const [];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 10, 10),
          title: Text(
            dept.departmentName,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13.5),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                _Pill(label: dept.departmentCode, color: AppColors.navy,
                    small: true),
                _Pill(label: '$pts pts', color: AppColors.navy, small: true),
                _Pill(label: '\$$gross', color: AppColors.success, small: true),
                _Pill(label: '$steps steps', color: AppColors.disabled,
                    small: true),
                if (reworks > 0)
                  _Pill(label: '$reworks rw', color: AppColors.warning,
                      small: true),
              ],
            ),
          ),
          children: trailers.isEmpty
              ? const [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('No trailers recorded.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.disabled)),
                  )
                ]
              : trailers.map<Widget>((t) => _TrailerLine(trailer: t)).toList(),
        ),
      ),
    );
  }
}

class _TrailerLine extends StatelessWidget {
  final dynamic trailer;
  const _TrailerLine({required this.trailer});

  @override
  Widget build(BuildContext context) {
    final size = (trailer.sizeFt ?? '') as String;
    final model = (trailer.modelName ?? '') as String;
    final pts = (trailer.points as double).toStringAsFixed(2);
    final isRework = trailer.isRework == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.local_shipping_outlined,
              size: 14, color: AppColors.disabled),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SO ${trailer.soNumber}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    [
                      if (size.isNotEmpty) '${size}ft',
                      if (model.isNotEmpty) model,
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.disabled),
                  ),
                ),
              ],
            ),
          ),
          if (isRework)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child:
                  _Pill(label: 'rw', color: AppColors.warning, small: true),
            ),
          Text(
            '$pts pts',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Compact colour-coded label pill used throughout the report.
class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool small;
  const _Pill({required this.label, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(small ? 6 : 8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 11 : 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
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
