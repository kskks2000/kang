import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import 'auth_api.dart';
import 'firebase_social_auth.dart';

class GoogleDriveApi {
  GoogleDriveApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<GoogleDriveSheetFile>> listSheetFiles({String query = ''}) async {
    final response = await _postJson('/drive/files', {
      'id_token': await _idToken(),
      'google_access_token':
          await FirebaseSocialAuth.requestGoogleDriveSheetsAccessToken(),
      'query': query.trim().isEmpty ? null : query.trim(),
      'page_size': 50,
    });
    final json = _decode(response);
    _throwIfFailed(response, json, 'Google Drive 파일을 불러오지 못했습니다.');
    final files = json['files'] as List<dynamic>? ?? const [];
    return files
        .whereType<Map<String, dynamic>>()
        .map(GoogleDriveSheetFile.fromJson)
        .toList(growable: false);
  }

  Future<GoogleDriveImportResult> importSheet(GoogleDriveSheetFile file) async {
    final response = await _postJson('/drive/import', {
      'id_token': await _idToken(),
      'google_access_token':
          await FirebaseSocialAuth.requestGoogleDriveSheetsAccessToken(),
      'file_id': file.id,
      'file_name': file.name,
      'max_rows': 1000,
    });
    final json = _decode(response);
    _throwIfFailed(response, json, 'Google Sheet를 가져오지 못했습니다.');
    return GoogleDriveImportResult.fromJson(json);
  }

  Future<List<GoogleDriveTableRowData>> listRows({String search = ''}) async {
    final response = await _postJson('/drive/rows', {
      'id_token': await _idToken(),
      'search': search.trim().isEmpty ? null : search.trim(),
      'limit': 500,
    });
    final json = _decode(response);
    _throwIfFailed(response, json, '저장된 Google Drive 데이터를 불러오지 못했습니다.');
    final rows = json['rows'] as List<dynamic>? ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(GoogleDriveTableRowData.fromJson)
        .toList(growable: false);
  }

  Future<String> _idToken() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const ApiException('로그인 토큰이 없습니다. 다시 로그인해 주세요.');
    }
    return token;
  }

  Uri _uri(String path) {
    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$baseUrl$path');
  }

  Future<http.Response> _postJson(String path, Map<String, dynamic> body) {
    return _client.post(
      _uri(path),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  void _throwIfFailed(
    http.Response response,
    Map<String, dynamic> json,
    String fallback,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final detail = json['detail'];
    throw ApiException(
      detail is String && detail.isNotEmpty ? detail : fallback,
    );
  }
}

class GoogleDriveSheetFile {
  const GoogleDriveSheetFile({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.webViewLink,
  });

  final String id;
  final String name;
  final String? modifiedTime;
  final String? webViewLink;

  factory GoogleDriveSheetFile.fromJson(Map<String, dynamic> json) {
    return GoogleDriveSheetFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled sheet',
      modifiedTime: json['modified_time'] as String?,
      webViewLink: json['web_view_link'] as String?,
    );
  }
}

class GoogleDriveImportResult {
  const GoogleDriveImportResult({
    required this.fileId,
    required this.fileName,
    required this.importedRows,
    required this.sheetCount,
  });

  final String fileId;
  final String fileName;
  final int importedRows;
  final int sheetCount;

  factory GoogleDriveImportResult.fromJson(Map<String, dynamic> json) {
    return GoogleDriveImportResult(
      fileId: json['file_id'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      importedRows: json['imported_rows'] as int? ?? 0,
      sheetCount: json['sheet_count'] as int? ?? 0,
    );
  }
}

class GoogleDriveTableRowData {
  const GoogleDriveTableRowData({
    required this.id,
    this.driveName,
    this.tabName,
    required this.values,
  });

  final String id;
  final String? driveName;
  final String? tabName;
  final List<String?> values;

  factory GoogleDriveTableRowData.fromJson(Map<String, dynamic> json) {
    return GoogleDriveTableRowData(
      id: json['id'] as String? ?? '',
      driveName: json['drivename'] as String?,
      tabName: json['tabname'] as String?,
      values: [
        for (var index = 1; index <= 20; index++)
          json['text${index.toString().padLeft(2, '0')}'] as String?,
      ],
    );
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    final haystack = [
      driveName,
      tabName,
      ...values,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(normalized);
  }
}
