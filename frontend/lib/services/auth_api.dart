import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/app_user.dart';
import '../models/find_login_id_result.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) {
    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$baseUrl$path');
  }

  Future<AppUser> createSession(String idToken) async {
    final response = await _client.post(
      _uri('/auth/session'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );

    final json = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_messageFrom(json, '로그인 세션을 만들 수 없습니다.'));
    }

    return AppUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<FindLoginIdResult> findLoginId(String email) async {
    final response = await _client.post(
      _uri('/auth/find-login-id'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    final json = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_messageFrom(json, 'ID를 찾을 수 없습니다.'));
    }

    return FindLoginIdResult.fromJson(json);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }

  String _messageFrom(Map<String, dynamic> json, String fallback) {
    final detail = json['detail'];
    if (detail is String && detail.isNotEmpty) {
      return detail;
    }
    return fallback;
  }
}
