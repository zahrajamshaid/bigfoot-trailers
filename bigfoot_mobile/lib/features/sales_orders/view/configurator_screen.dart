import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../data/models/customer.dart';
import '../../customers/view/customer_form_screen.dart';
import '../../customers/viewmodel/customers_viewmodel.dart';
import '../../../shared/widgets/stock_location_chips.dart';
import '../data/sales_order_api.dart';

/// Phase 2 — Sales Order configurator. Pick a customer → model → options,
/// see a live price preview, create the order, and push it to QuickBooks as
/// an Estimate (styled as the Sales Order). This is the app-native sales flow.
class ConfiguratorScreen extends StatefulWidget {
  const ConfiguratorScreen({super.key});

  @override
  State<ConfiguratorScreen> createState() => _ConfiguratorScreenState();
}

class _ConfiguratorScreenState extends State<ConfiguratorScreen> {
  late final SalesOrderApi _api;
  bool _loading = true;
  String? _error;

  CatalogData? _catalog;
  List<Customer> _customers = const [];

  Customer? _customer;
  CatalogModel? _model;
  final Set<int> _optionIds = {};

  // Quick Estimate (Slice 2b) — the fast lane. Instead of picking a full
  // customer record, sales types a name (+ phone) and the app creates the
  // minimal customer. Same engine, same defaults + fees — just fewer taps.
  bool _quickMode = false;
  final _quickNameController = TextEditingController();
  final _quickPhoneController = TextEditingController();
  // Optional for now, but the customer's email is what lets us email the
  // estimate straight to them (QuickBooks needs a BillEmail to send).
  final _quickEmailController = TextEditingController();

  // Build spec — the same fields the trailer-create form captured. They ride
  // on the estimate and are applied to the trailer when it's converted.
  final _colorController = TextEditingController();
  final _sizeController = TextEditingController();
  final _notesController = TextEditingController();
  final _specialNoteController = TextEditingController();
  bool _isStockBuild = false;
  int? _stockLocationId;
  String? _stockLocationError;

  ComposedPreview? _preview;
  Timer? _previewDebounce;

  bool _busy = false;
  SalesOrder? _result; // set after create/approve

