import { Injectable } from '@nestjs/common';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { QboApiClient, QboCompanyHeader } from '../quickbooks/qbo-api.client';

// pdfkit is a CommonJS module (module.exports = PDFDocument) with no ESM
// default export, so import-equals is the reliable form under our tsconfig.
import PDFDocument = require('pdfkit');

/** One printed row. `rate`/`amount` are only rendered on the priced document. */
interface SlipRow {
  service: string;
  description: string;
  qty: number;
  rate: number;
  amount: number;
}

/**
 * Generates the Sales Order **packing slip** — the work-order document with
 * ALL dollar values stripped (the floor/jig copy). QuickBooks Online has no
 * packing-slip API (it's a UI-only batch print), so per Intuit's own
 * recommendation we render it from the Sales Order lines. Layout mirrors the
 * QBO "Print packing slip": PACKING SLIP header, company block, Bill-to,
 * Sales Order details (no. + date), then a SERVICE / DESCRIPTION / QTY table.
 */
@Injectable()
export class PackingSlipService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly qbo: QboApiClient,
  ) {}

  /**
   * Build the document for a Sales Order.
   *
   * `withPrices: false` (default) → the WORK ORDER / packing slip: identical
   * layout with every dollar amount stripped — what the floor and jig see.
   * `withPrices: true` → the SALES ORDER: same document, plus RATE / AMOUNT
   * columns and the totals block. Same generator on purpose, so the two can
   * never drift apart in layout.
   */
  async generate(
    soId: bigint,
    opts: { withPrices?: boolean } = {},
  ): Promise<{ pdf: Buffer; soNumber: string }> {
    const withPrices = opts.withPrices ?? false;
    const so = await this.prisma.salesOrder.findUnique({
      where: { id: soId },
      include: {
        lines: { orderBy: { sortOrder: 'asc' } },
        customer: {
          select: {
            name: true,
            company: true,
            billingAddress: true,
            deliveryAddress: true,
          },
        },
      },
    });
    if (!so) throw new AppError(ErrorCode.NOT_FOUND, `Sales order ${soId} not found`);

    const soNumber = so.soNumber ?? String(so.id);
    const rows = await this.buildRows(so.lines);
    // Prefer the accepted date, fall back to approved/created — this is the
    // "Date:" printed on the slip.
    const date = so.acceptedAt ?? so.approvedAt ?? so.createdAt;

    // Best-effort company header from QBO; fall back to a plain Bigfoot header
    // so the slip still renders if QBO is unreachable.
    let header: QboCompanyHeader;
    try {
      header = await this.qbo.getCompanyHeader();
    } catch {
      header = { name: 'Bigfoot Trailers', addressLines: [] };
    }

    // QBO prints the customer's display name then company name (both, even
    // when identical — as its packing slip does), followed by the address.
    const nameBlock = [so.customer.name, so.customer.company].filter(
      (l): l is string => !!l && l.length > 0,
    );
    const billToLines = [
      ...nameBlock,
      ...this.addressLines(so.customer.billingAddress),
    ];
    const shipToLines = [
      ...nameBlock,
      ...this.addressLines(
        so.customer.deliveryAddress || so.customer.billingAddress,
      ),
    ];

    const pdf = await this.render({
      header,
      billToLines,
      shipToLines,
      soNumber,
      date,
      rows,
      withPrices,
      // Totals come from QuickBooks (it owns the tax) — never recomputed here.
      subtotal: Number(so.subtotal),
      taxAmount: Number(so.taxAmount),
      total: Number(so.total),
    });
    return { pdf, soNumber };
  }

  /** Split a one-line address into "Line1" + "City, State Zip" like QBO. */
  private addressLines(addr: string | null): string[] {
    if (!addr) return [];
    const parts = addr
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
    if (parts.length <= 1) return parts;
    return [parts[0], parts.slice(1).join(', ')];
  }

  /** Resolve each line into a printable {service, description, qty} row. */
  private async buildRows(
    lines: {
      kind: string;
      refId: number | null;
      itemName: string | null;
      description: string;
      qty: unknown;
      rate: unknown;
    }[],
  ): Promise<SlipRow[]> {
    const rows: SlipRow[] = [];
    for (const line of lines) {
      const qty = Number(line.qty) || 1;
      const rate = Number(line.rate) || 0;
      rows.push({
        service: await this.serviceName(line),
        description: line.description,
        qty,
        rate,
        amount: qty * rate,
      });
    }
    return rows;
  }

  /** The short "SERVICE" column label — the model code / option / fee name. */
  private async serviceName(line: {
    kind: string;
    refId: number | null;
    itemName: string | null;
    description: string;
  }): Promise<string> {
    // Imported QBO estimates carry the item name directly.
    if (line.itemName) return line.itemName;
    if (line.kind === 'model' && line.refId != null) {
      const m = await this.prisma.trailerModel.findUnique({
        where: { id: line.refId },
        select: { code: true },
      });
      if (m?.code) return m.code;
    } else if (line.kind === 'option' && line.refId != null) {
      const o = await this.prisma.option.findUnique({
        where: { id: line.refId },
        select: { name: true },
      });
      if (o?.name) return o.name;
    } else if (line.kind === 'fee' && line.refId != null) {
      const f = await this.prisma.feeSchedule.findUnique({
        where: { id: line.refId },
        select: { name: true },
      });
      if (f?.name) return f.name;
    }
    // Fallback: first line of the description.
    return line.description.split('\n')[0].slice(0, 60);
  }

  // --- PDF layout -----------------------------------------------------------

  private render(data: {
    header: QboCompanyHeader;
    billToLines: string[];
    shipToLines: string[];
    soNumber: string;
    date: Date | null;
    rows: SlipRow[];
    withPrices: boolean;
    subtotal: number;
    taxAmount: number;
    total: number;
  }): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      const doc = new PDFDocument({ size: 'LETTER', margin: 50 });
      const chunks: Buffer[] = [];
      doc.on('data', (c: Buffer) => chunks.push(c));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      // QBO packing-slip palette.
      const blue = '#0077C5'; // QBO header/title + column-header blue
      const bandBg = '#eef4f9'; // light-blue Bill-to band
      const ink = '#393a3d'; // body text
      const rule = '#e3e5e8'; // hairline row rules
      const pageW = doc.page.width;
      const left = doc.page.margins.left;
      const right = pageW - doc.page.margins.right;

      // ── Title ──────────────────────────────────────────────────────────
      // Same document either way — only the title and the money differ.
      doc
        .fillColor(blue)
        .font('Helvetica-Bold')
        .fontSize(22)
        .text(data.withPrices ? 'SALES ORDER' : 'PACKING SLIP', left, 46);

      // ── Company block ──────────────────────────────────────────────────
      let y = 82;
      doc.fillColor(ink).font('Helvetica-Bold').fontSize(10).text(data.header.name, left, y);
      y = doc.y + 1;
      doc.font('Helvetica').fontSize(9).fillColor(ink);
      for (const l of data.header.addressLines) {
        doc.text(l, left, y);
        y = doc.y;
      }
      if (data.header.email) {
        doc.text(data.header.email, left, y);
        y = doc.y;
      }

      // ── Bill to · Ship to · Sales Order details band (full-bleed) ──────
      const soDetailLines = [`Sales Order no.: ${data.soNumber}`];
      if (data.date) soDetailLines.push(`Date: ${this.fmtDate(data.date)}`);
      // Three columns matching the QBO packing slip.
      const cBill = left;
      const cShip = left + 185;
      const cDet = left + 370;
      const billW = cShip - cBill - 12;
      const shipW = cDet - cShip - 12;
      const detW = right - cDet;

      doc.font('Helvetica').fontSize(9);
      const labelH = 13;
      const colH = (lines: string[], w: number) =>
        lines.reduce((h, l) => h + doc.heightOfString(l, { width: w }), 0);
      const billH = colH(data.billToLines, billW);
      const shipH = colH(data.shipToLines, shipW);
      const detH = colH(soDetailLines, detW);
      const padY = 14;
      const bandTop = y + 18;
      const bandH =
        padY * 2 + labelH + 6 + Math.max(billH, shipH, detH);

      doc.rect(0, bandTop, pageW, bandH).fill(bandBg);

      // Column labels.
      let ty = bandTop + padY;
      doc.fillColor(ink).font('Helvetica-Bold').fontSize(9);
      doc.text('Bill to', cBill, ty);
      doc.text('Ship to', cShip, ty);
      doc.text('Sales Order details', cDet, ty);
      ty += labelH + 6;

      // Column bodies.
      doc.font('Helvetica').fontSize(9).fillColor(ink);
      const drawCol = (lines: string[], x: number, w: number) => {
        let yy = ty;
        for (const l of lines) {
          doc.text(l, x, yy, { width: w });
          yy = doc.y;
        }
      };
      drawCol(data.billToLines, cBill, billW);
      drawCol(data.shipToLines, cShip, shipW);
      drawCol(soDetailLines, cDet, detW);

      // ── Table ──────────────────────────────────────────────────────────
      // The priced document adds RATE + AMOUNT on the right; the work order is
      // the identical table with those two columns (and the totals) removed.
      y = bandTop + bandH + 26;
      const money = (n: number) =>
        `$${n.toLocaleString('en-US', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        })}`;

      const cService = left;
      const svcW = 150;
      const cDesc = left + 165;
      const numW = 62;
      const qtyW = 34;
      // Right-edge columns, laid out from the right inwards.
      const cAmount = right - numW;
      const cRate = cAmount - numW;
      const cQty = data.withPrices ? cRate - qtyW - 6 : right - qtyW;
      const descW = cQty - cDesc - 10;

      doc.font('Helvetica-Bold').fontSize(9).fillColor(blue);
      doc.text('SERVICE', cService, y, { width: svcW });
      doc.text('DESCRIPTION', cDesc, y, { width: descW });
      doc.text('QTY', cQty, y, { width: qtyW, align: 'right' });
      if (data.withPrices) {
        doc.text('RATE', cRate, y, { width: numW, align: 'right' });
        doc.text('AMOUNT', cAmount, y, { width: numW, align: 'right' });
      }
      y += 16;
      doc.strokeColor(rule).lineWidth(1).moveTo(left, y).lineTo(right, y).stroke();
      y += 10;

      // Rows — row height driven by the tallest wrapping column.
      doc.font('Helvetica').fontSize(9).fillColor(ink);
      for (const row of data.rows) {
        const svcH = doc.heightOfString(row.service, { width: svcW });
        const descH = doc.heightOfString(row.description, { width: descW });
        const rowH = Math.max(svcH, descH) + 14;

        if (y + rowH > doc.page.height - doc.page.margins.bottom) {
          doc.addPage();
          y = doc.page.margins.top;
        }

        doc.fillColor(ink).font('Helvetica').fontSize(9);
        doc.text(row.service, cService, y, { width: svcW });
        doc.text(row.description, cDesc, y, { width: descW });
        doc.text(String(row.qty), cQty, y, { width: qtyW, align: 'right' });
        if (data.withPrices) {
          doc.text(money(row.rate), cRate, y, { width: numW, align: 'right' });
          doc.text(money(row.amount), cAmount, y, {
            width: numW,
            align: 'right',
          });
        }
        y += rowH;
        doc.strokeColor(rule).lineWidth(1).moveTo(left, y - 7).lineTo(right, y - 7).stroke();
      }

      // ── Totals (priced document only) ──────────────────────────────────
      if (data.withPrices) {
        y += 12;
        const labelX = cRate - 40;
        const totalRow = (label: string, value: number, bold = false) => {
          doc
            .font(bold ? 'Helvetica-Bold' : 'Helvetica')
            .fontSize(bold ? 11 : 9)
            .fillColor(ink);
          doc.text(label, labelX, y, { width: numW + 40, align: 'right' });
          doc.text(money(value), cAmount, y, { width: numW, align: 'right' });
          y += bold ? 20 : 15;
        };
        totalRow('Subtotal', data.subtotal);
        totalRow('Tax', data.taxAmount);
        doc
          .strokeColor(rule)
          .lineWidth(1)
          .moveTo(labelX, y - 3)
          .lineTo(right, y - 3)
          .stroke();
        y += 5;
        totalRow('Total', data.total, true);
      }

      doc.end();
    });
  }

  private fmtDate(d: Date): string {
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    return `${mm}/${dd}/${d.getFullYear()}`;
  }
}
