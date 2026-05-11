/// A trailer yard / factory location served by the API.
///
/// `shortLabel` is the compact code (Mul, Jax, VA, GA, TAL) used in chip
/// pickers; `name` / `city` / `state` are the long-form display strings.
class Location {
  final int id;
  final String code;
  final String name;
  final String? city;
  final String? state;
  final String? shortLabel;
  final bool isFactory;
  final bool isActive;

  const Location({
    required this.id,
    required this.code,
    required this.name,
    this.city,
    this.state,
    this.shortLabel,
    this.isFactory = false,
    this.isActive = true,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      city: json['city'] as String?,
      state: json['state'] as String?,
      shortLabel: json['shortLabel'] as String?,
      isFactory: json['isFactory'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  /// Best-effort label for chip/button UIs — falls back to code/name when the
  /// backend hasn't been migrated yet.
  String get chipLabel {
    final s = shortLabel?.trim();
    if (s != null && s.isNotEmpty) return s;
    if (code.isNotEmpty) return code;
    return name;
  }

  /// Long-form "City, ST" for subtitles and tooltips.
  String get cityState {
    final c = city?.trim() ?? '';
    final s = state?.trim() ?? '';
    if (c.isNotEmpty && s.isNotEmpty) return '$c, $s';
    if (c.isNotEmpty) return c;
    return s;
  }
}
