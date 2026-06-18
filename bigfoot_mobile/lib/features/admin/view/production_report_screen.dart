import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../viewmodel/admin_viewmodel.dart';

/// Weekly trailer-throughput dashboard. Different from the Payroll Weekly
/// Report (which is about worker output) — this one is about trailers
/// entering/exiting production, deliveries, current inventory, and a
/// rough WIP cost summary driven by the cost matrix.
class ProductionReportScreen extends StatefulWidget {
  const ProductionReportScreen({super.key});

  @override
  State<ProductionReportScreen> createState() =>
      _ProductionReportScreenState();
}

class _ProductionReportScreenState extends State<ProductionReportScreen> {
  bool _loading = true;
  String? _error;
  ProductionReport? _report;
  DateTime _weekStart = _currentWeekSunday();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final iso = _weekStart.toIso8601String().split('T').first;
      final r =
          await context.read<AdminViewModel>().getProductionReport(iso);
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _shiftWeek(int days) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: days));
    });
    _load();
  }

  bool get _isCurrentWeek =>
      _weekStart.toUtc().difference(_currentWeekSunday().toUtc()).inDays == 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Production report'),
        actions: [
          IconButton(
            tooltip: 'Edit cost matrix',
            icon: const Icon(Icons.attach_money_outlined),
            onPressed: () => context.goNamed(RouteNames.productionCostMatrix),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _Content(
                  report: _report!,
                  weekStart: _weekStart,
                  onPrev: () => _shiftWeek(-7),
                  onNext: _isCurrentWeek ? null : () => _shiftWeek(7),
                  onCostMatrix: () =>
                      context.goNamed(RouteNames.productionCostMatrix),
                ),
    );
  }
}

class _Content extends StatelessWidget {
  final ProductionReport report;
  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onCostMatrix;

  const _Content({
    required this.report,
    required this.weekStart,
    required this.onPrev,
    required this.onNext,
    required this.onCostMatrix,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        // The actual refresh is owned by the parent; here we only need the
        // pull gesture to feel right while the page is scrollable.
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WeekPicker(weekStart: weekStart, onPrev: onPrev, onNext: onNext),
          const SizedBox(height: 12),
          _SectionTitle('This week'),
          _StatGrid(
            tiles: [
              _Tile(
                label: 'Entered production',
                value: '${report.throughput.enteredProduction}',
                icon: Icons.input,
                color: AppColors.navy,
              ),
              _Tile(
                label: 'Exited production',
                value: '${report.throughput.exitedProduction}',
                icon: Icons.check_circle_outline,
                color: AppColors.success,
              ),
              _Tile(
                label: 'Delivered',
                value: '${report.throughput.delivered}',
                icon: Icons.local_shipping,
                color: AppColors.amber,
              ),
            ],
          ),
          if (report.throughput.exitedBySeries.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Exited by series: ${report.throughput.exitedBySeries.entries.map((e) => '${e.key} ${e.value}').join(' · ')}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.disabled),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _SectionTitle('Live snapshot'),
          _StatGrid(
            tiles: [
              _Tile(
                label: 'In production',
                value: '${report.snapshot.inProduction}',
                icon: Icons.precision_manufacturing,
                color: AppColors.statusInProduction,
              ),
              _Tile(
                label: 'Ready for delivery',
                value: '${report.snapshot.readyForDelivery}',
                icon: Icons.outbox,
                color: AppColors.statusReady,
              ),
            ],
          ),
          if (report.snapshot.inventoryByYard.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Inventory by yard',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: report.snapshot.inventoryByYard
                        .map(
                          (y) => Chip(
                            label: Text('${y.code} · ${y.count}'),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          _WipSection(wip: report.wipCost, onCostMatrix: onCostMatrix),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _WeekPicker extends StatelessWidget {
  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _WeekPicker({
    required this.weekStart,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final end = weekStart.add(const Duration(days: 6));
    String fmt(DateTime d) =>
        '${_short(d.month)} ${d.day}';
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous week',
        ),
        Expanded(
          child: Center(
            child: Text(
              '${fmt(weekStart)} — ${fmt(end)}, ${weekStart.year}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next week',
        ),
      ],
    );
  }

  static String _short(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m - 1];
  }
}

class _StatGrid extends StatelessWidget {
  final List<_Tile> tiles;
  const _StatGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: tiles.length >= 3 ? 3 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.5,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: tiles,
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Tile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.disabled),
          ),
        ],
      ),
    );
  }
}

class _WipSection extends StatelessWidget {
  final ProductionWipCost wip;
  final VoidCallback onCostMatrix;
  const _WipSection({required this.wip, required this.onCostMatrix});

  @override
  Widget build(BuildContext context) {
    final progress = wip.totalProjectedDollars == 0
        ? 0.0
        : (wip.totalCumulativeDollars / wip.totalProjectedDollars)
            .clamp(0.0, 1.0)
            .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle('Work-in-progress cost')),
            TextButton.icon(
              onPressed: onCostMatrix,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit matrix'),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Invested ${_money(wip.totalCumulativeDollars)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    'Projected ${_money(wip.totalProjectedDollars)}',
                    style: const TextStyle(
                        color: AppColors.disabled, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(AppColors.amber),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Across ${wip.perTrailer.length} in-production trailer'
                '${wip.perTrailer.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.disabled),
              ),
            ],
          ),
        ),
        if (wip.perTrailer.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...wip.perTrailer.take(20).map(
                (t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t.soNumber} · ${t.modelCode}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${_money(t.cumulativeDollars)} / ${_money(t.projectedDollars)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          if (wip.perTrailer.length > 20)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '... +${wip.perTrailer.length - 20} more',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.disabled),
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.disabled,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Last-Sunday-00:00-UTC of the current week. Matches the backend's window.
DateTime _currentWeekSunday() {
  final now = DateTime.now().toUtc();
  final dow = now.weekday % 7; // Sun=0 … Sat=6
  return DateTime.utc(now.year, now.month, now.day - dow);
}

String _money(double v) {
  if (v == 0) return r'$0';
  // Thousands separator for readability without pulling in intl. Two-decimal
  // for sub-$10 values so the floor's $X.YY cells still show their cents.
  final cents = (v.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final frac = (cents % 100).toString().padLeft(2, '0');
  final withSeparators = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) {
      withSeparators.write(',');
    }
    withSeparators.write(whole[i]);
  }
  return frac == '00'
      ? '\$$withSeparators'
      : '\$$withSeparators.$frac';
}