  @override
  void initState() {
    super.initState();
    _api = SalesOrderApi(context.read<DioClient>());
    _load();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _colorController.dispose();
    _sizeController.dispose();
    _notesController.dispose();
    _specialNoteController.dispose();
    _quickNameController.dispose();
    _quickPhoneController.dispose();
    _quickEmailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final customersVm = context.read<CustomersViewModel>();
      final catalog = await _api.catalog();
      final custs =
          await customersVm.getCustomers(limit: 100, excludeStockLocations: true);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _customers = custs.items;
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

  void _onModelChanged(CatalogModel? m) {
    setState(() {
      _model = m;
      _optionIds
        ..clear()
        // auto-check the model's default options (e.g. spare tire)
        ..addAll(m?.options.where((o) => o.defaultForModel).map((o) => o.id) ??
            const []);
      _result = null;
    });
    _schedulePreview();
  }

  void _toggleOption(int id, bool on) {
    setState(() {
      if (on) {
        _optionIds.add(id);
      } else {
        _optionIds.remove(id);
      }
      _result = null;
    });
    _schedulePreview();
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    if (_model == null) {
      setState(() => _preview = null);
      return;
    }
    _previewDebounce = Timer(const Duration(milliseconds: 300), _runPreview);
  }

  Future<void> _runPreview() async {
    final m = _model;
    if (m == null) return;
    try {
      final p = await _api.preview(
        modelId: m.id,
        optionIds: _optionIds.toList(),
        autoAddFees: true,
      );
      if (mounted) setState(() => _preview = p);
    } catch (_) {
      // preview is best-effort; ignore transient errors
    }
  }

  /// Create a brand-new customer inline (reuses the customer form, which
  /// syncs the new customer straight to QuickBooks), then select it.
  Future<void> _newCustomer() async {
    final vm = context.read<CustomersViewModel>();
    Customer? created;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          onSubmit: (c) async {
            created = await vm.createCustomer(c);
          },
        ),
      ),
    );
    if (created != null && mounted) {
      setState(() {
        if (!_customers.any((c) => c.id == created!.id)) {
          _customers = [created!, ..._customers];
        }
        _customer = _customers.firstWhere((c) => c.id == created!.id);
        _result = null;
      });
    }
  }

  /// Fetch the QuickBooks estimate PDF and open the system print/share/save
  /// sheet (works on web + mobile via the printing package).
  Future<void> _downloadPdf(int id) async {
    try {
      final bytes = await _api.estimatePdf(id);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF unavailable: $e')));
    }
  }

  Future<void> _createAndApprove() async {
    final c = _customer;
    final m = _model;
    final quickName = _quickNameController.text.trim();
    if (m == null) return;
    if (_quickMode ? quickName.isEmpty : c == null) return;

    // A stock build must name the yard it ships to (same rule as the
    // trailer-create form).
    if (_isStockBuild && _stockLocationId == null) {
      setState(() => _stockLocationError = 'Pick a destination yard');
      return;
    }
    setState(() {
      _stockLocationError = null;
      _busy = true;
    });
    try {
      final draft = await _api.createDraft(
        customerId: _quickMode ? null : c!.id.toString(),
        quickName: _quickMode ? quickName : null,
        quickPhone: _quickMode ? _quickPhoneController.text.trim() : null,
        quickEmail: _quickMode ? _quickEmailController.text.trim() : null,
        modelId: m.id,
        optionIds: _optionIds.toList(),
        autoAddFees: true,
        color: _colorController.text.trim(),
        sizeFt: _sizeController.text.trim(),
        optionsNotes: _notesController.text.trim(),
        specialNote: _specialNoteController.text.trim(),
        isStockBuild: _isStockBuild,
        stockLocationId: _stockLocationId,
      );
      final approved = await _api.approve(draft.id);
      if (!mounted) return;
      setState(() => _result = approved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Email the QuickBooks estimate to the customer.
  Future<void> _send(int id) async {
    setState(() => _busy = true);
    try {
      final so = await _api.send(id);
      if (!mounted) return;
      setState(() => _result = so);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estimate emailed to the customer')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Send failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Customer accepted the estimate → convert it to a Sales Order (and, when
  /// it maps to a trailer model, the production trailer / work order).
  Future<void> _accept(int id) async {
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
      final so = await _api.accept(id);
      if (!mounted) return;
      setState(() => _result = so);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(so.isConverted
              ? 'Converted — Sales Order + work order created'
              : 'Converted to Sales Order')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Convert failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Sales Order')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _result != null
                  ? _ResultView(
                      result: _result!,
                      busy: _busy,
                      onDownloadPdf: () => _downloadPdf(_result!.id),
                      onSend: () => _send(_result!.id),
                      onAccept: () => _accept(_result!.id),
                      onNew: () => setState(() {
                        _result = null;
                        _customer = null;
                        _model = null;
                        _optionIds.clear();
                        _preview = null;
                      }),
                    )
                  : _buildForm(),
    );
  }

  Widget _buildForm() {
    final catalog = _catalog!;
    final hasCustomer = _quickMode
        ? _quickNameController.text.trim().isNotEmpty
        : _customer != null;
    final canSubmit = hasCustomer && _model != null && !_busy;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Quick Estimate toggle — a priced quote from just a name + phone.
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.person_outline, size: 18),
              label: Text('Full order'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.bolt_outlined, size: 18),
              label: Text('Quick estimate'),
            ),
          ],
          selected: {_quickMode},
          onSelectionChanged: (s) => setState(() {
            _quickMode = s.first;
            _result = null;
          }),
        ),
        const SizedBox(height: 16),

        if (_quickMode) ...[
          _label('Customer (quick)'),
          const SizedBox(height: 8),
          TextField(
            controller: _quickNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Name',
              hintText: 'Who is this quote for?',
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quickPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Phone (optional)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quickEmailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Email (optional)',
              hintText: 'So you can email them the estimate',
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Creates the customer for you — fill in the full record later. '
            'The quote is not re-entered. Add an email if you want to send the '
            'estimate straight to the customer.',
            style: TextStyle(fontSize: 12, color: AppColors.disabled),
          ),
          const SizedBox(height: 16),
        ] else ...[
          Row(
            children: [
              Expanded(child: _label('Customer')),
              TextButton.icon(
                onPressed: _newCustomer,
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('New'),
              ),
            ],
          ),
          _customerDropdown(),
        ],
        _buildRest(catalog, canSubmit),
      ],
    );
  }

  Widget _customerDropdown() {
    return DropdownButtonFormField<Customer>(
          value: _customer,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Pick a customer',
          ),
          items: _customers
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c.company?.isNotEmpty == true ? c.company! : c.name,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (c) => setState(() {
            _customer = c;
            _result = null;
          }),
    );
  }

  /// Everything below the customer block — identical in both modes, so a quick
  /// quote and a full order run through exactly the same engine.
  Widget _buildRest(CatalogData catalog, bool canSubmit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        _label('Model'),
        DropdownButtonFormField<CatalogModel>(
          value: _model,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Pick a trailer model',
          ),
          items: catalog.models
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text('${m.code} — ${m.displayName}',
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: _onModelChanged,
        ),
        if (_model != null) ...[
          const SizedBox(height: 16),
          _label('Options'),
          if (_model!.options.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No options for this model',
                  style: TextStyle(color: AppColors.disabled)),
            ),
          ..._model!.options.map((o) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _optionIds.contains(o.id),
                onChanged: (v) => _toggleOption(o.id, v ?? false),
                title: Text(o.name),
                subtitle: o.price > 0
                    ? Text('\$${o.price.toStringAsFixed(2)}')
                    : null,
              )),
        ],

        // ── Build spec ───────────────────────────────────────────────────
        // The estimate replaces the QuickBooks PDF as the source of build
        // intent, so it captures everything the trailer-create form did.
        // These flow straight onto the trailer when the estimate is converted.
        const SizedBox(height: 20),
        _label('Build details'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _colorController,
                decoration: const InputDecoration(
                  labelText: 'Color',
                  hintText: 'e.g. Black',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _sizeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Size (ft)',
                  hintText: 'e.g. 16',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Build / options notes',
            hintText: 'Add-ons and build notes for the shop',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _specialNoteController,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'VIN Number',
            hintText: 'Trailer VIN',
            alignLabelWithHint: true,
          ),
        ),
        SwitchListTile(
          value: _isStockBuild,
          contentPadding: EdgeInsets.zero,
          title: const Text('Stock build'),
          subtitle: const Text('Building for inventory, not this customer'),
          onChanged: (v) => setState(() {
            _isStockBuild = v;
            if (!v) {
              _stockLocationId = null;
              _stockLocationError = null;
            }
          }),
        ),
        if (_isStockBuild) ...[
          const SizedBox(height: 4),
          StockLocationChips(
            selectedLocationId: _stockLocationId,
            errorText: _stockLocationError,
            labelText: 'Destination yard',
            onChanged: (loc) => setState(() {
              _stockLocationId = loc.id;
              _stockLocationError = null;
            }),
          ),
        ],

        const SizedBox(height: 16),
        if (_preview != null) _PreviewPanel(preview: _preview!),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: canSubmit ? _createAndApprove : null,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_outlined),
          label: const Text('Create & send to QuickBooks'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(s.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.navy)),
      );
}

