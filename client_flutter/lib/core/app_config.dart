import 'dart:io';

import 'package:flutter/widgets.dart';

class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3601',
  );

  static const String target = String.fromEnvironment('APP_TARGET');

  static const String appVersion = '0.1.0';

  static bool isTv(BuildContext context) {
    if (target == 'tv') return true;
    if (target == 'phone') return false;
    final size = MediaQuery.sizeOf(context);
    return Platform.isAndroid && size.width >= 960 && size.height >= 540;
  }

  static String platform(BuildContext context) =>
      isTv(context) ? 'android-tv' : 'android-phone';

  static String get defaultPlatform => target == 'tv' ? 'android-tv' : 'android-phone';

  static String defaultDeviceName(BuildContext context) =>
      isTv(context) ? 'Android TV' : 'Android 手机';

  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
