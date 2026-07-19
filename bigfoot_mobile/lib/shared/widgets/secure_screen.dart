import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/security/mobile_security.dart';

/// Wraps a sensitive screen (payroll / points) with Android's FLAG_SECURE so it
/// can't be screenshotted or screen-recorded.
///
/// Disabled in debug/dev builds so the app can be demoed and screen-recorded
/// end to end. Release builds (what employees run) keep the protection on.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  @override
  void initState() {
    super.initState();
    if (!kDebugMode) MobileSecurity.enableSecureScreen();
  }

  @override
  void dispose() {
    if (!kDebugMode) MobileSecurity.disableSecureScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