class _PreviewPanel extends StatelessWidget {
  final ComposedPreview preview;
  const _PreviewPanel({required this.preview});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PREVIEW',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.navy)),
          const SizedBox(height: 8),
          ...preview.lines.map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        l.kind == 'model'
                            ? l.description.split('\n').first
                            : l.description,
                        maxLines: l.kind == 'model' ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('\$${l.rate.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal (tax computed by QuickBooks)',
                  style: TextStyle(fontSize: 12, color: AppColors.disabled)),
              Text('\$${preview.previewSubtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final SalesOrder result;
  final bool busy;
  final VoidCallback onNew;
  final VoidCallback onDownloadPdf;
  final VoidCallback onSend;
  final VoidCallback onAccept;
  const _ResultView({
    required this.result,
    required this.busy,
    required this.onNew,
    required this.onDownloadPdf,
    required this.onSend,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final synced = result.syncState == 'synced';
    final converted = result.trailerId != null;
    final accepted = result.acceptedAt != null;
    final canAccept = result.status == 'approved' && !accepted;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(synced ? Icons.check_circle : Icons.error_outline,
            size: 56,
            color: synced ? AppColors.success : AppColors.error),
        const SizedBox(height: 12),
        Center(
          child: Text(
            synced ? 'Sales Order created' : 'Created — QuickBooks sync failed',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        _row('SO number', result.soNumber ?? '—'),
        _row('Status', result.status),
        _row('QuickBooks sync', result.syncState),
        if (result.qboEstimateId != null)
          _row('QBO Estimate', '#${result.qboDocNumber ?? result.qboEstimateId}'),
        if (converted) _row('Work order', 'Trailer #${result.trailerId}'),
        _row('Subtotal', '\$${result.subtotal.toStringAsFixed(2)}'),
        _row('Tax (QBO)', '\$${result.taxAmount.toStringAsFixed(2)}'),
        _row('Total', '\$${result.total.toStringAsFixed(2)}'),
        if (result.syncError != null) ...[
          const SizedBox(height: 8),
          Text(result.syncError!,
              style: const TextStyle(color: AppColors.error, fontSize: 12)),
        ],
        const SizedBox(height: 24),

        // When the customer accepts, convert the estimate → Sales Order. This
        // is the headline action, so it leads.
        if (canAccept) ...[
          FilledButton.icon(
            onPressed: busy ? null : onAccept,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Convert to Sales Order'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (accepted) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              converted
                  ? 'Converted — work order #${result.trailerId} is now in production.'
                  : 'Converted to Sales Order.',
              style: TextStyle(
                  color: Colors.green.shade800, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
        ],

        if (result.qboEstimateId != null) ...[
          FilledButton.icon(
            onPressed: busy ? null : onDownloadPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Download estimate PDF'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : onSend,
            icon: const Icon(Icons.email_outlined),
            label: Text(result.sentAt != null
                ? 'Resend estimate to customer'
                : 'Send estimate to customer'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: busy ? null : onNew,
          icon: const Icon(Icons.add),
          label: const Text('New Sales Order'),
        ),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: AppColors.disabled)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
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
            const Icon(Icons.error_outline, size: 44, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
