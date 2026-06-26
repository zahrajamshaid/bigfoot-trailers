import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../domain/repositories/admin_repository.dart';

/// Renders a Health Check report into a printable PDF. Layout follows the
/// on-screen sections — period header, throughput + sales side by side,
/// sold-vs-built grid, department board, and WIP cost summary + per-trailer
/// table — but uses static print styling and fixed dimensions so multi-page
/// breaks happen cleanly.
///
/// String literals use plain ASCII arrows (->) instead of the unicode →
/// glyph so the default Helvetica fallback can draw them — pdf otherwise
/// silently drops the glyph and logs "Unable to find a font to draw" on every
/// render.
pw.Document buildHealthCheckPdf(HealthCheckReport report) {
  final periodLabel = report.window.period?.label ?? 'Custom';
  final doc = pw.Document(
    title:
        'Health Check - $periodLabel ${report.window.start} to ${report.window.end}',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
      header: (ctx) => _header(report, periodLabel),
      footer: (ctx) => _footer(ctx),
      build: (ctx) => [
        pw.SizedBox(height: 10),
        _throughputAndSales(report),
        pw.SizedBox(height: 18),
        _soldVsBuilt(report),
        pw.SizedBox(height: 18),
        _departmentBoard(report.live),
        pw.SizedBox(height: 18),
        _liveSnapshot(report.live),
        pw.SizedBox(height: 22),
        _wipSummary(report.wipCost),
        if (report.wipCost.perTrailer.isNotEmpty &&
            report.wipCost.totalProjectedDollars > 0) ...[
          pw.SizedBox(height: 10),
          _wipTable(report.wipCost.perTrailer),
        ],
      ],
    ),
  );

  return doc;
}

// ── Header / footer ─────────────────────────────────────────────────────────

pw.Widget _header(HealthCheckReport report, String periodLabel) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Health Check',
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Text('Bigfoot Trailers',
                style: const pw.TextStyle(
                    fontSize: 12, color: PdfColors.grey600)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '$periodLabel  |  ${report.window.start} to ${report.window.end}'
          '  |  vs prior ${report.previousWindow.start} to ${report.previousWindow.end}',
          style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 0.6, color: PdfColors.grey400),
      ],
    );

pw.Widget _footer(pw.Context ctx) => pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Generated ${DateTime.now().toUtc().toIso8601String().split('.').first}Z · Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
      ),
    );

// ── Throughput + Sales side by side ─────────────────────────────────────────

pw.Widget _throughputAndSales(HealthCheckReport r) {
  final cur = r.current;
  final prev = r.previous;
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _sectionBox('THIS PERIOD', [
          _deltaRow('Entered production', cur.throughput.enteredProduction,
              prev.throughput.enteredProduction),
          _deltaRow('Exited production', cur.throughput.exitedProduction,
              prev.throughput.exitedProduction),
          _deltaRow('Delivered', cur.throughput.delivered,
              prev.throughput.delivered),
          if (cur.throughput.exitedBySeries.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Exited by series: ${cur.throughput.exitedBySeries.entries.map((e) => '${e.key} ${e.value}').join(' · ')}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ]),
      ),
      pw.SizedBox(width: 10),
      pw.Expanded(
        child: _sectionBox('SALES', [
          _deltaRow('Customer orders', cur.sales.customerOrders,
              prev.sales.customerOrders),
          _deltaRow('Open-stock sold', cur.sales.openStockSold,
              prev.sales.openStockSold),
          pw.Divider(thickness: 0.5, color: PdfColors.grey300),
          _deltaRow('Total sales', cur.sales.totalSales,
              prev.sales.totalSales,
              emphasis: true),
        ]),
      ),
    ],
  );
}

pw.Widget _sectionBox(String title, List<pw.Widget> children) => pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.6,
                  color: PdfColors.grey600)),
          pw.SizedBox(height: 8),
          ...children,
        ],
      ),
    );

pw.Widget _deltaRow(String label, int value, int previous,
    {bool emphasis = false}) {
  final delta = value - previous;
  final pct = previous == 0
      ? (value == 0 ? 0 : 100)
      : ((delta / previous) * 100).round();
  final deltaText = delta == 0
      ? 'no change'
      : '${delta > 0 ? '+' : ''}$delta (${delta > 0 ? '+' : ''}$pct%)';
  final deltaColor = delta == 0
      ? PdfColors.grey600
      : (delta > 0 ? PdfColors.green700 : PdfColors.red700);
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: emphasis ? 12 : 11,
                      fontWeight: emphasis
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal)),
              pw.Text('vs $previous prior · $deltaText',
                  style: pw.TextStyle(fontSize: 9, color: deltaColor)),
            ],
          ),
        ),
        pw.Text('$value',
            style: pw.TextStyle(
                fontSize: emphasis ? 20 : 16,
                fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

// ── Sold vs Built ───────────────────────────────────────────────────────────

pw.Widget _soldVsBuilt(HealthCheckReport r) {
  final svb = r.current.soldVsBuilt;
  if (svb.perModel.isEmpty) {
    return _sectionBox('SOLD VS BUILT', [
      pw.Text('No model activity in this period.',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
    ]);
  }
  final headerStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey700,
      letterSpacing: 0.4);
  return _sectionBox('SOLD VS BUILT', [
    pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text('Sold ${svb.totalSold}',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green800)),
        ),
        pw.Expanded(
          child: pw.Text('Built ${svb.totalBuilt}',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800)),
        ),
      ],
    ),
    pw.SizedBox(height: 8),
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _td('Model', headerStyle),
            _td('Series', headerStyle),
            _td('Sold', headerStyle, align: pw.TextAlign.right),
            _td('Built', headerStyle, align: pw.TextAlign.right),
          ],
        ),
        ...svb.perModel.map(
          (m) => pw.TableRow(children: [
            _td(m.modelCode,
                pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            _td(m.series, const pw.TextStyle(fontSize: 10)),
            _td('${m.sold}',
                pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                align: pw.TextAlign.right),
            _td('${m.built}',
                pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                align: pw.TextAlign.right),
          ]),
        ),
      ],
    ),
  ]);
}

