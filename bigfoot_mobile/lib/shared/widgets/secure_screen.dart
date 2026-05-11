import 'package:flutter/material.dart';

import '../../core/security/mobile_security.dart';

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
    MobileSecurity.enableSecureScreen();
  }

  @override
  void dispose() {
    MobileSecurity.disableSecureScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
