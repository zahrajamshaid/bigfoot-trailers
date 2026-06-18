import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../viewmodel/admin_viewmodel.dart';

/// Renders the [ProductionReport] into a printable PDF document. Layout
/// mirrors the on-screen card structure (header, throughput, snapshot +
/// inventory, WIP totals, per-trailer table) but uses static print
/// styling — no interactivity, fixed dimensions, table breaks across
/// pages cleanly.
///
/// Returns the raw bytes so the caller can hand them to `Printing.layoutPdf`
/// (system print/save dialog) or write them to a temp file for share_plus.
pw.Document buildProductionReportPdf(ProductionReport report) {
  final doc = pw.Document(
    title: 'Production Report — Week of ${report.weekStart}',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
      header: (ctx) => _header(report),
      footer: (ctx) => _footer(ctx),
      build: (ctx) => [
        pw.SizedBox(height: 10),
        _statRow('This week', [
          _Stat('Entered production', report.throughput.enteredProduction),
          _Stat('Exited production', report.throughput.exitedProduction),
          _Stat('Delivered', report.throughput.delivered),
        ]),
        if (report.throughput.exitedBySeries.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Exited by series: ${report.throughput.exitedBySeries.entries.map((e) => '${e.key} ${e.value}').join(' · ')}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 18),
        _statRow('Live snapshot', [
          _Stat('In production', report.snapshot.inProduction),
          _Stat('Ready for delivery', report.snapshot.readyForDelivery),
        ]),
        if (report.snapshot.inventoryByYard.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('Inventory by yard',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 8,
            runSpacing: 6,
            children: report.snapshot.inventoryByYard
                .map((y) => _chip('${y.code} · ${y.count}'))
                .toList(),
          ),
        ],
        pw.SizedBox(height: 22),
        _wipSummary(report.wipCost),
        if (report.wipCost.perTrailer.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _wipTable(report.wipCost.perTrailer),
        ],
      ],
    ),
  );

  return doc;
}

// ── Header / footer ─────────────────────────────────────────────────────────

pw.Widget _header(ProductionReport report) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Production Report',
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Text('Bigfoot Trailers',
                style: const pw.TextStyle(
                    fontSize: 12, color: PdfColors.grey600)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Week of ${report.weekStart} → ${report.weekEnd}',
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

// ── Stats grid ──────────────────────────────────────────────────────────────

pw.Widget _statRow(String title, List<_Stat> stats) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title.toUpperCase(),
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
                color: PdfColors.grey600)),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            for (final s in stats) ...[
              pw.Expanded(child: _statCard(s)),
              if (s != stats.last) pw.SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );

pw.Widget _statCard(_Stat s) => pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${s.value}',
            style: pw.TextStyle(
                fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            s.label,
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey600),
          ),
        ],
      ),
    );

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
  final pct = wip.totalProjectedDollars == 0
      ? 0
      : ((wip.totalCumulativeDollars / wip.totalProjectedDollars) * 100).round();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('WORK-IN-PROGRESS COST',
          style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.6,
              color: PdfColors.grey600)),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
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
                          : (pct >= 40
                              ? PdfColors.amber700
                              : PdfColors.grey600)),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Across ${wip.perTrailer.length} in-production trailer'
              '${wip.perTrailer.length == 1 ? '' : 's'}',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    ],
  );
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
            _td(
              t.soNumber,
              pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
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

// ── Local helpers ───────────────────────────────────────────────────────────

class _Stat {
  final String label;
  final int value;
  _Stat(this.label, this.value);
}

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
