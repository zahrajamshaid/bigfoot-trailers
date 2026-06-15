import 'package:json_annotation/json_annotation.dart';

part 'trailer.g.dart';

// Prisma serializes Decimal fields as strings — parse either String or num.
double? _parseDecimalField(dynamic v) =>
    v == null ? null : double.tryParse(v.toString());

@JsonSerializable()
class Trailer {
  final int id;
  final String soNumber;
  final String? vinNumber;
  final int? trailerModelId;
  final int? customerId;
  final int? currentLocationId;
  /// The yard a stock build is destined to ship to. Captured at trailer
  /// creation; the trailer stays at the factory until a stack_to_location
  /// delivery completes. Null for customer trailers.
  final int? intendedStockLocationId;
  final int? createdByUserId;
  final String? color;
  @JsonKey(name: 'sizeFt')
  final String? size;
  final String? optionsNotes;
  final String? specialNote;
  final String? qbSoPdfStorageKey;
  /// Order date from the QB packing-slip PDF ("Date:" field). Backfilled
  /// from Spaces; date-only (no time-of-day). Surfaced on the trailer
  /// detail screen so production knows when a build was ordered.
  final DateTime? qbSoDate;
  final String status;

  /// Sale state, independent of the production [status]:
  /// `available` · `sale_pending` · `sold`. A trailer linked to a customer
  /// is always `sold`.
  @JsonKey(defaultValue: 'available')
  final String saleStatus;

  /// Free-text buyer name captured when a stock / no-customer trailer is
  /// marked sold. Null for trailers that carry a [customer] record instead.
  final String? soldToName;
  final int globalPriority;
  final bool isStockBuild;
  final bool isHot;
  final bool customerLocked;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Expanded relations (may be null)
  final TrailerModelInfo? trailerModel;
  final CustomerInfo? customer;
  final LocationInfo? currentLocation;
  final LocationInfo? intendedStockLocation;
  final List<TrailerAddon>? addons;
  final List<ProductionStepSummary>? productionSteps;

  const Trailer({
    required this.id,
    required this.soNumber,
    this.vinNumber,
    this.trailerModelId,
    this.customerId,
    this.currentLocationId,
    this.intendedStockLocationId,
    this.createdByUserId,
    this.color,
    this.size,
    this.optionsNotes,
    this.specialNote,
    this.qbSoPdfStorageKey,
    this.qbSoDate,
    required this.status,
    this.saleStatus = 'available',
    this.soldToName,
    this.globalPriority = 9999,
    this.isStockBuild = false,
    this.isHot = false,
    this.customerLocked = false,
    this.createdAt,
    this.updatedAt,
    this.trailerModel,
    this.customer,
    this.currentLocation,
    this.intendedStockLocation,
    this.addons,
    this.productionSteps,
  });

  factory Trailer.fromJson(Map<String, dynamic> json) =>
      _$TrailerFromJson(json);
  Map<String, dynamic> toJson() => _$TrailerToJson(this);
}

@JsonSerializable()
class LocationInfo {
  final int id;
  final String code;
  final String name;
  final String? city;
  final String? state;
  final String? shortLabel;

  const LocationInfo({
    required this.id,
    required this.code,
    required this.name,
    this.city,
    this.state,
    this.shortLabel,
  });

  factory LocationInfo.fromJson(Map<String, dynamic> json) =>
      _$LocationInfoFromJson(json);
  Map<String, dynamic> toJson() => _$LocationInfoToJson(this);

  /// Best-effort chip label — short code if the backend has it, else the code,
  /// else the first three letters of the city.
  String get chipLabel {
    final s = shortLabel?.trim();
    if (s != null && s.isNotEmpty) return s;
    if (code.isNotEmpty) return code;
    final c = city?.trim();
    if (c != null && c.isNotEmpty) return c.substring(0, c.length < 3 ? c.length : 3);
    return name;
  }
}

