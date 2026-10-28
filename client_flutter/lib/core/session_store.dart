import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class SessionStore {
  SessionStore._(this._prefs);

  static const _kBaseUrl = 'server_base_url';
  static const _kAccessToken = 'auth_access_token';
  static const _kRefreshToken = 'auth_refresh_token';
  static const _kDeviceId = 'device_id';
  static const _kUser = 'auth_user';

  final SharedPreferences _prefs;

  static Future<SessionStore> open() async =>
      SessionStore._(await SharedPreferences.getInstance());

  String get baseUrl => _prefs.getString(_kBaseUrl) ?? '';
  String? get accessToken => _prefs.getString(_kAccessToken);
  String? get refreshToken => _prefs.getString(_kRefreshToken);
  String? get deviceId => _prefs.getString(_kDeviceId);

  User? get user {
    final raw = _prefs.getString(_kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBaseUrl(String value) => _prefs.setString(_kBaseUrl, value);

  Future<void> saveDeviceId(String value) => _prefs.setString(_kDeviceId, value);

  Future<void> saveSession(AuthSession session) async {
    await _prefs.setString(_kAccessToken, session.accessToken);
    await _prefs.setString(_kRefreshToken, session.refreshToken);
    await _prefs.setString(_kUser, jsonEncode(session.user.toJson()));
  }

  Future<void> clearSession() async {
    await _prefs.remove(_kAccessToken);
    await _prefs.remove(_kRefreshToken);
    await _prefs.remove(_kUser);
  }

  String newDeviceId(String platform) {
    final prefix = platform == 'android-tv' ? 'tv' : 'phone';
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final rand = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-$stamp$rand';
  }
}
