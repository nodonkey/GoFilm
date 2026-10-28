import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'app_config.dart';
import 'session_store.dart';

class AuthController extends ChangeNotifier {
  AuthController(this.api, this.store);

  final ApiClient api;
  final SessionStore store;

  bool _initialized = false;
  bool _busy = false;
  bool _refreshing = false;
  String? _error;
  String? _accessToken;
  String? _refreshToken;
  User? _user;
  String _deviceId = '';
  Future<bool>? _refreshFuture;

  bool get initialized => _initialized;
  bool get busy => _busy;
  String? get error => _error;
  User? get user => _user;
  String get deviceId => _deviceId;
  String get baseUrl => api.baseUrl;
  bool get isLoggedIn => _refreshToken != null && _user != null;

  Future<void> init() async {
    if (_initialized) return;
    final savedBase = store.baseUrl;
    api.baseUrl = savedBase.isEmpty ? AppConfig.apiBaseUrl : savedBase;
    _accessToken = store.accessToken;
    _refreshToken = store.refreshToken;
    _user = store.user;
    _deviceId = store.deviceId ?? store.newDeviceId(AppConfig.defaultPlatform);
    if (store.deviceId == null) {
      await store.saveDeviceId(_deviceId);
    }
    api.accessToken = _accessToken;
    api.onUnauthorized = _refreshSilently;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setBaseUrl(String raw, {bool dropSession = true}) async {
    final normalized = AppConfig.normalizeBaseUrl(raw);
    if (normalized.isEmpty) return;
    if (normalized == api.baseUrl) return;
    api.baseUrl = normalized;
    await store.saveBaseUrl(normalized);
    if (dropSession && isLoggedIn) {
      await clearSession();
    }
    notifyListeners();
  }

  Future<void> login({
    required String baseUrl,
    required String account,
    required String password,
    required String platform,
    required String deviceName,
  }) async {
    await _prepare(baseUrl);
    _setBusy(true);
    try {
      final data = await api.post(
        '/api/v1/auth/login',
        body: {
          'account': account.trim(),
          'password': password,
          'deviceId': _deviceId,
          'deviceName': deviceName,
          'platform': platform,
          'appVersion': AppConfig.appVersion,
        },
        retryOnUnauthorized: false,
      );
      await _applySession(AuthSession.fromJson(_map(data)));
    } catch (e) {
      _error = friendlyError(e);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> register({
    required String baseUrl,
    required String userName,
    required String password,
    required String nickName,
    required String platform,
    required String deviceName,
  }) async {
    await _prepare(baseUrl);
    _setBusy(true);
    try {
      final data = await api.post(
        '/api/v1/auth/register',
        body: {
          'userName': userName.trim(),
          'password': password,
          'nickName': nickName.trim(),
          'deviceId': _deviceId,
          'deviceName': deviceName,
          'platform': platform,
          'appVersion': AppConfig.appVersion,
        },
        retryOnUnauthorized: false,
      );
      await _applySession(AuthSession.fromJson(_map(data)));
    } catch (e) {
      _error = friendlyError(e);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    try {
      await api.post('/api/v1/auth/logout', body: const {}, auth: true);
    } catch (_) {
      // 本地登出优先，忽略网络错误
    }
    await clearSession();
  }

  Future<int> logoutAll() async {
    try {
      final data = await api.post('/api/v1/auth/logout-all', body: const {}, auth: true);
      return _map(data)['revoked'] as int? ?? 0;
    } finally {
      await clearSession();
    }
  }

  Future<List<DeviceSession>> devices() async {
    final data = await api.get('/api/v1/auth/devices', auth: true);
    final items = (_map(data)['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => DeviceSession.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> revokeDevice(String deviceId) async {
    await api.delete('/api/v1/auth/devices/$deviceId', auth: true);
  }

  // ---------------------------------------------------------------- 扫码登录

  Future<QrCreateResult> createQr({
    required String platform,
    required String deviceName,
  }) async {
    final data = await api.post(
      '/api/v1/auth/qr/create',
      body: {
        'deviceId': _deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'appVersion': AppConfig.appVersion,
      },
      retryOnUnauthorized: false,
    );
    return QrCreateResult.fromJson(_map(data));
  }

  Future<QrPollResult> pollQr(String qid, String pollToken) async {
    final data = await api.get(
      '/api/v1/auth/qr/poll',
      query: {'qid': qid, 'token': pollToken},
    );
    return QrPollResult.fromJson(_map(data));
  }

  Future<void> scanQr(String qid) async {
    await api.post('/api/v1/auth/qr/scan', body: {'qid': qid}, auth: true);
  }

  Future<void> confirmQr(String qid) async {
    await api.post('/api/v1/auth/qr/confirm', body: {'qid': qid}, auth: true);
  }

  Future<void> applyQrAuth(AuthSession session) => _applySession(session);

  // ---------------------------------------------------------------- 内部逻辑

  Future<void> _prepare(String rawBaseUrl) async {
    final normalized = AppConfig.normalizeBaseUrl(rawBaseUrl);
    if (normalized.isEmpty) {
      throw ApiException(message: '请填写服务器地址');
    }
    if (normalized != api.baseUrl) {
      api.baseUrl = normalized;
      await store.saveBaseUrl(normalized);
    }
  }

  Future<void> _applySession(AuthSession session) async {
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    _user = session.user;
    if (session.deviceId.isNotEmpty) {
      _deviceId = session.deviceId;
      await store.saveDeviceId(session.deviceId);
    }
    api.accessToken = session.accessToken;
    await store.saveSession(session);
    _error = null;
    notifyListeners();
  }

  Future<bool> _refreshSilently() {
    final pending = _refreshFuture;
    if (pending != null) return pending;
    final future = _refreshTokens();
    _refreshFuture = future;
    return future.whenComplete(() => _refreshFuture = null);
  }

  Future<bool> _refreshTokens() async {
    if (_refreshing) return false;
    final token = _refreshToken;
    if (token == null || token.isEmpty) return false;
    _refreshing = true;
    try {
      final data = await api.post(
        '/api/v1/auth/refresh',
        body: {'refreshToken': token},
        retryOnUnauthorized: false,
      );
      await _applySession(AuthSession.fromJson(_map(data)));
      return true;
    } on ApiException catch (e) {
      if (e.unauthorized) {
        await clearSession();
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    api.accessToken = null;
    await store.clearSession();
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    if (value) _error = null;
    notifyListeners();
  }
}

Map<String, dynamic> _map(dynamic data) =>
    (data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

String friendlyError(Object error) {
  if (error is ApiException) return error.message;
  return '操作失败，请稍后重试';
}
