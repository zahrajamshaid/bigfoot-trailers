class CustomerType {
  static const String endUser = 'end_user';
  static const String dealer = 'dealer';
  static const String stockLocation = 'stock_location';

  static const values = [endUser, dealer, stockLocation];
}

class Customer {
  final int id;
  final String name;
  final String? company;
  final String? phone;
  final String? email;
  final String customerType;
  final String? billingAddress;
  final String? deliveryAddress;
  final bool smsOptOut;
  final String? quickbooksCustomerId;
  final String? notes;
  // Set when customerType == stock_location — tells callers which yard
  // this stock customer represents.
  final int? stockLocationId;
  final int activeTrailerCount;

  const Customer({
    required this.id,
    required this.name,
    this.company,
    this.phone,
    this.email,
    required this.customerType,
    this.billingAddress,
    this.deliveryAddress,
    this.smsOptOut = false,
    this.quickbooksCustomerId,
    this.notes,
    this.stockLocationId,
    this.activeTrailerCount = 0,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      company: json['company'] as String?,
      phone: (json['phone'] ?? json['smsPhone']) as String?,
      email: json['email'] as String?,
      customerType: json['customerType'] as String? ?? CustomerType.endUser,
      billingAddress: json['billingAddress'] as String?,
      deliveryAddress: json['deliveryAddress'] as String?,
      smsOptOut: json['smsOptOut'] as bool? ?? false,
      quickbooksCustomerId:
          (json['quickbooksCustomerId'] ?? json['qbCustomerId']) as String?,
      notes: json['notes'] as String?,
      stockLocationId: (json['stockLocationId'] as num?)?.toInt(),
      activeTrailerCount: (json['activeTrailerCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toCreatePayload() {
    // Backend DTOs use `smsPhone` (not `phone`); class-validator whitelist
    // rejects the request if we send the wrong key.
    return {
      'name': name,
      if (company != null && company!.isNotEmpty) 'company': company,
      if (phone != null && phone!.isNotEmpty) 'smsPhone': phone,
      if (email != null && email!.isNotEmpty) 'email': email,
      'customerType': customerType,
      if (billingAddress != null && billingAddress!.isNotEmpty)
        'billingAddress': billingAddress,
      if (deliveryAddress != null && deliveryAddress!.isNotEmpty)
        'deliveryAddress': deliveryAddress,
      'smsOptOut': smsOptOut,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      if (stockLocationId != null) 'stockLocationId': stockLocationId,
    };
  }

  Map<String, dynamic> toUpdatePayload() {
    return {
      'name': name,
      'company': company,
      'smsPhone': phone,
      'email': email,
      'customerType': customerType,
      'billingAddress': billingAddress,
      'deliveryAddress': deliveryAddress,
      'smsOptOut': smsOptOut,
      'notes': notes,
      'stockLocationId': stockLocationId,
    };
  }
}

class CustomerTrailerHistoryItem {
  final int trailerId;
  final String soNumber;
  final String? vinNumber;
  final String status;

  const CustomerTrailerHistoryItem({
    required this.trailerId,
    required this.soNumber,
    this.vinNumber,
    required this.status,
  });

  factory CustomerTrailerHistoryItem.fromJson(Map<String, dynamic> json) {
    return CustomerTrailerHistoryItem(
      trailerId: (json['trailerId'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt() ??
          0,
      soNumber: json['soNumber'] as String? ?? '-',
      vinNumber: json['vinNumber'] as String?,
      status: json['status'] as String? ?? 'unknown',
    );
  }
}

class CustomerDeliveryHistoryItem {
  final int deliveryId;
  final int? trailerId;
  final String status;
  final String? deliveryType;
  final DateTime? deliveredAt;

  const CustomerDeliveryHistoryItem({
    required this.deliveryId,
    this.trailerId,
    required this.status,
    this.deliveryType,
    this.deliveredAt,
  });

  factory CustomerDeliveryHistoryItem.fromJson(Map<String, dynamic> json) {
    return CustomerDeliveryHistoryItem(
      deliveryId: (json['deliveryId'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt() ??
          0,
      trailerId: (json['trailerId'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'unknown',
      deliveryType: json['deliveryType'] as String?,
      deliveredAt: json['deliveredAt'] == null
          ? null
          : DateTime.tryParse(json['deliveredAt'] as String),
    );
  }
}

class CustomerDetail {
  final Customer customer;
  final List<CustomerTrailerHistoryItem> trailerHistory;
  final List<CustomerDeliveryHistoryItem> deliveryHistory;

  const CustomerDetail({
    required this.customer,
    required this.trailerHistory,
    required this.deliveryHistory,
  });

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    final customerJson =
        (json['customer'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return CustomerDetail(
      customer: Customer.fromJson(customerJson.isNotEmpty ? customerJson : json),
      trailerHistory: ((json['trailerHistory'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CustomerTrailerHistoryItem.fromJson)
          .toList(),
      deliveryHistory: ((json['deliveryHistory'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CustomerDeliveryHistoryItem.fromJson)
          .toList(),
    );
  }
}
