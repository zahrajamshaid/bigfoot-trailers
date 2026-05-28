import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../viewmodel/admin_viewmodel.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  DateTime _weekStart = _currentSunday();
  AdminWeeklyProductionReport? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static DateTime _currentSunday() {
    final now = DateTime.now();
    final day = now.weekday % 7;
    return DateTime(now.year, now.month, now.day).subtract(Duration(days: day));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final report = await context
          .read<AdminViewModel>()
          .getWeeklyProductionReport(_weekStart.toIso8601String().split('T').first);
      if (!mounted) return;
      setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).adminNavReports),
        actions: [
          IconButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDate: _weekStart,
              );
              if (picked == null) return;
              final normalized =
                  DateTime(picked.year, picked.month, picked.day - (picked.weekday % 7));
              setState(() => _weekStart = normalized);
              _load();
            },
            icon: const Icon(Icons.date_range),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : r == null
              ? Center(child: Text(AppLocalizations.of(context).adminReportsNoReport))
              : Builder(builder: (context) {
                  final l = AppLocalizations.of(context);
                  return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _MetricCard(
                      title: l.adminReportWeeklySteps,
                      value: '${r.totalStepsCompleted}',
                    ),
                    _MetricCard(
                      title: l.adminReportWeeklyPoints,
                      value: r.totalPoints.toStringAsFixed(1),
                    ),
                    _MetricCard(
                      title: l.adminReportQcFailTrend,
                      value: l.adminReportNotAvailable,
                    ),
                    _MetricCard(
                      title: l.adminReportAvgTimePerStep,
                      value: l.adminReportNotAvailable,
                    ),
                    _MetricCard(
                      title: l.adminReportStalledTrailers,
                      value: l.adminReportUseProdDashboard,
                    ),
                    const SizedBox(height: 8),
                    Text(l.adminReportWorkerSummary,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    ...r.workerSummary.map((w) => Card(
                          child: ListTile(
                            title: Text(w['workerName']?.toString() ?? l.commonUnknown),
                            subtitle: Text(l.adminReportRoleValue('${w['role'] ?? '-'}')),
                            trailing: Text(
                              l.adminReportStepsPtsLine(
                                '${w['stepsCompleted'] ?? 0}',
                                '${w['totalPoints'] ?? 0}',
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        )),
                  ],
                  );
                }),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const _MetricCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: AppColors.disabled)),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
