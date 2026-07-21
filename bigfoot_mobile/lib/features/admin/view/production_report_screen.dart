import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/user.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/admin_viewmodel.dart';
import 'production_report_pdf.dart';

/// Health Check report — formerly "Production Report". Period-over-period
/// throughput, sales (customer orders + open-stock sold), sold-vs-built per
/// model, plus a live department board with waiting + sold-not-started.
class ProductionReportScreen extends StatefulWidget {
  const ProductionReportScreen({super.key});

  @override
  State<ProductionReportScreen> createState() =>
      _ProductionReportScreenState();
}

class _ProductionReportScreenState extends State<ProductionReportScreen> {
  bool _loading = true;
  String? _error;
  HealthCheckReport? _report;
  HealthCheckPeriod _period = HealthCheckPeriod.weekly;
  DateTime _pivot = DateTime.now().toUtc();
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _load();
  }

  HealthCheckQuery _buildQuery() {
    if (_period == HealthCheckPeriod.custom) {
      return HealthCheckQuery(
        period: HealthCheckPeriod.custom,
        start: _customStart != null ? _iso(_customStart!) : null,
        end: _customEnd != null ? _iso(_customEnd!) : null,
      );
    }
    return HealthCheckQuery(period: _period, start: _iso(_pivot));
  }

  Future<void> _load() async {
    if (_period == HealthCheckPeriod.custom &&
        (_customStart == null || _customEnd == null)) {
      setState(() {
        _loading = false;
        _report = null;
        _error = null;
      });
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await context
          .read<AdminViewModel>()
          .getHealthCheckReport(_buildQuery());
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

  void _shiftPeriod(int direction) {
    if (_period == HealthCheckPeriod.custom) return;
    int days;
    switch (_period) {
      case HealthCheckPeriod.weekly:
        days = 7;
        break;
      case HealthCheckPeriod.biweekly:
        days = 14;
        break;
      case HealthCheckPeriod.monthly:
        days = 30;
        break;
      case HealthCheckPeriod.custom:
        return;
    }
    setState(() => _pivot = _pivot.add(Duration(days: direction * days)));
    _load();
  }

  void _selectPeriod(HealthCheckPeriod next) {
    if (next == _period) return;
    setState(() {
      _period = next;
      if (next != HealthCheckPeriod.custom) {
        _pivot = DateTime.now().toUtc();
      }
    });
    _load();
  }

  Future<void> _pickCustomRange() async {
    final initialStart = _customStart ?? DateTime.now().toUtc();
    final initialEnd = _customEnd ?? initialStart;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().toUtc().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (range == null) return;
    setState(() {
      _customStart =
          DateTime.utc(range.start.year, range.start.month, range.start.day);
      _customEnd =
          DateTime.utc(range.end.year, range.end.month, range.end.day);
    });
    _load();
  }

  Future<void> _downloadPdf() async {
    final report = _report;
    if (report == null) return;
    final doc = buildHealthCheckPdf(report);
    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'health-check-${report.window.start}-${report.window.end}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final canDownload = !_loading && _error == null && _report != null;
    final authState = context.watch<AuthViewModel>().state;
    // Cost matrix is financial config — full-admin tier only (owner + office).
    // Production_manager + QC see Health Check but can't edit the matrix.
    final canEditCostMatrix = authState is Authenticated &&
        (authState.user.role == UserRole.owner ||
            authState.user.role == UserRole.office);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Health Check'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            tooltip: 'Download as PDF',
            icon: const Icon(Icons.download_outlined),
            onPressed: canDownload ? _downloadPdf : null,
          ),
          if (canEditCostMatrix)
            IconButton(
              tooltip: 'Edit cost matrix',
              icon: const Icon(Icons.attach_money_outlined),
              onPressed: () =>
                  context.pushNamed(RouteNames.productionCostMatrix),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : _buildBody(canEditCostMatrix),
        ),
      ),
    );
  }

  Widget _buildBody(bool canEditCostMatrix) {
    final r = context.responsive;
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: r.pagePadding,
        vertical: 14,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: r.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PeriodSelector(
                  period: _period,
                  onSelect: _selectPeriod,
                ),
                const SizedBox(height: 10),
                if (_period == HealthCheckPeriod.custom)
                  _CustomRangePicker(
                    start: _customStart,
                    end: _customEnd,
                    onPick: _pickCustomRange,
                  )
                else
                  _WindowStepper(
                    window: _report?.window,
                    onPrev: () => _shiftPeriod(-1),
                    onNext: () => _shiftPeriod(1),
                  ),
                const SizedBox(height: 14),
                if (_report == null)
                  const _AwaitingRangeView()
                else
                  _Content(
                    report: _report!,
                    onCostMatrix: canEditCostMatrix
                        ? () => context.pushNamed(
                            RouteNames.productionCostMatrix)
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Period selector + window stepper
// ===========================================================================

class _PeriodSelector extends StatelessWidget {
  final HealthCheckPeriod period;
  final ValueChanged<HealthCheckPeriod> onSelect;
  const _PeriodSelector({required this.period, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    // On compact widths SegmentedButton can clip on 4 segments — switch to
    // a horizontally-scrollable chip row.
    if (r.isCompact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in HealthCheckPeriod.values) ...[
              ChoiceChip(
                label: Text(p.label),
                selected: p == period,
                onSelected: (_) => onSelect(p),
                selectedColor: AppColors.navy,
                labelStyle: TextStyle(
                  color: p == period ? AppColors.white : AppColors.navy,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: p == period
                        ? AppColors.navy
                        : AppColors.divider,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );
    }
    return Center(
      child: SegmentedButton<HealthCheckPeriod>(
        segments: [
          for (final p in HealthCheckPeriod.values)
            ButtonSegment(value: p, label: Text(p.label)),
        ],
        selected: {period},
        onSelectionChanged: (s) => onSelect(s.first),
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.navy,
          selectedForegroundColor: AppColors.white,
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
    );
  }
}

class _WindowStepper extends StatelessWidget {
  final HealthCheckWindow? window;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _WindowStepper({
    required this.window,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 0,
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous period',
              color: AppColors.navy,
            ),
            Expanded(
              child: Center(
                child: Text(
                  window == null
                      ? '—'
                      : '${_fmt(window!.start)}  →  ${_fmt(window!.end)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next period',
              color: AppColors.navy,
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomRangePicker extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPick;
  const _CustomRangePicker({
    required this.start,
    required this.end,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRange = start != null && end != null;
    return Material(
      elevation: 0,
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.date_range_outlined, color: AppColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasRange
                      ? '${_fmt(_iso(start!))}  →  ${_fmt(_iso(end!))}'
                      : 'Tap to pick a date range',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: hasRange ? AppColors.navy : AppColors.disabled,
                  ),
                ),
              ),
              const Icon(Icons.edit_calendar_outlined,
                  color: AppColors.disabled, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _AwaitingRangeView extends StatelessWidget {
  const _AwaitingRangeView();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.date_range_outlined,
                size: 48, color: AppColors.disabled),
            const SizedBox(height: 12),
            Text(
              'Choose a custom date range to load the report.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.disabled,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Content layout — fully responsive
// ===========================================================================

class _Content extends StatelessWidget {
  final HealthCheckReport report;
  final VoidCallback? onCostMatrix;
  const _Content({required this.report, required this.onCostMatrix});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;

    final hero = _HeroBanner(report: report);
    final throughputCard = _ThroughputCard(report: report);
    final salesCard = _SalesCard(report: report);
    final soldVsBuilt = _SoldVsBuiltCard(report: report);
    final deptBoard = _DepartmentBoardCard(live: report.live);
    final inventoryCard = _InventoryCard(live: report.live);
    final wipCard =
        _WipSection(wip: report.wipCost, onCostMatrix: onCostMatrix);

    // Layout strategy:
    // • compact / medium phones → single column
    // • expanded tablets → 2-column where it reads well
    // • large desktop → wider 2-col with hero spanning full width
    final useTwoCol = r.isExpanded || r.isLarge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hero,
        const SizedBox(height: 14),
        if (useTwoCol)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: throughputCard),
                const SizedBox(width: 14),
                Expanded(child: salesCard),
              ],
            ),
          )
        else ...[
          throughputCard,
          const SizedBox(height: 14),
          salesCard,
        ],
        const SizedBox(height: 14),
        soldVsBuilt,
        const SizedBox(height: 14),
        deptBoard,
        const SizedBox(height: 14),
        if (useTwoCol)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: inventoryCard),
                const SizedBox(width: 14),
                Expanded(child: wipCard),
              ],
            ),
          )
        else ...[
          inventoryCard,
          const SizedBox(height: 14),
          wipCard,
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

// ===========================================================================
// Hero banner — at-a-glance period summary
// ===========================================================================

class _HeroBanner extends StatelessWidget {
  final HealthCheckReport report;
  const _HeroBanner({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = context.responsive;
    final cur = report.current;
    final prev = report.previous;

    final highlights = <_HeroMetric>[
      _HeroMetric(
        label: 'Total sales',
        value: cur.sales.totalSales,
        previous: prev.sales.totalSales,
        icon: Icons.point_of_sale_outlined,
      ),
      _HeroMetric(
        label: 'Built',
        value: cur.soldVsBuilt.totalBuilt,
        previous: prev.soldVsBuilt.totalBuilt,
        icon: Icons.check_circle_outline,
      ),
      _HeroMetric(
        label: 'Delivered',
        value: cur.throughput.delivered,
        previous: prev.throughput.delivered,
        icon: Icons.local_shipping_outlined,
      ),
    ];

    final cols = r.value(compact: 1, medium: 3, expanded: 3, large: 3);
    final isSingleCol = cols == 1;

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.navy, Color(0xFF254A5E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.monitor_heart_outlined,
                      color: AppColors.amber, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${report.window.period?.label ?? 'Custom'} health check',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.amber,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${_fmt(report.window.start)} → ${_fmt(report.window.end)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'vs ${_fmt(report.previousWindow.start)} → ${_fmt(report.previousWindow.end)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (isSingleCol)
              Column(
                children: [
                  for (int i = 0; i < highlights.length; i++) ...[
                    _HeroMetricTile(metric: highlights[i]),
                    if (i < highlights.length - 1)
                      const SizedBox(height: 8),
                  ],
                ],
              )
            else
              Row(
                children: [
                  for (int i = 0; i < highlights.length; i++) ...[
                    Expanded(
                      child: _HeroMetricTile(metric: highlights[i]),
                    ),
                    if (i < highlights.length - 1)
                      const SizedBox(width: 10),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroMetric {
  final String label;
  final int value;
  final int previous;
  final IconData icon;
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.previous,
    required this.icon,
  });
}

class _HeroMetricTile extends StatelessWidget {
  final _HeroMetric metric;
  const _HeroMetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon,
                  color: AppColors.white.withValues(alpha: 0.85), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  metric.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.white.withValues(alpha: 0.7),
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${metric.value}',
                    maxLines: 1,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _DeltaChip(
                  value: metric.value,
                  previous: metric.previous,
                  invertColors: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Throughput & Sales — metric row cards
// ===========================================================================

class _ThroughputCard extends StatelessWidget {
  final HealthCheckReport report;
  const _ThroughputCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final cur = report.current.throughput;
    final prev = report.previous.throughput;
    return _SectionCard(
      title: 'Throughput',
      icon: Icons.trending_up,
      accent: AppColors.statusInProduction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MetricRow(
            label: 'Entered production',
            value: cur.enteredProduction,
            previous: prev.enteredProduction,
            color: AppColors.statusInProduction,
            icon: Icons.input,
          ),
          const _MetricDivider(),
          _MetricRow(
            label: 'Exited production',
            value: cur.exitedProduction,
            previous: prev.exitedProduction,
            color: AppColors.success,
            icon: Icons.check_circle_outline,
          ),
          const _MetricDivider(),
          _MetricRow(
            label: 'Delivered',
            value: cur.delivered,
            previous: prev.delivered,
            color: AppColors.amber,
            icon: Icons.local_shipping,
          ),
          if (cur.exitedBySeries.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: cur.exitedBySeries.entries
                  .map((e) => _SeriesPill(series: e.key, count: e.value))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SalesCard extends StatelessWidget {
  final HealthCheckReport report;
  const _SalesCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final cur = report.current.sales;
    final prev = report.previous.sales;
    return _SectionCard(
      title: 'Sales',
      icon: Icons.point_of_sale_outlined,
      accent: AppColors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MetricRow(
            label: 'Customer orders',
            value: cur.customerOrders,
            previous: prev.customerOrders,
            color: AppColors.navy,
            icon: Icons.assignment_ind_outlined,
            sublabel: 'New orders with a customer',
          ),
          const _MetricDivider(),
          _MetricRow(
            label: 'Open-stock orders placed',
            value: cur.stockOrdersPlaced,
            previous: prev.stockOrdersPlaced,
            color: AppColors.amber,
            icon: Icons.add_box_outlined,
            sublabel: 'Stock builds entered this period (no customer)',
          ),
          const _MetricDivider(),
          _MetricRow(
            label: 'Open-stock sold',
            value: cur.openStockSold,
            previous: prev.openStockSold,
            color: AppColors.seriesDeckOver,
            icon: Icons.inventory_2_outlined,
            sublabel: 'Stock builds sold this period',
          ),
          const _MetricDivider(),
          _MetricRow(
            label: '· out of production',
            value: cur.openStockSoldFromProduction,
            previous: prev.openStockSoldFromProduction,
            color: AppColors.statusInProduction,
            icon: Icons.precision_manufacturing_outlined,
            sublabel: 'Sold while still being built',
          ),
          const _MetricDivider(),
          _MetricRow(
            label: '· out of inventory',
            value: cur.openStockSoldFromInventory,
            previous: prev.openStockSoldFromInventory,
            color: AppColors.success,
            icon: Icons.warehouse_outlined,
            sublabel: 'Sold from finished stock',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Divider(color: AppColors.divider, thickness: 1.2),
          ),
          _MetricRow(
            label: 'Total sales',
            value: cur.totalSales,
            previous: prev.totalSales,
            color: AppColors.amber,
            icon: Icons.savings_outlined,
            emphasis: true,
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();
  @override
  Widget build(BuildContext context) => const Divider(
        color: AppColors.divider,
        height: 1,
        thickness: 1,
      );
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final int value;
  final int previous;
  final Color color;
  final IconData icon;
  final bool emphasis;
  const _MetricRow({
    required this.label,
    required this.value,
    required this.previous,
    required this.color,
    required this.icon,
    this.sublabel,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: emphasis ? 12 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: emphasis ? 44 : 38,
            height: emphasis ? 44 : 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: emphasis ? 22 : 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: (emphasis
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                    fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.disabled,
                    ),
                  ),
                const SizedBox(height: 2),
                _DeltaChip(value: value, previous: previous),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '$value',
                style: (emphasis
                        ? theme.textTheme.displaySmall
                        : theme.textTheme.headlineSmall)
                    ?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final int value;
  final int previous;
  /// True on dark backgrounds — uses lighter, higher-contrast tints.
  final bool invertColors;
  const _DeltaChip({
    required this.value,
    required this.previous,
    this.invertColors = false,
  });

  @override
  Widget build(BuildContext context) {
    final delta = value - previous;
    final pct = previous == 0
        ? (value == 0 ? 0 : 100)
        : ((delta / previous) * 100).round();

    IconData icon;
    Color color;
    String text;
    if (delta == 0) {
      icon = Icons.remove;
      color = invertColors
          ? AppColors.white.withValues(alpha: 0.6)
          : AppColors.disabled;
      text = 'no change';
    } else if (delta > 0) {
      icon = Icons.trending_up;
      color = invertColors ? const Color(0xFF7CE5A8) : AppColors.success;
      text = '+$delta · +$pct%';
    } else {
      icon = Icons.trending_down;
      color = invertColors ? const Color(0xFFFFA8A8) : AppColors.error;
      text = '$delta · $pct%';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: invertColors ? 0.18 : 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesPill extends StatelessWidget {
  final String series;
  final int count;
  const _SeriesPill({required this.series, required this.count});

  @override
  Widget build(BuildContext context) {
    final color = _colorForSeries(series);
    final label = _labelForSeries(series);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label · $count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Sold vs Built — totals + per-model table
// ===========================================================================

class _SoldVsBuiltCard extends StatelessWidget {
  final HealthCheckReport report;
  const _SoldVsBuiltCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final svb = report.current.soldVsBuilt;
    final prev = report.previous.soldVsBuilt;
    return _SectionCard(
      title: 'Sold vs Built',
      icon: Icons.compare_arrows,
      accent: AppColors.seriesXp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _TotalsBlock(
                  label: 'SOLD',
                  value: svb.totalSold,
                  previous: prev.totalSold,
                  color: AppColors.success,
                  icon: Icons.sell_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TotalsBlock(
                  label: 'BUILT',
                  value: svb.totalBuilt,
                  previous: prev.totalBuilt,
                  color: AppColors.statusInProduction,
                  icon: Icons.handyman_outlined,
                ),
              ),
            ],
          ),
          if (svb.perModel.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _MetricDivider(),
            const SizedBox(height: 12),
            Text(
              'BY MODEL',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.disabled,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            _SoldVsBuiltTable(rows: svb.perModel),
          ] else ...[
            const SizedBox(height: 12),
            _EmptyHint(
              icon: Icons.inbox_outlined,
              text: 'No model activity in this period.',
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalsBlock extends StatelessWidget {
  final String label;
  final int value;
  final int previous;
  final Color color;
  final IconData icon;
  const _TotalsBlock({
    required this.label,
    required this.value,
    required this.previous,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$value',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _DeltaChip(value: value, previous: previous),
        ],
      ),
    );
  }
}

class _SoldVsBuiltTable extends StatelessWidget {
  final List<HealthCheckModelLine> rows;
  const _SoldVsBuiltTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = context.responsive;
    if (r.isTablet) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: const [
                _Th('MODEL', flex: 4),
                _Th('SERIES', flex: 3),
                _Th('SOLD', flex: 2, align: TextAlign.right),
                _Th('BUILT', flex: 2, align: TextAlign.right),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          for (int i = 0; i < rows.length; i++)
            Container(
              decoration: BoxDecoration(
                color: i.isEven
                    ? AppColors.background.withValues(alpha: 0.5)
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      rows[i].modelCode,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SeriesPill(
                        series: rows[i].series,
                        count: rows[i].sold + rows[i].built,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${rows[i].sold}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${rows[i].built}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.statusInProduction,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    // Mobile: compact row per model
    return Column(
      children: rows
          .map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _SeriesPill(series: m.series, count: m.sold + m.built),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.modelCode,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  _LabeledNumber(
                    label: 'Sold',
                    value: m.sold,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 12),
                  _LabeledNumber(
                    label: 'Built',
                    value: m.built,
                    color: AppColors.statusInProduction,
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _LabeledNumber extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _LabeledNumber(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.disabled,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        Text(
          '$value',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Department board — responsive tile grid
// ===========================================================================

class _DepartmentBoardCard extends StatelessWidget {
  final HealthCheckLive live;
  const _DepartmentBoardCard({required this.live});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final cols = r.gridColumns(compact: 2, medium: 3, expanded: 4, large: 5);
    final totalWaiting =
        live.departments.fold<int>(0, (s, d) => s + d.waiting);
    final totalSoldHere =
        live.departments.fold<int>(0, (s, d) => s + d.soldHere);

    // Slightly taller tiles on narrow phones so two numbers + label fit.
    final aspect = r.isSmallPhone
        ? 1.0
        : r.value(compact: 1.1, medium: 1.2, expanded: 1.25, large: 1.3);

    return _SectionCard(
      title: 'Department board',
      icon: Icons.dashboard_customize_outlined,
      accent: AppColors.seriesGooseneck,
      headerTrailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _SummaryPill(
            label: 'Waiting',
            value: totalWaiting,
            color: AppColors.navy,
          ),
          _SummaryPill(
            label: 'Sold in build',
            value: totalSoldHere,
            color: AppColors.amber,
          ),
        ],
      ),
      child: live.departments.isEmpty
          ? _EmptyHint(
              icon: Icons.layers_clear_outlined,
              text: 'No departments configured yet.',
            )
          : GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: live.departments.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: aspect,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemBuilder: (_, i) => _DeptTile(tile: live.departments[i]),
            ),
    );
  }
}

class _DeptTile extends StatelessWidget {
  final HealthCheckDeptTile tile;
  const _DeptTile({required this.tile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _colorForDept(tile.code);
    final hasSold = tile.soldHere > 0;

    return Material(
      elevation: 0,
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Stack(
          children: [
            // Left accent stripe — matches StatCard convention.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tile.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                      height: 1.2,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${tile.waiting}',
                            maxLines: 1,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accent,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 4),
                        child: Text(
                          'waiting',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.disabled,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (hasSold
                              ? AppColors.amber
                              : AppColors.disabled)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasSold
                              ? Icons.local_fire_department_outlined
                              : Icons.check_outlined,
                          size: 12,
                          color:
                              hasSold ? AppColors.amber : AppColors.disabled,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            hasSold
                                ? '${tile.soldHere} sold here'
                                : 'No sold here',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: hasSold
                                  ? AppColors.amber
                                  : AppColors.disabled,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Inventory / Live snapshot
// ===========================================================================

class _InventoryCard extends StatelessWidget {
  final HealthCheckLive live;
  const _InventoryCard({required this.live});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Live snapshot',
      icon: Icons.radar,
      accent: AppColors.statusDelivered,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SnapshotTile(
                  label: 'In production',
                  value: live.inProduction,
                  color: AppColors.statusInProduction,
                  icon: Icons.precision_manufacturing,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SnapshotTile(
                  label: 'Ready for delivery',
                  value: live.readyForDelivery,
                  color: AppColors.statusReady,
                  icon: Icons.outbox,
                ),
              ),
            ],
          ),
          if (live.inventoryByYard.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'INVENTORY BY YARD',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.disabled,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: live.inventoryByYard
                  .map(
                    (y) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 14, color: AppColors.disabled),
                          const SizedBox(width: 4),
                          Text(
                            y.code,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.navy,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${y.count}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  const _SnapshotTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$value',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.disabled,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// WIP cost section
// ===========================================================================

class _WipSection extends StatelessWidget {
  final ProductionWipCost wip;
  final VoidCallback? onCostMatrix;
  const _WipSection({required this.wip, required this.onCostMatrix});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = context.responsive;
    final matrixIsEmpty = wip.totalProjectedDollars == 0;
    final progress = matrixIsEmpty
        ? 0.0
        : (wip.totalCumulativeDollars / wip.totalProjectedDollars)
            .clamp(0.0, 1.0)
            .toDouble();

    if (matrixIsEmpty) {
      final cta = onCostMatrix;
      return _SectionCard(
        title: 'Work-in-progress cost',
        icon: Icons.savings_outlined,
        accent: AppColors.amber,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cta == null
                  ? 'Cost matrix not configured'
                  : 'No cost matrix configured yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              cta == null
                  ? 'Ask the owner to set up the (trailer model × department) '
                      'cost matrix and this section will start showing invested '
                      'vs projected cost.'
                  : 'Set an approximate dollar value for each (trailer model × '
                      'department) cell and this section will show invested vs '
                      'projected cost across the ${wip.perTrailer.length} '
                      'trailer${wip.perTrailer.length == 1 ? '' : 's'} '
                      'currently in production.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.disabled,
                height: 1.4,
              ),
            ),
            if (cta != null) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: cta,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Open cost matrix'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: AppColors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final pct =
        ((wip.totalCumulativeDollars / wip.totalProjectedDollars) * 100)
            .round();
    final pctColor = pct >= 80
        ? AppColors.success
        : (pct >= 40 ? AppColors.amber : AppColors.disabled);

    return _SectionCard(
      title: 'Work-in-progress cost',
      icon: Icons.savings_outlined,
      accent: AppColors.amber,
      headerTrailing: onCostMatrix != null
          ? TextButton.icon(
              onPressed: onCostMatrix,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit matrix'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.navy,
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INVESTED',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.disabled,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _money(wip.totalCumulativeDollars),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'of projected ${_money(wip.totalProjectedDollars)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.disabled,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: pctColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: pctColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$pct% utilised',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: pctColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(pctColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Across ${wip.perTrailer.length} in-production trailer'
            '${wip.perTrailer.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.disabled,
            ),
          ),
          if (wip.perTrailer.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _MetricDivider(),
            const SizedBox(height: 10),
            if (r.isTablet)
              _WipTable(rows: wip.perTrailer.take(20).toList())
            else
              Column(
                children: wip.perTrailer.take(20).map(_compactRow).toList(),
              ),
            if (wip.perTrailer.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '… +${wip.perTrailer.length - 20} more',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.disabled,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _compactRow(ProductionWipTrailer t) => Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    t.soNumber,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.modelCode,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                Text(
                  '${_money(t.cumulativeDollars)} / ${_money(t.projectedDollars)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.disabled,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _WipTable extends StatelessWidget {
  final List<ProductionWipTrailer> rows;
  const _WipTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: const [
              _Th('SO', flex: 2),
              _Th('MODEL', flex: 3),
              _Th('INVESTED', flex: 2, align: TextAlign.right),
              _Th('PROJECTED', flex: 2, align: TextAlign.right),
              _Th('%', flex: 1, align: TextAlign.right),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        for (int i = 0; i < rows.length; i++) ...[
          () {
            final t = rows[i];
            final pct = t.projectedDollars == 0
                ? 0
                : ((t.cumulativeDollars / t.projectedDollars) * 100).round();
            final pctColor = pct >= 80
                ? AppColors.success
                : (pct >= 40 ? AppColors.amber : AppColors.disabled);
            return Container(
              decoration: BoxDecoration(
                color: i.isEven
                    ? AppColors.background.withValues(alpha: 0.5)
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      t.soNumber,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      t.modelCode,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.disabled,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _money(t.cumulativeDollars),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _money(t.projectedDollars),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.disabled,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '$pct%',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: pctColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }(),
        ],
      ],
    );
  }
}

// ===========================================================================
// Shared scaffolding
// ===========================================================================

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;
  final Widget? headerTrailing;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (headerTrailing != null) headerTrailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$value',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AppColors.disabled),
            const SizedBox(height: 8),
            Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.disabled,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Th extends StatelessWidget {
  final String label;
  final int flex;
  final TextAlign align;
  const _Th(this.label, {this.flex = 1, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.disabled,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
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
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.error_outline,
                      size: 32, color: AppColors.error),
                ),
                const SizedBox(height: 14),
                Text(
                  'Could not load the Health Check report',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.disabled,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: AppColors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Helpers
// ===========================================================================

Color _colorForSeries(String series) {
  switch (series) {
    case 'xp':
      return AppColors.seriesXp;
    case 'yeti':
      return AppColors.seriesYeti;
    case 'deck_over':
      return AppColors.seriesDeckOver;
    case 'gooseneck_dump':
      return AppColors.seriesGooseneck;
    case 'gooseneck_yeti':
      return AppColors.seriesGooseneckYeti;
    case 'inventory':
      return AppColors.seriesInventory;
    default:
      return AppColors.navy;
  }
}

String _labelForSeries(String series) {
  switch (series) {
    case 'xp':
      return 'XP';
    case 'yeti':
      return 'YETI';
    case 'deck_over':
      return 'DECK OVER';
    case 'gooseneck_dump':
      return 'GOOSENECK';
    case 'gooseneck_yeti':
      return 'GN YETI';
    case 'inventory':
      return 'INVENTORY';
    default:
      return series.toUpperCase();
  }
}

Color _colorForDept(String code) {
  // Tie dept tiles to the series palette so the board reads as
  // "blue cluster = XP, purple = Yeti, green = Deck Over, orange = Gooseneck,
  // amber = paint, navy = wire/wood/hydraulics".
  if (code.startsWith('XP_')) return AppColors.seriesXp;
  if (code.startsWith('YETI_')) return AppColors.seriesYeti;
  if (code.startsWith('DO_')) return AppColors.seriesDeckOver;
  if (code.startsWith('GN_')) return AppColors.seriesGooseneck;
  if (code.startsWith('PAINT')) return AppColors.amber;
  switch (code) {
    case 'WIRE':
      return AppColors.statusInProduction;
    case 'WOOD':
      return AppColors.seriesInventory;
    case 'HYDRAULICS':
      return AppColors.navy;
    default:
      return AppColors.navy;
  }
}

String _iso(DateTime d) => d.toIso8601String().split('T').first;

String _fmt(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (m == null || d == null || m < 1 || m > 12) return iso;
  return '${months[m - 1]} $d';
}

String _money(double v) {
  if (v == 0) return r'$0';
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
