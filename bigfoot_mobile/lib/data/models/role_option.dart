/// One entry from `GET /users/roles` — the admin role picker reads these.
///
/// `value` is the enum value the API expects on user create/update (e.g.
/// `parts`, `production_manager`). `label` is the English display string
/// from the backend; locales that have a translation override it client-
/// side via `AppLocalizations`.
class RoleOption {
  final String value;
  final String label;

  const RoleOption({required this.value, required this.label});

  factory RoleOption.fromJson(Map<String, dynamic> json) {
    return RoleOption(
      value: json['value'] as String,
      label: json['label'] as String? ?? json['value'] as String,
    );
  }
}
