import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException({
    required this.message,
    this.status = 0,
    this.code = 0,
  });

  final String message;
  final int status;
  final int code;

  bool get unauthorized =>
      status == 401 || code == 40100 || code == 40101 || code == 40102;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({this.baseUrl = '', http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  String baseUrl;
  String? accessToken;
  Future<bool> Function()? onUnauthorized;

  static const Duration _timeout = Duration(seconds: 20);

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = false,
  }) =>
      _send('GET', path, query: query, auth: auth);

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    bool retryOnUnauthorized = true,
  }) =>
      _send('POST', path, body: body, auth: auth, retryOnUnauthorized: retryOnUnauthorized);

  Future<dynamic> delete(
    String path, {
    bool auth = false,
  }) =>
      _send('DELETE', path, auth: auth);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    bool auth = false,
    bool retryOnUnauthorized = true,
  }) async {
    var response = await _raw(method, path, query: query, body: body, auth: auth);
    if (response.statusCode == 401 &&
        auth &&
        retryOnUnauthorized &&
        onUnauthorized != null) {
      final refreshed = await onUnauthorized!();
      if (refreshed) {
        response = await _raw(method, path, query: query, body: body, auth: auth);
      }
    }
    return _decode(response);
  }

  Future<http.Response> _raw(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    required bool auth,
  }) async {
    final uri = _buildUri(path, query);
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    if (auth && accessToken != null && accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    final encoded = body == null ? null : jsonEncode(body);
    try {
      switch (method) {
        case 'POST':
          return await _http.post(uri, headers: headers, body: encoded).timeout(_timeout);
        case 'DELETE':
          return await _http.delete(uri, headers: headers).timeout(_timeout);
        default:
          return await _http.get(uri, headers: headers).timeout(_timeout);
      }
    } on TimeoutException {
      throw ApiException(message: '请求超时，请检查服务器地址');
    } catch (_) {
      throw ApiException(message: '无法连接服务器，请检查网络与地址');
    }
  }

  Uri _buildUri(String path, Map<String, dynamic>? query) {
    final base = baseUrl;
    final uri = Uri.parse('$base$path');
    if (query == null || query.isEmpty) return uri;
    final params = <String, String>{};
    query.forEach((key, value) {
      if (value != null) params[key] = value.toString();
    });
    return uri.replace(queryParameters: {...uri.queryParameters, ...params});
  }

  dynamic _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      if (response.statusCode >= 400) {
        throw ApiException(
          message: '服务器响应异常 (${response.statusCode})',
          status: response.statusCode,
        );
      }
      return null;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException(
        message: '服务器响应格式异常 (${response.statusCode})',
        status: response.statusCode,
      );
    }
    if (decoded is! Map) {
      throw ApiException(
        message: '服务器响应格式异常 (${response.statusCode})',
        status: response.statusCode,
      );
    }
    final code = int.tryParse('${decoded['code']}') ?? -1;
    if (code != 0) {
      throw ApiException(
        message: '${decoded['msg'] ?? '请求失败'}',
        status: response.statusCode,
        code: code,
      );
    }
    return decoded['data'];
  }

  void close() => _http.close();
}
