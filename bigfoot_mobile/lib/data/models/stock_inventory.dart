// Stock inventory: trailers currently parked at each stock-location yard.
// Returned by `GET /deliveries/stock-inventory`, grouped by location.

class StockTrailer {
  /// Null for stock builds born at a yard (no delivery brought them there).
  /// The API surfaces these with deliveryId=null since 0ee94be.
  final int? deliveryId;
  final int trailerId;
  final String soNumber;
  final String? model;
  final String? series;
  final String? sizeFt;
  final bool isHot;
  final String? saleStatus;
  final String? customerName;
  final DateTime? deliveredAt;
  final String? deliveredBy;

  const StockTrailer({
    required this.deliveryId,
    required this.trailerId,
    required this.soNumber,
    this.model,
    this.series,
    this.sizeFt,
    this.isHot = false,
    this.saleStatus,
    this.customerName,
    this.deliveredAt,
    this.deliveredBy,
  });

  factory StockTrailer.fromJson(Map<String, dynamic> json) => StockTrailer(
        // tryParse handles the null case (yard-born stock) without throwing
        // a FormatException, and still falls back to null for malformed
        // payloads that slipped past the API.
        deliveryId: int.tryParse(json['deliveryId']?.toString() ?? ''),
        trailerId: int.parse(json['trailerId'].toString()),
        soNumber: (json['soNumber'] as String?) ?? '',
        model: json['model'] as String?,
        series: json['series'] as String?,
        sizeFt: json['sizeFt'] as String?,
        isHot: json['isHot'] as bool? ?? false,
        saleStatus: json['saleStatus'] as String?,
        customerName: json['customerName'] as String?,
        deliveredAt: json['deliveredAt'] != null
            ? DateTime.tryParse(json['deliveredAt'].toString())
            : null,
        deliveredBy: json['deliveredBy'] as String?,
      );
}

class StockLocationGroup {
  final int locationId;
  final String code;
  final String name;
  final String city;
  final String state;
  final int count;
  final List<StockTrailer> trailers;

  const StockLocationGroup({
    required this.locationId,
    required this.code,
    required this.name,
    required this.city,
    required this.state,
    required this.count,
    required this.trailers,
  });

  factory StockLocationGroup.fromJson(Map<String, dynamic> json) {
    final loc = (json['location'] as Map<String, dynamic>?) ?? const {};
    final trailers = ((json['trailers'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StockTrailer.fromJson)
        .toList();
    return StockLocationGroup(
      locationId: int.parse(loc['id'].toString()),
      code: (loc['code'] as String?) ?? '',
      name: (loc['name'] as String?) ?? '',
      city: (loc['city'] as String?) ?? '',
      state: (loc['state'] as String?) ?? '',
      count: (json['count'] as num?)?.toInt() ?? trailers.length,
      trailers: trailers,
    );
  }
}
