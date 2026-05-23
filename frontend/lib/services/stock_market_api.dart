import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

class StockMarketApi {
  StockMarketApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<MarketCapTopDataset> loadGlobalTop() async {
    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client.get(
      Uri.parse('$baseUrl/market-cap/global-top'),
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StockMarketApiException(
        '세계 시총 데이터를 불러오지 못했습니다. (${response.statusCode})',
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw const StockMarketApiException(
        '시가총액 API가 JSON 응답을 반환하지 않았습니다. 잠시 후 다시 시도해 주세요.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const StockMarketApiException(
        '시가총액 API 응답을 해석하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const StockMarketApiException('세계 시총 API 응답 형식이 올바르지 않습니다.');
    }

    return MarketCapTopDataset.fromJson(decoded);
  }
}

class StockMarketApiException implements Exception {
  const StockMarketApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MarketCapTopDataset {
  const MarketCapTopDataset({
    required this.status,
    required this.fetchedAt,
    required this.cached,
    required this.cacheSeconds,
    required this.source,
    required this.summary,
    required this.companies,
  });

  final String status;
  final String fetchedAt;
  final bool cached;
  final int cacheSeconds;
  final MarketCapSource source;
  final MarketCapSummary summary;
  final List<MarketCapCompany> companies;

  factory MarketCapTopDataset.fromJson(Map<String, dynamic> json) {
    return MarketCapTopDataset(
      status: json['status'] as String? ?? 'error',
      fetchedAt: json['fetchedAt'] as String? ?? '',
      cached: json['cached'] as bool? ?? false,
      cacheSeconds: json['cacheSeconds'] as int? ?? 0,
      source: MarketCapSource.fromJson(
        json['source'] as Map<String, dynamic>? ?? const {},
      ),
      summary: MarketCapSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      companies: (json['companies'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MarketCapCompany.fromJson)
          .toList(growable: false),
    );
  }
}

class MarketCapSource {
  const MarketCapSource({
    required this.title,
    required this.provider,
    required this.sourceUrl,
    required this.description,
  });

  final String title;
  final String provider;
  final String sourceUrl;
  final String description;

  factory MarketCapSource.fromJson(Map<String, dynamic> json) {
    return MarketCapSource(
      title: json['title'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

class MarketCapSummary {
  const MarketCapSummary({
    required this.requestedLimit,
    required this.count,
    required this.topCompany,
    required this.topSymbol,
    required this.topMarketCap,
    required this.lastUpdated,
  });

  final int requestedLimit;
  final int count;
  final String topCompany;
  final String topSymbol;
  final int topMarketCap;
  final String lastUpdated;

  factory MarketCapSummary.fromJson(Map<String, dynamic> json) {
    return MarketCapSummary(
      requestedLimit: json['requestedLimit'] as int? ?? 0,
      count: json['count'] as int? ?? 0,
      topCompany: json['topCompany'] as String? ?? '',
      topSymbol: json['topSymbol'] as String? ?? '',
      topMarketCap: json['topMarketCap'] as int? ?? 0,
      lastUpdated: json['lastUpdated'] as String? ?? '',
    );
  }
}

class MarketCapCompany {
  const MarketCapCompany({
    required this.rank,
    required this.symbol,
    required this.name,
    required this.country,
    required this.countryCode,
    required this.sector,
    required this.industry,
    required this.marketCap,
    required this.price,
    required this.dailyChangePercent,
    required this.peRatio,
    required this.revenue,
    required this.earnings,
    required this.lastUpdated,
  });

  final int rank;
  final String symbol;
  final String name;
  final String country;
  final String countryCode;
  final String sector;
  final String industry;
  final int marketCap;
  final double? price;
  final double? dailyChangePercent;
  final double? peRatio;
  final int revenue;
  final int earnings;
  final String lastUpdated;

  bool matches(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return true;
    }
    return name.toLowerCase().contains(trimmed) ||
        symbol.toLowerCase().contains(trimmed) ||
        country.toLowerCase().contains(trimmed) ||
        countryCode.toLowerCase().contains(trimmed) ||
        sector.toLowerCase().contains(trimmed) ||
        industry.toLowerCase().contains(trimmed);
  }

  factory MarketCapCompany.fromJson(Map<String, dynamic> json) {
    return MarketCapCompany(
      rank: json['rank'] as int? ?? 0,
      symbol: json['symbol'] as String? ?? '',
      name: json['name'] as String? ?? '',
      country: json['country'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
      sector: json['sector'] as String? ?? '',
      industry: json['industry'] as String? ?? '',
      marketCap: json['marketCap'] as int? ?? 0,
      price: _doubleOrNull(json['price']),
      dailyChangePercent: _doubleOrNull(json['dailyChangePercent']),
      peRatio: _doubleOrNull(json['peRatio']),
      revenue: json['revenue'] as int? ?? 0,
      earnings: json['earnings'] as int? ?? 0,
      lastUpdated: json['lastUpdated'] as String? ?? '',
    );
  }

  static double? _doubleOrNull(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }
}
