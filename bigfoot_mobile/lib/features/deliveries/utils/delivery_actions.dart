import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/delivery.dart';

/// Device-level actions a driver can take on a delivery — open the destination
/// in Google Maps and text the customer. Both leave the app via the OS, so the
/// caller only needs to surface a friendly message when they return `false`.

/// Builds a human-readable destination string for a delivery, or `null` when
/// the delivery has neither a yard nor a custom address.
String? deliveryDestinationQuery(Delivery d) {
  final loc = d.destinationLocation;
  if (loc != null) {
    final parts = <String>[
      if ((loc.address ?? '').trim().isNotEmpty) loc.address!.trim(),
      loc.name.trim(),
      if ((loc.city ?? '').trim().isNotEmpty) loc.city!.trim(),
      if ((loc.state ?? '').trim().isNotEmpty) loc.state!.trim(),
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }
  final custom = d.customerDeliveryAddress?.trim();
  return (custom == null || custom.isEmpty) ? null : custom;
}

/// Opens the delivery destination in Google Maps (or the browser as a
/// fallback). Returns `false` if there is no destination to navigate to or the
/// OS could not handle the request.
Future<bool> openDeliveryInMaps(Delivery d) async {
  final query = deliveryDestinationQuery(d);
  if (query == null) return false;
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
  );
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The number to text for a delivery — the per-delivery contact phone entered
/// when the delivery was created, falling back to the trailer customer's
/// number. Returns `null` when neither is available.
String? deliveryContactPhone(Delivery d) {
  final contact = d.contactPhone?.trim();
  if (contact != null && contact.isNotEmpty) return contact;
  final customer = d.trailer?.customer?.smsPhone?.trim();
  return (customer == null || customer.isEmpty) ? null : customer;
}

/// Builds an `sms:<phone>?body=<msg>` URI that iOS Messages will accept.
///
/// We intentionally hand-roll the query instead of using `Uri(scheme:, path:,
/// queryParameters: {...})`. `queryParameters` applies `application/x-www-form-
/// urlencoded` encoding, which turns spaces into `+`. iOS Messages does NOT
/// decode `+` back to a space — it renders the body verbatim as
/// "Hi,+this+is+your+...". `Uri.encodeComponent` uses `%20` for spaces, which
/// iOS handles correctly. Android Messages handles either, so this is the
/// safe form for both platforms.
Uri _smsUri(String phone, String body) =>
    Uri.parse('sms:$phone?body=${Uri.encodeComponent(body)}');

/// Opens the device SMS app addressed to the delivery's contact, pre-filled
/// with a starter message the driver can edit. Returns `false` when there is
/// no phone number on file.
Future<bool> textDeliveryCustomer(Delivery d) async {
  final phone = deliveryContactPhone(d);
  if (phone == null) return false;
  final body =
      'Hi, this is your BigFoot driver for trailer ${d.soNumber}. ';
  return launchUrl(_smsUri(phone, body));
}

/// Opens the device SMS app to tell the customer their trailer is ready to be
/// picked up at the factory. Returns `false` when no phone number is on file.
Future<bool> textCustomerReadyForPickup(Delivery d) async {
  final phone = deliveryContactPhone(d);
  if (phone == null) return false;
  final body =
      'Hi, your BigFoot trailer ${d.soNumber} is ready for pickup at the '
      'factory. Please contact us to arrange collection.';
  return launchUrl(_smsUri(phone, body));
}

/// Whether the delivery has a phone number available to text.
bool deliveryHasCustomerPhone(Delivery d) => deliveryContactPhone(d) != null;