// ── Department board ───────────────────────────────────────────────────────

pw.Widget _departmentBoard(HealthCheckLive live) {
  if (live.departments.isEmpty) {
    return _sectionBox('DEPARTMENT BOARD', [
      pw.Text('No departments configured.',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
    ]);
  }
  final totalWaiting =
      live.departments.fold<int>(0, (s, d) => s + d.waiting);
  final totalSold =
      live.departments.fold<int>(0, (s, d) => s + d.soldHere);
  // Render as a flat Table — pw.GridView can't paginate (a too-tall page
  // throws TooManyPagesException), but Table rows break across pages cleanly.
  final headerStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey700,
      letterSpacing: 0.4);
  return _sectionBox('DEPARTMENT BOARD', [
    pw.Text(
        'Total waiting $totalWaiting  |  sold in build $totalSold',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    pw.SizedBox(height: 6),
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _td('Department', headerStyle),
            _td('Waiting', headerStyle, align: pw.TextAlign.right),
            _td('Sold here', headerStyle, align: pw.TextAlign.right),
          ],
        ),
        ...live.departments.map(
          (d) => pw.TableRow(children: [
            _td(d.displayName,
                pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            _td('${d.waiting}',
                pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                align: pw.TextAlign.right),
            _td(
              d.soldHere == 0 ? '-' : '${d.soldHere}',
              pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: d.soldHere == 0
                    ? PdfColors.grey500
                    : PdfColors.amber800,
              ),
              align: pw.TextAlign.right,
            ),
          ]),
        ),
      ],
    ),
  ]);
}

// ── Live snapshot ───────────────────────────────────────────────────────────

pw.Widget _liveSnapshot(HealthCheckLive live) => _sectionBox('LIVE SNAPSHOT', [
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text('In production: ${live.inProduction}',
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Text('Ready for delivery: ${live.readyForDelivery}',
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
      if (live.inventoryByYard.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        pw.Text('Inventory by yard',
            style:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Wrap(
          spacing: 6,
          runSpacing: 4,
          children: live.inventoryByYard
              .map((y) => _chip('${y.code} · ${y.count}'))
              .toList(),
        ),
      ],
    ]);

pw.Widget _chip(String text) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
    );

// ── WIP cost ────────────────────────────────────────────────────────────────

pw.Widget _wipSummary(ProductionWipCost wip) {
  if (wip.totalProjectedDollars == 0) {
    return _sectionBox('WORK-IN-PROGRESS COST', [
      pw.Text('No cost matrix configured yet.',
          style:
              pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text(
        'Set per-stage dollar values in the admin cost matrix to populate this section.',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
      ),
    ]);
  }

  final pct =
      ((wip.totalCumulativeDollars / wip.totalProjectedDollars) * 100)
          .round();
  return _sectionBox('WORK-IN-PROGRESS COST', [
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: 'Invested ${_money(wip.totalCumulativeDollars)}',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.TextSpan(
                text:
                    '  of projected ${_money(wip.totalProjectedDollars)}',
                style: const pw.TextStyle(
                    fontSize: 11, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        pw.Text(
          '$pct% utilised',
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: pct >= 80
                  ? PdfColors.green700
                  : (pct >= 40 ? PdfColors.amber700 : PdfColors.grey600)),
        ),
      ],
    ),
    pw.SizedBox(height: 6),
    pw.Text(
      'Across ${wip.perTrailer.length} in-production trailer'
      '${wip.perTrailer.length == 1 ? '' : 's'}',
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
    ),
  ]);
}

pw.Widget _wipTable(List<ProductionWipTrailer> rows) {
  final headerStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey700,
      letterSpacing: 0.4);
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.4),
    columnWidths: const {
      0: pw.FlexColumnWidth(2),
      1: pw.FlexColumnWidth(3),
      2: pw.FlexColumnWidth(2),
      3: pw.FlexColumnWidth(2),
      4: pw.FlexColumnWidth(1.4),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          _td('SO', headerStyle),
          _td('Model', headerStyle),
          _td('Invested', headerStyle, align: pw.TextAlign.right),
          _td('Projected', headerStyle, align: pw.TextAlign.right),
          _td('Progress', headerStyle, align: pw.TextAlign.right),
        ],
      ),
      ...rows.map((t) {
        final pct = t.projectedDollars == 0
            ? 0
            : ((t.cumulativeDollars / t.projectedDollars) * 100).round();
        return pw.TableRow(
          children: [
            _td(t.soNumber,
                pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            _td(t.modelCode, const pw.TextStyle(fontSize: 10)),
            _td(_money(t.cumulativeDollars),
                const pw.TextStyle(fontSize: 10),
                align: pw.TextAlign.right),
            _td(_money(t.projectedDollars),
                const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                align: pw.TextAlign.right),
            _td('$pct%',
                pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: pct >= 80
                      ? PdfColors.green700
                      : (pct >= 40
                          ? PdfColors.amber700
                          : PdfColors.grey600),
                ),
                align: pw.TextAlign.right),
          ],
        );
      }),
    ],
  );
}

pw.Widget _td(String text, pw.TextStyle style,
        {pw.TextAlign align = pw.TextAlign.left}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(text, style: style, textAlign: align),
    );

String _money(double v) {
  if (v == 0) return r'$0';
  final cents = (v.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final frac = (cents % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return frac == '00' ? '\$$buf' : '\$$buf.$frac';
}
