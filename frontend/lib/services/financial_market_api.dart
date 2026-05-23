import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

class FinancialMarketApi {
  FinancialMarketApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<FinancialMarketsDataset> loadMarkets() async {
    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client.get(
      Uri.parse('$baseUrl/financial/markets'),
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FinancialMarketApiException(
        '금융정보 데이터를 불러오지 못했습니다. (${response.statusCode})',
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw const FinancialMarketApiException(
        '금융정보 API가 JSON 응답을 반환하지 않았습니다. 잠시 후 다시 시도해 주세요.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const FinancialMarketApiException(
        '금융정보 API 응답을 해석하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FinancialMarketApiException('금융정보 API 응답 형식이 올바르지 않습니다.');
    }

    return FinancialMarketsDataset.fromJson(decoded);
  }
}

class FinancialMarketApiException implements Exception {
  const FinancialMarketApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FinancialMarketsDataset {
  const FinancialMarketsDataset({
    required this.status,
    required this.fetchedAt,
    required this.cached,
    required this.cacheSeconds,
    required this.sources,
    required this.summary,
    required this.treasuryRates,
    required this.treasurySpreads,
    required this.exchangeRates,
    required this.futures,
    required this.errors,
  });

  final String status;
  final String fetchedAt;
  final bool cached;
  final int cacheSeconds;
  final List<FinancialSource> sources;
  final FinancialSummary summary;
  final List<TreasuryRate> treasuryRates;
  final List<TreasurySpread> treasurySpreads;
  final List<ExchangeRate> exchangeRates;
  final List<MarketFutureQuote> futures;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;

  TreasuryRate? treasuryRate(String maturity) {
    for (final rate in treasuryRates) {
      if (rate.maturity == maturity) {
        return rate;
      }
    }
    return null;
  }

  TreasurySpread? treasurySpread(String code) {
    for (final spread in treasurySpreads) {
      if (spread.code == code) {
        return spread;
      }
    }
    return null;
  }

  ExchangeRate? exchangeRate(String pair) {
    for (final rate in exchangeRates) {
      if (rate.pair == pair) {
        return rate;
      }
    }
    return null;
  }

  MarketFutureQuote? futureQuote(String symbol) {
    for (final quote in futures) {
      if (quote.symbol == symbol) {
        return quote;
      }
    }
    return null;
  }

  factory FinancialMarketsDataset.fromJson(Map<String, dynamic> json) {
    return FinancialMarketsDataset(
      status: json['status'] as String? ?? 'error',
      fetchedAt: json['fetchedAt'] as String? ?? '',
      cached: json['cached'] as bool? ?? false,
      cacheSeconds: json['cacheSeconds'] as int? ?? 0,
      sources: (json['sources'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FinancialSource.fromJson)
          .toList(growable: false),
      summary: FinancialSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      treasuryRates: (json['treasuryRates'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TreasuryRate.fromJson)
          .toList(growable: false),
      treasurySpreads: (json['treasurySpreads'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TreasurySpread.fromJson)
          .toList(growable: false),
      exchangeRates: (json['exchangeRates'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ExchangeRate.fromJson)
          .toList(growable: false),
      futures: (json['futures'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MarketFutureQuote.fromJson)
          .toList(growable: false),
      errors: (json['errors'] as List<dynamic>? ?? const [])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class FinancialSource {
  const FinancialSource({
    required this.name,
    required this.url,
    required this.description,
  });

  final String name;
  final String url;
  final String description;

  factory FinancialSource.fromJson(Map<String, dynamic> json) {
    return FinancialSource(
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

class FinancialSummary {
  const FinancialSummary({
    required this.treasuryDate,
    required this.exchangeRateDate,
    required this.treasuryCount,
    required this.exchangeRateCount,
    required this.futureCount,
    required this.errorCount,
  });

  final String treasuryDate;
  final String exchangeRateDate;
  final int treasuryCount;
  final int exchangeRateCount;
  final int futureCount;
  final int errorCount;

  factory FinancialSummary.fromJson(Map<String, dynamic> json) {
    return FinancialSummary(
      treasuryDate: json['treasuryDate'] as String? ?? '',
      exchangeRateDate: json['exchangeRateDate'] as String? ?? '',
      treasuryCount: json['treasuryCount'] as int? ?? 0,
      exchangeRateCount: json['exchangeRateCount'] as int? ?? 0,
      futureCount: json['futureCount'] as int? ?? 0,
      errorCount: json['errorCount'] as int? ?? 0,
    );
  }
}

class TreasuryRate {
  const TreasuryRate({
    required this.maturity,
    required this.label,
    required this.rate,
    required this.previousRate,
    required this.change,
    required this.date,
  });

  final String maturity;
  final String label;
  final double? rate;
  final double? previousRate;
  final double? change;
  final String date;

  factory TreasuryRate.fromJson(Map<String, dynamic> json) {
    return TreasuryRate(
      maturity: json['maturity'] as String? ?? '',
      label: json['label'] as String? ?? '',
      rate: _doubleOrNull(json['rate']),
      previousRate: _doubleOrNull(json['previousRate']),
      change: _doubleOrNull(json['change']),
      date: json['date'] as String? ?? '',
    );
  }
}

class TreasurySpread {
  const TreasurySpread({
    required this.code,
    required this.label,
    required this.value,
    required this.date,
  });

  final String code;
  final String label;
  final double? value;
  final String date;

  factory TreasurySpread.fromJson(Map<String, dynamic> json) {
    return TreasurySpread(
      code: json['code'] as String? ?? '',
      label: json['label'] as String? ?? '',
      value: _doubleOrNull(json['value']),
      date: json['date'] as String? ?? '',
    );
  }
}

class ExchangeRate {
  const ExchangeRate({
    required this.pair,
    required this.label,
    required this.base,
    required this.quote,
    required this.rate,
    required this.usdBaseRate,
    required this.date,
  });

  final String pair;
  final String label;
  final String base;
  final String quote;
  final double rate;
  final double usdBaseRate;
  final String date;

  factory ExchangeRate.fromJson(Map<String, dynamic> json) {
    return ExchangeRate(
      pair: json['pair'] as String? ?? '',
      label: json['label'] as String? ?? '',
      base: json['base'] as String? ?? '',
      quote: json['quote'] as String? ?? '',
      rate: _doubleOrNull(json['rate']) ?? 0,
      usdBaseRate: _doubleOrNull(json['usdBaseRate']) ?? 0,
      date: json['date'] as String? ?? '',
    );
  }
}

class MarketFutureQuote {
  const MarketFutureQuote({
    required this.symbol,
    required this.name,
    required this.displayName,
    required this.group,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.previousClose,
    required this.currency,
    required this.marketTime,
    required this.exchange,
  });

  final String symbol;
  final String name;
  final String displayName;
  final String group;
  final double? price;
  final double? change;
  final double? changePercent;
  final double? previousClose;
  final String currency;
  final String marketTime;
  final String exchange;

  factory MarketFutureQuote.fromJson(Map<String, dynamic> json) {
    return MarketFutureQuote(
      symbol: json['symbol'] as String? ?? '',
      name: json['name'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      group: json['group'] as String? ?? '',
      price: _doubleOrNull(json['price']),
      change: _doubleOrNull(json['change']),
      changePercent: _doubleOrNull(json['changePercent']),
      previousClose: _doubleOrNull(json['previousClose']),
      currency: json['currency'] as String? ?? '',
      marketTime: json['marketTime'] as String? ?? '',
      exchange: json['exchange'] as String? ?? '',
    );
  }
}

double? _doubleOrNull(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}
