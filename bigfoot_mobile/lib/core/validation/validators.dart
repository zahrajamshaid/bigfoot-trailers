/// Reusable form-field validators with user-friendly messages.
///
/// All validators follow the Flutter `FormFieldValidator` contract: return
/// `null` when the value is acceptable, or a non-empty error string to
/// display inline under the field.
///
/// `required*` variants reject empty/whitespace. `optional*` variants accept
/// empty input but validate the format when something is typed.
library;

class Validators {
  Validators._();

  /// RFC-ish email pattern. Strict enough to reject obvious typos
  /// ("foo", "foo@", "foo@bar", "foo@bar.") while still permissive enough
  /// for real-world addresses (plus-tags, dots, etc).
  static final RegExp _emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+"
    r'@[a-zA-Z0-9]'
    r'(?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  /// Allows digits, spaces, parens, dashes, dots, and a leading "+".
  /// Requires at least 7 digits total — enough to reject "12" but not so
  /// strict it rejects international formats.
  static final RegExp _phoneRegex = RegExp(r'^[+\d][\d\s().\-]{6,}$');

  static String? required(String? value, {String fieldName = 'this field'}) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter $fieldName';
    }
    return null;
  }

  static String? requiredEmail(String? value) {
    final missing = required(value, fieldName: 'your email');
    if (missing != null) return missing;
    if (!_emailRegex.hasMatch(value!.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? optionalEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!_emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? requiredPhone(String? value) {
    final missing = required(value, fieldName: 'a phone number');
    if (missing != null) return missing;
    return _checkPhone(value!);
  }

  static String? optionalPhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _checkPhone(value);
  }

  static String? _checkPhone(String value) {
    final trimmed = value.trim();
    if (!_phoneRegex.hasMatch(trimmed)) {
      return 'Please enter a valid phone number';
    }
    final digitCount = trimmed.replaceAll(RegExp(r'\D'), '').length;
    if (digitCount < 7 || digitCount > 15) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  static String? password(String? value, {int minLength = 8}) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < minLength) {
      return 'Password must be at least $minLength characters';
    }
    return null;
  }

  /// Validator for an "optional new password" field (e.g. edit-user form
  /// where leaving it blank means "don't change"). Empty is OK; if typed,
  /// enforce the min-length rule.
  static String? optionalPassword(String? value, {int minLength = 8}) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.length < minLength) {
      return 'Password must be at least $minLength characters';
    }
    return null;
  }

  static String? requiredPositiveNumber(
    String? value, {
    String fieldName = 'a positive number',
  }) {
    final missing = required(value, fieldName: fieldName);
    if (missing != null) return missing;
    final parsed = double.tryParse(value!.trim());
    if (parsed == null) return 'Please enter a valid number';
    if (parsed <= 0) return 'Please enter a number greater than zero';
    return null;
  }

  static String? requiredPositiveInt(
    String? value, {
    String fieldName = 'a whole number',
  }) {
    final missing = required(value, fieldName: fieldName);
    if (missing != null) return missing;
    final parsed = int.tryParse(value!.trim());
    if (parsed == null) return 'Please enter a valid whole number';
    if (parsed <= 0) return 'Please enter a number greater than zero';
    return null;
  }

  /// Validator for optional numeric ID fields (e.g. department/location ID).
  /// Empty is OK; non-empty must be a positive integer.
  static String? optionalPositiveInt(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Please enter a valid whole number';
    if (parsed <= 0) return 'Please enter a number greater than zero';
    return null;
  }

  static String? minLength(String? value, int min, {String? fieldName}) {
    final label = fieldName ?? 'this field';
    if (value == null || value.trim().isEmpty) {
      return 'Please enter $label';
    }
    if (value.trim().length < min) {
      return '$label must be at least $min characters';
    }
    return null;
  }

  /// Compose multiple validators; returns the first non-null error.
  static String? Function(String?) compose(
    List<String? Function(String?)> validators,
  ) {
    return (value) {
      for (final v in validators) {
        final result = v(value);
        if (result != null) return result;
      }
      return null;
    };
  }
}
