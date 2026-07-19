import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

/// Prisma serialises Decimal columns as JSON strings ("217.50"), while plain
/// numbers arrive as num. This tolerates both so a Decimal field never
/// crashes the parse with "String is not a subtype of num".
double _d(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// Thin API wrapper for the Phase 2 Sales Order configurator. Talks to the
/// backend that composes lines, pushes QBO Estimates, and converts to orders.
class SalesOrderApi {
  final DioClient _api;
  SalesOrderApi(this._api);

  /// Catalog for the configurator: models (each with options) + fees.
  Future<CatalogData> catalog() async {
    final res = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.salesOrderCatalog,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return CatalogData.fromJson(res.data ?? const {});
  }

  /// Live price preview for a configuration (no persistence).
  Future<ComposedPreview> preview({
    required int modelId,
    required List<int> optionIds,
    bool autoAddFees = true,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.salesOrderPreview,
      data: {
        'modelId': modelId,
        'optionIds': optionIds,
        'autoAddFees': autoAddFees,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return ComposedPreview.fromJson(res.data ?? const {});
  }

  /// Create a draft Sales Order. The build spec (colour / size / note /
  /// stock-build) rides along and is applied to the trailer on convert.
  Future<SalesOrder> createDraft({
    String? customerId,
    // Quick Estimate: create the customer inline from just a name (+ phone
    // + email). Email is optional but lets us email the estimate to them.
    String? quickName,
    String? quickPhone,
    String? quickEmail,
    required int modelId,
    required List<int> optionIds,
    bool autoAddFees = true,
    String? color,
    String? sizeFt,
    String? optionsNotes,
    String? specialNote,
    bool isStockBuild = false,
    int? stockLocationId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.salesOrders,
      data: {
        if (customerId != null) 'customerId': customerId,
        if (customerId == null && quickName != null && quickName.isNotEmpty) ...{
          'quickCustomer': {
            'name': quickName,
            if (quickPhone != null && quickPhone.isNotEmpty) 'phone': quickPhone,
            if (quickEmail != null && quickEmail.isNotEmpty) 'email': quickEmail,
          },
          'isQuickEstimate': true,
        },
        'modelId': modelId,
        'optionIds': optionIds,
        'autoAddFees': autoAddFees,
        if (color != null && color.isNotEmpty) 'color': color,
        if (sizeFt != null && sizeFt.isNotEmpty) 'sizeFt': sizeFt,
        if (optionsNotes != null && optionsNotes.isNotEmpty)
          'optionsNotes': optionsNotes,
        if (specialNote != null && specialNote.isNotEmpty)
          'specialNote': specialNote,
        'isStockBuild': isStockBuild,
        if (isStockBuild && stockLocationId != null)
          'stockLocationId': stockLocationId,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SalesOrder.fromJson(res.data ?? const {});
  }

  /// Approve a draft → allocates SO#, pushes the QBO Estimate.
  Future<SalesOrder> approve(int id) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.salesOrderApprove(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SalesOrder.fromJson(res.data ?? const {});
  }

  Future<SalesOrder> retrySync(int id) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.salesOrderRetrySync(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SalesOrder.fromJson(res.data ?? const {});
  }

  /// Delete an estimate — also removes it from QuickBooks. The backend refuses
  /// (400) if it's already a production trailer.
  Future<void> deleteEstimate(int id) async {
    await _api.delete<Map<String, dynamic>>(
      ApiEndpoints.salesOrder(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  /// Record an initial deposit received on the trailer — posts a QuickBooks
  /// customer Payment. Returns the updated estimate.
  Future<SalesOrder> recordDeposit(int id, double amount, {String? method}) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.salesOrderDeposit(id),
      data: {'amount': amount, if (method != null && method.isNotEmpty) 'method': method},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SalesOrder.fromJson(res.data ?? const {});
  }

  /// The QuickBooks estimate PDF bytes for a synced Sales Order.
  Future<Uint8List> estimatePdf(int id) async {
    final res = await _api.dio.get<List<int>>(
      ApiEndpoints.salesOrderEstimatePdf(id),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }

  /// The WORK ORDER PDF (the Sales Order with every dollar amount stripped).
  /// Readable by the floor.
  Future<Uint8List> packingSlipPdf(int id) async {
    final res = await _api.dio.get<List<int>>(
      ApiEndpoints.salesOrderPackingSlip(id),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }

  /// The priced SALES ORDER PDF. Server-side role-gated to owner/office/sales —
  /// a floor role gets a 403.
  Future<Uint8List> salesOrderPdf(int id) async {
    final res = await _api.dio.get<List<int>>(
      ApiEndpoints.salesOrderPricedPdf(id),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }

  /// Slice 1 — pull models/options/fees + prices from QuickBooks. Idempotent.
  Future<Map<String, dynamic>> importCatalogFromQbo() async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.qboImportCatalog,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return res.data ?? const {};
  }

  /// Two-way estimate sync with QuickBooks: import estimates created in QBO and
  /// push any app estimates that failed to reach QBO. Returns a short summary.
  Future<String> syncEstimates() async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.salesOrdersSync,
      data: const {},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final data = res.data ?? const {};
    final imported = (data['imported'] as Map?) ?? const {};
    final pushed = (data['pushed'] as Map?) ?? const {};
    final pulled = (imported['created'] ?? 0) + (imported['updated'] ?? 0);
    final importFailed = imported['failed'] ?? 0;
    final sent = pushed['pushed'] ?? 0;
    final pushFailed = pushed['failed'] ?? 0;

    var msg = 'Synced estimates — pulled $pulled from QuickBooks, pushed $sent';
    final problems = <String>[
      if (importFailed != 0) '$importFailed couldn\'t import',
      if (pushFailed != 0) '$pushFailed failed to push',
    ];
    if (problems.isNotEmpty) msg += ' (${problems.join(', ')})';
    return msg;
  }

  Future<List<SalesOrder>> list() async {
    final res = await _api.get<List<dynamic>>(
      ApiEndpoints.salesOrders,
      fromJson: (d) => d as List<dynamic>,
    );
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SalesOrder.fromJson)
        .toList();
  }

  /// One Sales Order with its composed lines + customer.
  Future<SalesOrder> get(int id) async {
    final res = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.salesOrder(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SalesOrder.fromJson(res.data ?? const {});
  }

  /// Email the QuickBooks estimate to the customer.
  Future<SalesOrder> send(int id) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.salesOrderSend(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SalesOrder.fromJson(res.data ?? const {});
  }

  /// Accept the estimate → convert it to a production trailer (work order).
  Future<SalesOrder> accept(int id) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.salesOrderAccept(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SalesOrder.fromJson(res.data ?? const {});
  }
}

// ── Models ───────────────────────────────────────────────────────────────

class CatalogData {
  final List<CatalogModel> models;
  final List<CatalogFee> fees;
  const CatalogData({required this.models, required this.fees});
  factory CatalogData.fromJson(Map<String, dynamic> j) => CatalogData(
        models: ((j['models'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CatalogModel.fromJson)
            .toList(),
        fees: ((j['fees'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CatalogFee.fromJson)
            .toList(),
      );
}

class CatalogModel {
  final int id;
  final String code;
  final String displayName;
  final String series;
  final double basePrice;
  final List<CatalogOption> options;
  const CatalogModel({
    required this.id,
    required this.code,
    required this.displayName,
    required this.series,
    required this.basePrice,
    required this.options,
  });
  factory CatalogModel.fromJson(Map<String, dynamic> j) => CatalogModel(
        id: (j['id'] as num).toInt(),
        code: j['code'] as String? ?? '',
        displayName: j['displayName'] as String? ?? '',
        series: j['series'] as String? ?? '',
        basePrice: _d(j['basePrice']),
        options: ((j['options'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CatalogOption.fromJson)
            .toList(),
      );
}

class CatalogOption {
  final int id;
  final String name;
  final String? description;
  final double price;
  final bool defaultForModel;
  const CatalogOption({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.defaultForModel,
  });
  factory CatalogOption.fromJson(Map<String, dynamic> j) => CatalogOption(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        price: _d(j['price']),
        defaultForModel: j['defaultForModel'] as bool? ?? false,
      );
}

class CatalogFee {
  final int id;
  final String name;
  final double amount;
  final bool autoAdd;
  const CatalogFee({
    required this.id,
    required this.name,
    required this.amount,
    required this.autoAdd,
  });
  factory CatalogFee.fromJson(Map<String, dynamic> j) => CatalogFee(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        amount: _d(j['amount']),
        autoAdd: j['autoAdd'] as bool? ?? false,
      );
}

class ComposedLine {
  final String kind;
  final String description;
  final double qty;
  final double rate;
  const ComposedLine({
    required this.kind,
    required this.description,
    required this.qty,
    required this.rate,
  });
  factory ComposedLine.fromJson(Map<String, dynamic> j) => ComposedLine(
        kind: j['kind'] as String? ?? '',
        description: j['description'] as String? ?? '',
        qty: j['qty'] == null ? 1 : _d(j['qty']),
        rate: _d(j['rate']),
      );
}

class ComposedPreview {
  final List<ComposedLine> lines;
  final double previewSubtotal;
  const ComposedPreview({required this.lines, required this.previewSubtotal});
  factory ComposedPreview.fromJson(Map<String, dynamic> j) => ComposedPreview(
        lines: ((j['lines'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ComposedLine.fromJson)
            .toList(),
        previewSubtotal: _d(j['previewSubtotal']),
      );
}

class SalesOrder {
  final int id;
  final String? soNumber;
  final String status;
  final String syncState;
  final String? qboEstimateId;
  final String? qboDocNumber;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String? syncError;
  final String? customerName;
  final int lineCount;
  final String? createdAt;
  final String? sentAt;
  final String? acceptedAt;
  final int? trailerId;
  final double? depositAmount;
  final String? depositPaidAt;
  final String? depositMethod;
  final String? qboPaymentId;
  final List<ComposedLine> lines;
  const SalesOrder({
    required this.id,
    required this.soNumber,
    required this.status,
    required this.syncState,
    required this.qboEstimateId,
    required this.qboDocNumber,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.syncError,
    this.customerName,
    this.lineCount = 0,
    this.createdAt,
    this.sentAt,
    this.acceptedAt,
    this.trailerId,
    this.depositAmount,
    this.depositPaidAt,
    this.depositMethod,
    this.qboPaymentId,
    this.lines = const [],
  });

  bool get isSynced => qboEstimateId != null;
  bool get isSent => sentAt != null;
  bool get isConverted => trailerId != null;
  bool get hasDeposit => depositAmount != null && depositAmount! > 0;

  factory SalesOrder.fromJson(Map<String, dynamic> j) {
    final customer = j['customer'];
    final count = j['_count'];
    return SalesOrder(
      id: (j['id'] as num).toInt(),
      soNumber: j['soNumber'] as String?,
      status: j['status'] as String? ?? 'draft',
      syncState: j['syncState'] as String? ?? 'pending',
      qboEstimateId: j['qboEstimateId'] as String?,
      qboDocNumber: j['qboDocNumber'] as String?,
      subtotal: _d(j['subtotal']),
      taxAmount: _d(j['taxAmount']),
      total: _d(j['total']),
      syncError: j['syncError'] as String?,
      customerName: customer is Map<String, dynamic>
          ? (customer['company'] as String?)?.isNotEmpty == true
              ? customer['company'] as String?
              : customer['name'] as String?
          : null,
      lineCount: count is Map<String, dynamic>
          ? (count['lines'] as num?)?.toInt() ?? 0
          : ((j['lines'] as List<dynamic>?)?.length ?? 0),
      createdAt: j['createdAt'] as String?,
      sentAt: j['sentAt'] as String?,
      acceptedAt: j['acceptedAt'] as String?,
      trailerId: (j['trailerId'] as num?)?.toInt(),
      depositAmount: j['depositAmount'] == null ? null : _d(j['depositAmount']),
      depositPaidAt: j['depositPaidAt'] as String?,
      depositMethod: j['depositMethod'] as String?,
      qboPaymentId: j['qboPaymentId'] as String?,
      lines: ((j['lines'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ComposedLine.fromJson)
          .toList(),
    );
  }
}
