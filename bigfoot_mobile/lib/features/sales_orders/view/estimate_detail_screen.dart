import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../data/sales_order_api.dart';
import 'sales_order_status.dart';

/// QBO-style estimate detail: the composed lines, totals, sync/status chips,
/// and the full estimate action menu — Download PDF, Send to customer,
/// Accept → convert to a production trailer, and Retry sync.
class EstimateDetailScreen extends StatefulWidget {
  final int id;
  const EstimateDetailScreen({super.key, required this.id});

  @override
  State<EstimateDetailScreen> createState() => _EstimateDetailScreenState();
}

class _EstimateDetailScreenState extends State<EstimateDetailScreen> {
  late final SalesOrderApi _api;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  SalesOrder? _so;
  Uint8List? _pdfCache;

  /// Fetch (and cache) the exact QuickBooks estimate PDF bytes.
  Future<Uint8List> _pdfBytes() async =>
      _pdfCache ??= await _api.estimatePdf(widget.id);

  @override
  void initState() {
    super.initState();
    _api = SalesOrderApi(context.read<DioClient>());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final so = await _api.get(widget.id);
      if (!mounted) return;
      setState(() => _so = so);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// View the exact QuickBooks estimate PDF fit-to-width in-app.
  Future<void> _viewPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdfBytes();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _EstimatePdfViewer(
          bytes: bytes,
          label: _so?.soNumber ?? '${widget.id}',
        ),
      ));
    } catch (e) {
      _snack('PDF unavailable: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Download / share the estimate PDF, saved as the SO number.
  Future<void> _downloadPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdfBytes();
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${_so?.soNumber ?? widget.id}.pdf',
      );
    } catch (e) {
      _snack('Download failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final so = await _api.send(widget.id);
      if (!mounted) return;
      setState(() => _so = so);
      _snack('Estimate emailed to the customer');
    } catch (e) {
      _snack('Send failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convert to Sales Order?'),
        content: const Text(
          'This marks the estimate Accepted in QuickBooks and converts it into '
          'a Sales Order. If it maps to a trailer model, the production trailer '
          '(work order) is created too. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final so = await _api.accept(widget.id);
      if (!mounted) return;
      setState(() => _so = so);
      _snack(so.isConverted
          ? 'Converted — Sales Order + work order created'
          : 'Converted to Sales Order');
    } catch (e) {
      _snack('Convert failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retrySync() async {
    setState(() => _busy = true);
    try {
      final so = await _api.retrySync(widget.id);
      if (!mounted) return;
      setState(() => _so = so);
      _snack('Sync retried');
    } catch (e) {
      _snack('Retry failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final so = _so;
    final label = so?.soNumber != null ? '#${so!.soNumber}' : 'this estimate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete estimate?'),
        content: Text(
          'Estimate $label will be deleted here AND removed from QuickBooks. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _api.deleteEstimate(widget.id);
      if (!mounted) return;
      _snack('Estimate deleted (and removed from QuickBooks)');
      Navigator.of(context).pop(true); // back to the list, which reloads
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('Delete failed: $e');
    }
  }

  Future<void> _recordDeposit() async {
    final amountCtl = TextEditingController();
    final methodCtl = TextEditingController();
    final entered = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record deposit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: methodCtl,
              decoration: const InputDecoration(
                labelText: 'Method (optional) — cash, card, check…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Posts a matching Payment to QuickBooks.',
              style: TextStyle(fontSize: 12, color: AppColors.disabled),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (entered != true) return;

    final amount = double.tryParse(amountCtl.text.trim());
    if (amount == null || amount <= 0) {
      _snack('Enter a deposit amount greater than zero');
      return;
    }

    setState(() => _busy = true);
    try {
      final so = await _api.recordDeposit(widget.id, amount, method: methodCtl.text.trim());
      if (!mounted) return;
      setState(() => _so = so);
      _snack(so.qboPaymentId != null
          ? 'Deposit recorded and posted to QuickBooks'
          : 'Deposit recorded (QuickBooks post pending)');
    } catch (e) {
      _snack('Deposit failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _deposit(SalesOrder so) {
    return Card(
      color: AppColors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Deposit',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (!so.hasDeposit)
                  TextButton.icon(
                    onPressed: _busy ? null : _recordDeposit,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Record'),
                  ),
              ],
            ),
            if (so.hasDeposit) ...[
              const SizedBox(height: 4),
              Text(
                '\$${so.depositAmount!.toStringAsFixed(2)}'
                '${so.depositMethod != null ? ' · ${so.depositMethod}' : ''}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                so.qboPaymentId != null
                    ? 'Posted to QuickBooks'
                    : 'Recorded — QuickBooks post pending',
                style: TextStyle(
                  fontSize: 12,
                  color: so.qboPaymentId != null ? Colors.green : Colors.orange,
                ),
              ),
            ] else
              const Text('No deposit recorded yet.',
                  style: TextStyle(color: AppColors.disabled)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final so = _so;
    return Scaffold(
      appBar: AppBar(
        title: Text(so?.soNumber != null ? 'Estimate #${so!.soNumber}' : 'Estimate'),
        actions: [
          // A converted estimate is a live trailer — no delete (the backend
          // refuses it too). Edit that trailer into a stock build instead.
          if (so != null && !so.isConverted)
            IconButton(
              tooltip: 'Delete estimate',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _error != null
              ? Center(child: Text(_error!))
              : so == null
                  ? const SizedBox.shrink()
                  : Stack(
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _header(so),
                              const SizedBox(height: 16),
                              _lines(so),
                              const SizedBox(height: 16),
                              _totals(so),
                              const SizedBox(height: 16),
                              _deposit(so),
                              const SizedBox(height: 24),
                              _actions(so),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                        if (_busy)
                          const Positioned.fill(
                            child: ColoredBox(
                              color: Color(0x33000000),
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.amber),
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }

  Widget _header(SalesOrder so) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            so.customerName ?? 'Customer',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              SoStatusChip(status: so.status),
              SyncStateChip(state: so.syncState),
              if (so.isSent) const _Tag(label: 'Sent', color: Colors.teal),
              if (so.isConverted)
                _Tag(label: 'Trailer #${so.trailerId}', color: Colors.indigo),
            ],
          ),
          if (so.qboDocNumber != null) ...[
            const SizedBox(height: 10),
            Text('QuickBooks estimate: ${so.qboDocNumber}',
                style: const TextStyle(color: AppColors.disabled, fontSize: 12)),
          ],
          if (so.syncError != null) ...[
            const SizedBox(height: 6),
            Text(so.syncError!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _lines(SalesOrder so) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          for (final l in so.lines) ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_kindLabel(l.kind),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.disabled,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(l.description),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('\$${l.rate.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (l != so.lines.last)
              const Divider(height: 1, color: AppColors.divider),
          ],
        ],
      ),
    );
  }

  Widget _totals(SalesOrder so) {
    Widget row(String label, double v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
              Text('\$${v.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          row('Subtotal', so.subtotal),
          row('Tax (QuickBooks)', so.taxAmount),
          const Divider(),
          row('Total', so.total, bold: true),
        ],
      ),
    );
  }

  Widget _actions(SalesOrder so) {
    final children = <Widget>[];

    if (so.isSynced) {
      children.add(FilledButton.icon(
        onPressed: _busy ? null : _viewPdf,
        icon: const Icon(Icons.visibility_outlined),
        label: const Text('View PDF'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          minimumSize: const Size.fromHeight(48),
        ),
      ));
      children.add(OutlinedButton.icon(
        onPressed: _busy ? null : _downloadPdf,
        icon: const Icon(Icons.download_outlined),
        label: const Text('Download PDF'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ));
      children.add(OutlinedButton.icon(
        onPressed: _busy ? null : _send,
        icon: const Icon(Icons.email_outlined),
        label: Text(so.isSent ? 'Resend to customer' : 'Send to customer'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ));
    }

    if (so.status == 'approved' && so.acceptedAt == null) {
      children.add(FilledButton.icon(
        onPressed: _busy ? null : _accept,
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Convert to Sales Order'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          minimumSize: const Size.fromHeight(48),
        ),
      ));
    }

    if (so.syncState == 'error') {
      children.add(OutlinedButton.icon(
        onPressed: _busy ? null : _retrySync,
        icon: const Icon(Icons.sync_problem),
        label: const Text('Retry QuickBooks sync'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: Colors.red,
        ),
      ));
    }

    if (!so.isSynced) {
      children.add(const Text(
        'Not yet in QuickBooks. Finalizing this estimate (marking it Quoted) '
        'pushes it to QuickBooks and unlocks PDF / send / accept.',
        style: TextStyle(color: AppColors.disabled),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  static String _kindLabel(String kind) => switch (kind) {
        'model' => 'TRAILER',
        'option' => 'OPTION',
        'fee' => 'FEE',
        'discount' => 'DISCOUNT',
        _ => kind.toUpperCase(),
      };
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// In-app viewer for the exact QuickBooks estimate PDF — fit-to-width, with
/// the printing package's built-in print / share / download actions.
class _EstimatePdfViewer extends StatelessWidget {
  final Uint8List bytes;
  final String label;
  const _EstimatePdfViewer({required this.bytes, required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Estimate · $label')),
      body: PdfPreview(
        build: (_) => bytes,
        pdfFileName: '$label.pdf',
        maxPageWidth: 700,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        previewPageMargin: const EdgeInsets.all(12),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
