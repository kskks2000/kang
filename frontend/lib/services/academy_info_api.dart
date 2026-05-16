import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

class AcademyInfoApi {
  AcademyInfoApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AcademyInfoBasicDataset> loadBasicInformation() async {
    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client.get(
      Uri.parse('$baseUrl/academy-info/basic'),
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AcademyInfoApiException(
        '대학알리미 API 프록시 응답이 올바르지 않습니다. (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const AcademyInfoApiException('대학알리미 API 응답 형식이 올바르지 않습니다.');
    }

    return AcademyInfoBasicDataset.fromJson(decoded);
  }
}

class AcademyInfoApiException implements Exception {
  const AcademyInfoApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AcademyInfoBasicDataset {
  const AcademyInfoBasicDataset({
    required this.status,
    required this.fetchedAt,
    required this.cached,
    required this.cacheSeconds,
    required this.source,
    required this.summary,
    required this.operations,
  });

  final String status;
  final String fetchedAt;
  final bool cached;
  final int cacheSeconds;
  final AcademyInfoSource source;
  final AcademyInfoSummary summary;
  final List<AcademyInfoOperationResult> operations;

  bool get hasErrors => summary.errorCount > 0;

  factory AcademyInfoBasicDataset.fromJson(Map<String, dynamic> json) {
    return AcademyInfoBasicDataset(
      status: json['status'] as String? ?? 'error',
      fetchedAt: json['fetchedAt'] as String? ?? '',
      cached: json['cached'] as bool? ?? false,
      cacheSeconds: json['cacheSeconds'] as int? ?? 0,
      source: AcademyInfoSource.fromJson(
        json['source'] as Map<String, dynamic>? ?? const {},
      ),
      summary: AcademyInfoSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      operations: (json['operations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AcademyInfoOperationResult.fromJson)
          .toList(growable: false),
    );
  }
}

class AcademyInfoSource {
  const AcademyInfoSource({
    required this.title,
    required this.provider,
    required this.sourceUrl,
    required this.serviceBaseUrl,
    required this.format,
  });

  final String title;
  final String provider;
  final String sourceUrl;
  final String serviceBaseUrl;
  final String format;

  factory AcademyInfoSource.fromJson(Map<String, dynamic> json) {
    return AcademyInfoSource(
      title: json['title'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      serviceBaseUrl: json['serviceBaseUrl'] as String? ?? '',
      format: json['format'] as String? ?? '',
    );
  }
}

class AcademyInfoSummary {
  const AcademyInfoSummary({
    required this.operationCount,
    required this.successCount,
    required this.errorCount,
    required this.totalRows,
    required this.latestComparisonYear,
    required this.latestNoticeYear,
  });

  final int operationCount;
  final int successCount;
  final int errorCount;
  final int totalRows;
  final String latestComparisonYear;
  final String latestNoticeYear;

  factory AcademyInfoSummary.fromJson(Map<String, dynamic> json) {
    return AcademyInfoSummary(
      operationCount: json['operationCount'] as int? ?? 0,
      successCount: json['successCount'] as int? ?? 0,
      errorCount: json['errorCount'] as int? ?? 0,
      totalRows: json['totalRows'] as int? ?? 0,
      latestComparisonYear: json['latestComparisonYear'] as String? ?? '',
      latestNoticeYear: json['latestNoticeYear'] as String? ?? '',
    );
  }
}

class AcademyInfoOperationResult {
  const AcademyInfoOperationResult({
    required this.group,
    required this.title,
    required this.endpoint,
    required this.description,
    required this.requiredParams,
    required this.optionalParams,
    required this.responseFields,
    required this.serviceUrl,
    required this.status,
    required this.resultCode,
    required this.resultMsg,
    required this.totalCount,
    required this.rowCount,
    required this.hasMore,
    required this.requestParams,
    required this.rows,
    required this.fields,
  });

  final String group;
  final String title;
  final String endpoint;
  final String description;
  final List<String> requiredParams;
  final List<String> optionalParams;
  final List<String> responseFields;
  final String serviceUrl;
  final String status;
  final String resultCode;
  final String resultMsg;
  final int totalCount;
  final int rowCount;
  final bool hasMore;
  final Map<String, String> requestParams;
  final List<Map<String, String>> rows;
  final List<String> fields;

  bool get isOk => status == 'ok';

  bool get isUniversityList =>
      endpoint.contains('University') || endpoint == 'getUniversityCode';

  bool get isYearList =>
      endpoint == 'getComparisonPubYear' || endpoint == 'getNoticeSvyYear';

  bool matches(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return true;
    }
    return group.toLowerCase().contains(trimmed) ||
        title.toLowerCase().contains(trimmed) ||
        endpoint.toLowerCase().contains(trimmed) ||
        description.toLowerCase().contains(trimmed) ||
        resultMsg.toLowerCase().contains(trimmed) ||
        rows.any(
          (row) =>
              row.values.any((value) => value.toLowerCase().contains(trimmed)),
        );
  }

  factory AcademyInfoOperationResult.fromJson(Map<String, dynamic> json) {
    return AcademyInfoOperationResult(
      group: json['group'] as String? ?? '',
      title: json['title'] as String? ?? '',
      endpoint: json['endpoint'] as String? ?? '',
      description: json['description'] as String? ?? '',
      requiredParams: _stringList(json['requiredParams']),
      optionalParams: _stringList(json['optionalParams']),
      responseFields: _stringList(json['responseFields']),
      serviceUrl: json['serviceUrl'] as String? ?? '',
      status: json['status'] as String? ?? 'error',
      resultCode: json['resultCode'] as String? ?? '',
      resultMsg: json['resultMsg'] as String? ?? '',
      totalCount: json['totalCount'] as int? ?? 0,
      rowCount: json['rowCount'] as int? ?? 0,
      hasMore: json['hasMore'] as bool? ?? false,
      requestParams: _stringMap(json['requestParams']),
      rows: (json['rows'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_stringMap)
          .toList(growable: false),
      fields: _stringList(json['fields']),
    );
  }

  static List<String> _stringList(Object? value) {
    return (value as List<dynamic>? ?? const [])
        .map((item) => item?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, String> _stringMap(Object? value) {
    final map = value as Map<String, dynamic>? ?? const {};
    return {
      for (final entry in map.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
  }
}
