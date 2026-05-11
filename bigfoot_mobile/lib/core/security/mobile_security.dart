import 'package:flutter/services.dart';

class MobileSecurity {
  static const MethodChannel _channel =
      MethodChannel('com.bigfoottrailers.mobile_security');

  static Future<bool> isDeviceRooted() async {
    final result = await _channel.invokeMethod<bool>('isDeviceRooted');
    return result ?? false;
  }

  static Future<void> enableSecureScreen() {
    return _channel.invokeMethod<void>('enableSecureScreen');
  }

  static Future<void> disableSecureScreen() {
    return _channel.invokeMethod<void>('disableSecureScreen');
  }
}
