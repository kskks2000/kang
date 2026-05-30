import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

class SubwayApi {
  SubwayApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<SubwayOverviewDataset> loadOverview({
    required String station,
    required String line,
  }) async {
    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$baseUrl/subway/overview',
    ).replace(queryParameters: {'station': station, 'line': line});
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SubwayApiException('지하철 정보를 불러오지 못했습니다. (${response.statusCode})');
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw const SubwayApiException('지하철 API가 JSON 응답을 반환하지 않았습니다.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const SubwayApiException('지하철 API 응답을 해석하지 못했습니다.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SubwayApiException('지하철 API 응답 형식이 올바르지 않습니다.');
    }

    return SubwayOverviewDataset.fromJson(decoded);
  }
}

class SubwayApiException implements Exception {
  const SubwayApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SubwayOverviewDataset {
  const SubwayOverviewDataset({
    required this.status,
    required this.fetchedAt,
    required this.cached,
    required this.cacheSeconds,
    required this.source,
    required this.summary,
    required this.arrivals,
    required this.trains,
    required this.errors,
  });

  final String status;
  final String fetchedAt;
  final bool cached;
  final int cacheSeconds;
  final SubwaySource source;
  final SubwaySummary summary;
  final List<SubwayArrival> arrivals;
  final List<SubwayTrainPosition> trains;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;

  factory SubwayOverviewDataset.fromJson(Map<String, dynamic> json) {
    return SubwayOverviewDataset(
      status: json['status'] as String? ?? 'error',
      fetchedAt: json['fetchedAt'] as String? ?? '',
      cached: json['cached'] as bool? ?? false,
      cacheSeconds: json['cacheSeconds'] as int? ?? 0,
      source: SubwaySource.fromJson(
        json['source'] as Map<String, dynamic>? ?? const {},
      ),
      summary: SubwaySummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      arrivals: (json['arrivals'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SubwayArrival.fromJson)
          .toList(growable: false),
      trains: (json['trains'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SubwayTrainPosition.fromJson)
          .toList(growable: false),
      errors: (json['errors'] as List<dynamic>? ?? const [])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class SubwaySource {
  const SubwaySource({
    required this.title,
    required this.provider,
    required this.arrivalUrl,
    required this.positionUrl,
    required this.description,
  });

  final String title;
  final String provider;
  final String arrivalUrl;
  final String positionUrl;
  final String description;

  factory SubwaySource.fromJson(Map<String, dynamic> json) {
    return SubwaySource(
      title: json['title'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      arrivalUrl: json['arrivalUrl'] as String? ?? '',
      positionUrl: json['positionUrl'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

class SubwaySummary {
  const SubwaySummary({
    required this.station,
    required this.line,
    required this.lineColor,
    required this.arrivalCount,
    required this.trainCount,
    required this.keyMode,
    required this.favoriteStations,
  });

  final String station;
  final String line;
  final String lineColor;
  final int arrivalCount;
  final int trainCount;
  final String keyMode;
  final List<SubwayFavoriteStation> favoriteStations;

  factory SubwaySummary.fromJson(Map<String, dynamic> json) {
    return SubwaySummary(
      station: json['station'] as String? ?? '',
      line: json['line'] as String? ?? '',
      lineColor: json['lineColor'] as String? ?? '',
      arrivalCount: json['arrivalCount'] as int? ?? 0,
      trainCount: json['trainCount'] as int? ?? 0,
      keyMode: json['keyMode'] as String? ?? '',
      favoriteStations: (json['favoriteStations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SubwayFavoriteStation.fromJson)
          .toList(growable: false),
    );
  }
}

class SubwayFavoriteStation {
  const SubwayFavoriteStation({
    required this.station,
    required this.line,
    required this.label,
  });

  final String station;
  final String line;
  final String label;

  factory SubwayFavoriteStation.fromJson(Map<String, dynamic> json) {
    return SubwayFavoriteStation(
      station: json['station'] as String? ?? '',
      line: json['line'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }
}

class SubwayArrival {
  const SubwayArrival({
    required this.line,
    required this.lineColor,
    required this.station,
    required this.direction,
    required this.destination,
    required this.trainLine,
    required this.arrivalMessage,
    required this.arrivalDetail,
    required this.etaSeconds,
    required this.status,
    required this.trainNo,
    required this.receivedAt,
    required this.terminalStation,
  });

  final String line;
  final String lineColor;
  final String station;
  final String direction;
  final String destination;
  final String trainLine;
  final String arrivalMessage;
  final String arrivalDetail;
  final int? etaSeconds;
  final String status;
  final String trainNo;
  final String receivedAt;
  final String terminalStation;

  factory SubwayArrival.fromJson(Map<String, dynamic> json) {
    return SubwayArrival(
      line: json['line'] as String? ?? '',
      lineColor: json['lineColor'] as String? ?? '',
      station: json['station'] as String? ?? '',
      direction: json['direction'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      trainLine: json['trainLine'] as String? ?? '',
      arrivalMessage: json['arrivalMessage'] as String? ?? '',
      arrivalDetail: json['arrivalDetail'] as String? ?? '',
      etaSeconds: json['etaSeconds'] as int?,
      status: json['status'] as String? ?? '',
      trainNo: json['trainNo'] as String? ?? '',
      receivedAt: json['receivedAt'] as String? ?? '',
      terminalStation: json['terminalStation'] as String? ?? '',
    );
  }
}

class SubwayTrainPosition {
  const SubwayTrainPosition({
    required this.line,
    required this.lineColor,
    required this.station,
    required this.trainNo,
    required this.destination,
    required this.status,
    required this.directionCode,
    required this.isExpress,
    required this.isLastTrain,
    required this.receivedAt,
  });

  final String line;
  final String lineColor;
  final String station;
  final String trainNo;
  final String destination;
  final String status;
  final String directionCode;
  final bool isExpress;
  final bool isLastTrain;
  final String receivedAt;

  factory SubwayTrainPosition.fromJson(Map<String, dynamic> json) {
    return SubwayTrainPosition(
      line: json['line'] as String? ?? '',
      lineColor: json['lineColor'] as String? ?? '',
      station: json['station'] as String? ?? '',
      trainNo: json['trainNo'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      status: json['status'] as String? ?? '',
      directionCode: json['directionCode'] as String? ?? '',
      isExpress: json['isExpress'] as bool? ?? false,
      isLastTrain: json['isLastTrain'] as bool? ?? false,
      receivedAt: json['receivedAt'] as String? ?? '',
    );
  }
}