@JsonSerializable()
class TrailerModelInfo {
  final int id;
  final String code;
  final String displayName;
  final String series;
  final String? weightRating;

  const TrailerModelInfo({
    required this.id,
    required this.code,
    required this.displayName,
    required this.series,
    this.weightRating,
  });

  factory TrailerModelInfo.fromJson(Map<String, dynamic> json) =>
      _$TrailerModelInfoFromJson(json);
  Map<String, dynamic> toJson() => _$TrailerModelInfoToJson(this);
}

@JsonSerializable()
class CustomerInfo {
  final int id;
  final String name;
  final String? company;
  final String? smsPhone;
  final String? email;
  final String customerType;

  const CustomerInfo({
    required this.id,
    required this.name,
    this.company,
    this.smsPhone,
    this.email,
    required this.customerType,
  });

  factory CustomerInfo.fromJson(Map<String, dynamic> json) =>
      _$CustomerInfoFromJson(json);
  Map<String, dynamic> toJson() => _$CustomerInfoToJson(this);
}

@JsonSerializable()
class TrailerAddon {
  final int id;
  final int? trailerId;
  final String addonName;
  final String? notes;
  final DateTime? addedAt;

  const TrailerAddon({
    required this.id,
    this.trailerId,
    required this.addonName,
    this.notes,
    this.addedAt,
  });

  factory TrailerAddon.fromJson(Map<String, dynamic> json) =>
      _$TrailerAddonFromJson(json);
  Map<String, dynamic> toJson() => _$TrailerAddonToJson(this);
}

class ProductionStepSummary {
  final int id;
  final int stepOrder;
  final String status;
  final int departmentId;
  final String? departmentCode;
  final String? departmentName;
  final bool isRework;
  final int reworkCount;
  final double? pointsAwarded;
  final int? completedByUserId;
  final DateTime? completedAt;
  final DateTime? becameActiveAt;

  const ProductionStepSummary({
    required this.id,
    required this.stepOrder,
    required this.status,
    required this.departmentId,
    this.departmentCode,
    this.departmentName,
    this.isRework = false,
    this.reworkCount = 0,
    this.pointsAwarded,
    this.completedByUserId,
    this.completedAt,
    this.becameActiveAt,
  });

  factory ProductionStepSummary.fromJson(Map<String, dynamic> json) {
    final dept = json['department'] as Map<String, dynamic>?;
    final completedByUser = json['completedByUser'] as Map<String, dynamic>?;
    // Some endpoints return departmentId at the top level, others only as
    // department.id — fall back so either response shape parses cleanly.
    final departmentId = (json['departmentId'] as num?)?.toInt() ??
        (dept?['id'] as num?)?.toInt() ??
        0;
    return ProductionStepSummary(
      id: (json['id'] as num).toInt(),
      stepOrder: (json['stepOrder'] as num).toInt(),
      status: json['status'] as String,
      departmentId: departmentId,
      departmentCode: dept?['code'] as String? ?? json['departmentCode'] as String?,
      departmentName: dept?['displayName'] as String? ?? json['departmentName'] as String?,
      isRework: json['isRework'] as bool? ?? false,
      reworkCount: (json['reworkCount'] as num?)?.toInt() ?? 0,
      pointsAwarded: _parseDecimalField(json['pointsAwarded']),
      completedByUserId: completedByUser != null ? (completedByUser['id'] as num?)?.toInt() : null,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'].toString()) : null,
      becameActiveAt: json['becameActiveAt'] != null ? DateTime.tryParse(json['becameActiveAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'stepOrder': stepOrder,
    'status': status,
    'departmentId': departmentId,
    'departmentCode': departmentCode,
    'departmentName': departmentName,
    'isRework': isRework,
    'reworkCount': reworkCount,
    'pointsAwarded': pointsAwarded,
    'completedByUserId': completedByUserId,
    'completedAt': completedAt?.toIso8601String(),
    'becameActiveAt': becameActiveAt?.toIso8601String(),
  };
}
