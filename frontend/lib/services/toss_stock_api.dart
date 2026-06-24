import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

class TossStockApi {
  TossStockApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<TossOrderActionResult> cancelOrder(String orderId) async {
    final encodedOrderId = Uri.encodeComponent(orderId);
    return _postOrderAction('/toss/orders/$encodedOrderId/cancel', const {});
  }

  Future<TossOrderActionResult> modifyOrder({
    required String orderId,
    required String orderType,
    required String quantity,
    required String price,
  }) async {
    final payload = <String, dynamic>{
      'orderType': orderType,
      'quantity': quantity,
      'confirmHighValueOrder': false,
    };
    if (orderType == 'LIMIT') {
      payload['price'] = price;
    }
    final encodedOrderId = Uri.encodeComponent(orderId);
    return _postOrderAction('/toss/orders/$encodedOrderId/modify', payload);
  }

  Future<TossOpenOrder> loadOrder(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const TossStockApiException('로그인 인증이 만료되었습니다. 다시 로그인해 주세요.');
    }

    final encodedOrderId = Uri.encodeComponent(orderId);
    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client.get(
      Uri.parse('$baseUrl/toss/orders/$encodedOrderId'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
    );
    final decoded = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded['detail']?.toString();
      throw TossStockApiException(
        detail?.isNotEmpty == true ? detail! : '주문 정보를 불러오지 못했습니다.',
      );
    }
    return TossOpenOrder.fromJson(decoded);
  }

  Future<TossOrderSubmitResult> submitOrder(
    TossOrderSubmitRequest order,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const TossStockApiException('로그인 인증이 만료되었습니다. 다시 로그인해 주세요.');
    }

    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client.post(
      Uri.parse('$baseUrl/toss/orders'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(order.toJson()),
    );

    final decoded = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded['detail']?.toString();
      throw TossStockApiException(
        detail?.isNotEmpty == true ? detail! : '주문을 접수하지 못했습니다.',
      );
    }

    return TossOrderSubmitResult.fromJson(decoded);
  }

  Future<TossOrderActionResult> _postOrderAction(
    String path,
    Map<String, dynamic> body,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const TossStockApiException('로그인 인증이 만료되었습니다. 다시 로그인해 주세요.');
    }

    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    final decoded = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded['detail']?.toString();
      throw TossStockApiException(
        detail?.isNotEmpty == true ? detail! : '주문 요청을 처리하지 못했습니다.',
      );
    }
    return TossOrderActionResult.fromJson(decoded);
  }

  Future<TossStockDashboard> loadDashboard({
    required String market,
    String? symbol,
    List<String> symbols = const [],
    String candleInterval = '1m',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const TossStockApiException('로그인 인증이 만료되었습니다. 다시 로그인해 주세요.');
    }

    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final queryParameters = <String, String>{'market': market};
    final normalizedCandleInterval = candleInterval.trim().toLowerCase();
    if (normalizedCandleInterval.isNotEmpty) {
      queryParameters['candleInterval'] = normalizedCandleInterval;
    }
    final selectedSymbol = symbol?.trim().toUpperCase();
    if (selectedSymbol != null && selectedSymbol.isNotEmpty) {
      queryParameters['symbol'] = selectedSymbol;
    }
    final scopedSymbols = <String>[];
    for (final rawSymbol in symbols) {
      final scopedSymbol = rawSymbol.trim().toUpperCase();
      if (scopedSymbol.isNotEmpty && !scopedSymbols.contains(scopedSymbol)) {
        scopedSymbols.add(scopedSymbol);
      }
      if (scopedSymbols.length >= 24) {
        break;
      }
    }
    if (scopedSymbols.isNotEmpty) {
      queryParameters['symbols'] = scopedSymbols.join(',');
    }
    final uri = Uri.parse(
      '$baseUrl/toss/stock-dashboard',
    ).replace(queryParameters: queryParameters);
    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TossStockApiException(
        '토스증권 데이터를 불러오지 못했습니다. (${response.statusCode})',
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw const TossStockApiException(
        '토스증권 API가 JSON 응답을 반환하지 않았습니다. 잠시 후 다시 시도해 주세요.',
      );
    }

    return TossStockDashboard.fromJson(_decodeJsonObject(response));
  }

  Future<TossStockCandlesResult> loadCandles({
    required String market,
    required String symbol,
    String candleInterval = '1m',
    int count = 200,
    String? before,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const TossStockApiException(
        '濡쒓렇???몄쬆??留뚮즺?섏뿀?듬땲?? ?ㅼ떆 濡쒓렇?명빐 二쇱꽭??',
      );
    }

    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final queryParameters = <String, String>{
      'market': market,
      'symbol': symbol.trim().toUpperCase(),
      'candleInterval': candleInterval.trim().toLowerCase(),
      'count': count.clamp(1, 200).toString(),
    };
    final beforeValue = before?.trim();
    if (beforeValue != null && beforeValue.isNotEmpty) {
      queryParameters['before'] = beforeValue;
    }
    final response = await _client.get(
      Uri.parse(
        '$baseUrl/toss/candles',
      ).replace(queryParameters: queryParameters),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
    );
    final decoded = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded['detail']?.toString();
      throw TossStockApiException(
        detail?.isNotEmpty == true ? detail! : '?좎뒪利앷텒 李⑦듃瑜?遺덈윭?ㅼ? 紐삵뻽?듬땲??',
      );
    }
    return TossStockCandlesResult.fromJson(decoded);
  }

  Future<TossStockSearchResult> searchStocks({
    required String market,
    required String query,
    int limit = 30,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const TossStockApiException('로그인 인증이 만료되었습니다. 다시 로그인해 주세요.');
    }

    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/toss/stocks/search').replace(
      queryParameters: {
        'market': market,
        'query': query,
        'limit': limit.toString(),
      },
    );
    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
    );
    final decoded = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded['detail']?.toString();
      throw TossStockApiException(
        detail?.isNotEmpty == true ? detail! : '종목 검색 결과를 불러오지 못했습니다.',
      );
    }
    return TossStockSearchResult.fromJson(decoded);
  }

  void close() {
    _client.close();
  }
}

Map<String, dynamic> _decodeJsonObject(http.Response response) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(response.bodyBytes));
  } on FormatException {
    throw const TossStockApiException(
      '토스증권 API 응답을 해석하지 못했습니다. 잠시 후 다시 시도해 주세요.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const TossStockApiException('토스증권 API 응답 형식이 올바르지 않습니다.');
  }
  return decoded;
}

class TossOrderSubmitRequest {
  const TossOrderSubmitRequest({
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantity,
    required this.price,
    required this.orderAmount,
    this.timeInForce = 'DAY',
  });

  final String symbol;
  final String side;
  final String orderType;
  final String quantity;
  final String price;
  final String orderAmount;
  final String timeInForce;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'symbol': symbol,
      'side': side,
      'orderType': orderType,
      'timeInForce': timeInForce,
      'confirmHighValueOrder': false,
    };
    if (quantity.isNotEmpty) {
      json['quantity'] = quantity;
    }
    if (orderAmount.isNotEmpty) {
      json['orderAmount'] = orderAmount;
    }
    if (orderType == 'LIMIT') {
      json['price'] = price;
    }
    return json;
  }
}

class TossOrderSubmitResult {
  const TossOrderSubmitResult({
    required this.status,
    required this.orderId,
    required this.clientOrderId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantity,
    required this.price,
    required this.timeInForce,
    required this.message,
  });

  final String status;
  final String orderId;
  final String clientOrderId;
  final String symbol;
  final String side;
  final String orderType;
  final String quantity;
  final String price;
  final String timeInForce;
  final String message;

  factory TossOrderSubmitResult.fromJson(Map<String, dynamic> json) {
    return TossOrderSubmitResult(
      status: json['status'] as String? ?? '',
      orderId: json['orderId'] as String? ?? '',
      clientOrderId: json['clientOrderId'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
      side: json['side'] as String? ?? '',
      orderType: json['orderType'] as String? ?? '',
      quantity: json['quantity'] as String? ?? '',
      price: json['price'] as String? ?? '',
      timeInForce: json['timeInForce'] as String? ?? '',
      message: json['message'] as String? ?? '주문이 접수되었습니다.',
    );
  }
}

class TossOrderActionResult {
  const TossOrderActionResult({
    required this.status,
    required this.orderId,
    required this.clientOrderId,
    required this.message,
  });

  final String status;
  final String orderId;
  final String clientOrderId;
  final String message;

  factory TossOrderActionResult.fromJson(Map<String, dynamic> json) {
    return TossOrderActionResult(
      status: json['status'] as String? ?? '',
      orderId: json['orderId'] as String? ?? '',
      clientOrderId: json['clientOrderId'] as String? ?? '',
      message: json['message'] as String? ?? '주문 요청이 접수되었습니다.',
    );
  }
}

class TossStockApiException implements Exception {
  const TossStockApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TossStockSearchResult {
  const TossStockSearchResult({
    required this.market,
    required this.query,
    required this.count,
    required this.items,
  });

  final String market;
  final String query;
  final int count;
  final List<TossStockSearchItem> items;

  factory TossStockSearchResult.fromJson(Map<String, dynamic> json) {
    return TossStockSearchResult(
      market: json['market'] as String? ?? '',
      query: json['query'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TossStockSearchItem.fromJson)
          .toList(growable: false),
    );
  }
}

class TossStockSearchItem {
  const TossStockSearchItem({
    required this.symbol,
    required this.name,
    required this.market,
  });

  final String symbol;
  final String name;
  final String market;

  factory TossStockSearchItem.fromJson(Map<String, dynamic> json) {
    return TossStockSearchItem(
      symbol: json['symbol'] as String? ?? '',
      name: json['name'] as String? ?? '',
      market: json['market'] as String? ?? '',
    );
  }
}

class TossStockDashboard {
  const TossStockDashboard({
    required this.status,
    required this.fetchedAt,
    required this.cached,
    required this.cacheSeconds,
    required this.summary,
    required this.watchlist,
    required this.orderbook,
    required this.candles,
    required this.holdings,
    required this.openOrders,
    required this.buyingPower,
    required this.errors,
  });

  final String status;
  final String fetchedAt;
  final bool cached;
  final int cacheSeconds;
  final TossStockSummary summary;
  final List<TossStockQuote> watchlist;
  final TossOrderbook? orderbook;
  final List<TossCandle> candles;
  final List<TossHolding> holdings;
  final List<TossOpenOrder> openOrders;
  final List<TossBuyingPower> buyingPower;
  final List<String> errors;

  TossStockQuote? get primaryQuote {
    final primarySymbol = summary.primarySymbol.trim().toUpperCase();
    if (primarySymbol.isNotEmpty) {
      for (final quote in watchlist) {
        if (quote.symbol.toUpperCase() == primarySymbol) {
          return quote;
        }
      }
    }
    return watchlist.isEmpty ? null : watchlist.first;
  }

  bool get hasLiveData =>
      status == 'ok' ||
      status == 'partial' ||
      watchlist.any((item) => item.hasPrice);

  String? get firstError => errors.isEmpty ? null : errors.first;

  factory TossStockDashboard.fromJson(Map<String, dynamic> json) {
    return TossStockDashboard(
      status: json['status'] as String? ?? 'error',
      fetchedAt: json['fetchedAt'] as String? ?? '',
      cached: json['cached'] as bool? ?? false,
      cacheSeconds: json['cacheSeconds'] as int? ?? 0,
      summary: TossStockSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      watchlist: (json['watchlist'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TossStockQuote.fromJson)
          .toList(growable: false),
      orderbook: json['orderbook'] is Map<String, dynamic>
          ? TossOrderbook.fromJson(json['orderbook'] as Map<String, dynamic>)
          : null,
      candles: (json['candles'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TossCandle.fromJson)
          .toList(growable: false),
      holdings: (json['holdings'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TossHolding.fromJson)
          .toList(growable: false),
      openOrders: (json['openOrders'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TossOpenOrder.fromJson)
          .toList(growable: false),
      buyingPower: (json['buyingPower'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TossBuyingPower.fromJson)
          .toList(growable: false),
      errors: (json['errors'] as List<dynamic>? ?? const [])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class TossStockCandlesResult {
  const TossStockCandlesResult({
    required this.symbol,
    required this.interval,
    required this.count,
    required this.nextBefore,
    required this.candles,
  });

  final String symbol;
  final String interval;
  final int count;
  final String nextBefore;
  final List<TossCandle> candles;

  factory TossStockCandlesResult.fromJson(Map<String, dynamic> json) {
    return TossStockCandlesResult(
      symbol: json['symbol'] as String? ?? '',
      interval: json['interval'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      nextBefore: json['nextBefore'] as String? ?? '',
      candles: (json['candles'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TossCandle.fromJson)
          .toList(growable: false),
    );
  }
}

class TossStockSummary {
  const TossStockSummary({
    required this.market,
    required this.primarySymbol,
    required this.symbolCount,
    required this.accountCount,
    required this.accountConfigured,
    required this.selectedAccountMasked,
    required this.holdingCount,
    required this.openOrderCount,
    required this.buyingPowerKrw,
    required this.buyingPowerUsd,
  });

  final String market;
  final String primarySymbol;
  final int symbolCount;
  final int accountCount;
  final bool accountConfigured;
  final String selectedAccountMasked;
  final int holdingCount;
  final int openOrderCount;
  final String buyingPowerKrw;
  final String buyingPowerUsd;

  factory TossStockSummary.fromJson(Map<String, dynamic> json) {
    return TossStockSummary(
      market: json['market'] as String? ?? 'KR',
      primarySymbol: json['primarySymbol'] as String? ?? '',
      symbolCount: json['symbolCount'] as int? ?? 0,
      accountCount: json['accountCount'] as int? ?? 0,
      accountConfigured: json['accountConfigured'] as bool? ?? false,
      selectedAccountMasked: json['selectedAccountMasked'] as String? ?? '',
      holdingCount: json['holdingCount'] as int? ?? 0,
      openOrderCount: json['openOrderCount'] as int? ?? 0,
      buyingPowerKrw: json['buyingPowerKrw'] as String? ?? '',
      buyingPowerUsd: json['buyingPowerUsd'] as String? ?? '',
    );
  }
}

class TossStockQuote {
  const TossStockQuote({
    required this.symbol,
    required this.name,
    required this.englishName,
    required this.displayName,
    required this.market,
    required this.currency,
    required this.lastPrice,
    required this.previousClose,
    required this.change,
    required this.changePercent,
    required this.sharesOutstanding,
    required this.marketCap,
    required this.timestamp,
  });

  final String symbol;
  final String name;
  final String englishName;
  final String displayName;
  final String market;
  final String currency;
  final String lastPrice;
  final String previousClose;
  final String change;
  final String changePercent;
  final String sharesOutstanding;
  final String marketCap;
  final String timestamp;

  bool get hasPrice => lastPrice.trim().isNotEmpty;
  double? get lastPriceValue => _doubleOrNull(lastPrice);
  double? get changeValue => _doubleOrNull(change);
  double? get changePercentValue => _doubleOrNull(changePercent);
  double? get marketCapValue => _doubleOrNull(marketCap);
  bool get isUp => (changeValue ?? 0) > 0;
  bool get isDown => (changeValue ?? 0) < 0;

  factory TossStockQuote.fromJson(Map<String, dynamic> json) {
    return TossStockQuote(
      symbol: json['symbol'] as String? ?? '',
      name: json['name'] as String? ?? '',
      englishName: json['englishName'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      market: json['market'] as String? ?? '',
      currency: json['currency'] as String? ?? '',
      lastPrice: json['lastPrice'] as String? ?? '',
      previousClose: json['previousClose'] as String? ?? '',
      change: json['change'] as String? ?? '',
      changePercent: json['changePercent'] as String? ?? '',
      sharesOutstanding: json['sharesOutstanding'] as String? ?? '',
      marketCap: json['marketCap'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
    );
  }
}

class TossOrderbook {
  const TossOrderbook({
    required this.symbol,
    required this.timestamp,
    required this.currency,
    required this.asks,
    required this.bids,
  });

  final String symbol;
  final String timestamp;
  final String currency;
  final List<TossOrderbookEntry> asks;
  final List<TossOrderbookEntry> bids;

  factory TossOrderbook.fromJson(Map<String, dynamic> json) {
    return TossOrderbook(
      symbol: json['symbol'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      currency: json['currency'] as String? ?? '',
      asks: (json['asks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TossOrderbookEntry.fromJson)
          .toList(growable: false),
      bids: (json['bids'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TossOrderbookEntry.fromJson)
          .toList(growable: false),
    );
  }
}

class TossOrderbookEntry {
  const TossOrderbookEntry({required this.price, required this.volume});

  final String price;
  final String volume;

  factory TossOrderbookEntry.fromJson(Map<String, dynamic> json) {
    return TossOrderbookEntry(
      price: json['price'] as String? ?? '',
      volume: json['volume'] as String? ?? '',
    );
  }
}

class TossCandle {
  const TossCandle({
    required this.timestamp,
    required this.openPrice,
    required this.highPrice,
    required this.lowPrice,
    required this.closePrice,
    required this.volume,
    required this.currency,
  });

  final String timestamp;
  final String openPrice;
  final String highPrice;
  final String lowPrice;
  final String closePrice;
  final String volume;
  final String currency;

  double? get closePriceValue => _doubleOrNull(closePrice);

  factory TossCandle.fromJson(Map<String, dynamic> json) {
    return TossCandle(
      timestamp: json['timestamp'] as String? ?? '',
      openPrice: json['openPrice'] as String? ?? '',
      highPrice: json['highPrice'] as String? ?? '',
      lowPrice: json['lowPrice'] as String? ?? '',
      closePrice: json['closePrice'] as String? ?? '',
      volume: json['volume'] as String? ?? '',
      currency: json['currency'] as String? ?? '',
    );
  }
}

class TossHolding {
  const TossHolding({
    required this.symbol,
    required this.name,
    required this.marketCountry,
    required this.currency,
    required this.quantity,
    required this.lastPrice,
    required this.averagePurchasePrice,
    required this.marketValue,
    required this.profitLoss,
    required this.profitLossRate,
  });

  final String symbol;
  final String name;
  final String marketCountry;
  final String currency;
  final String quantity;
  final String lastPrice;
  final String averagePurchasePrice;
  final String marketValue;
  final String profitLoss;
  final String profitLossRate;

  factory TossHolding.fromJson(Map<String, dynamic> json) {
    return TossHolding(
      symbol: json['symbol'] as String? ?? '',
      name: json['name'] as String? ?? '',
      marketCountry: json['marketCountry'] as String? ?? '',
      currency: json['currency'] as String? ?? '',
      quantity: json['quantity'] as String? ?? '',
      lastPrice: json['lastPrice'] as String? ?? '',
      averagePurchasePrice: json['averagePurchasePrice'] as String? ?? '',
      marketValue: json['marketValue'] as String? ?? '',
      profitLoss: json['profitLoss'] as String? ?? '',
      profitLossRate: json['profitLossRate'] as String? ?? '',
    );
  }
}

class TossOpenOrder {
  const TossOpenOrder({
    required this.orderId,
    required this.symbol,
    required this.side,
    required this.status,
    required this.orderType,
    required this.quantity,
    required this.price,
    required this.currency,
    required this.orderedAt,
  });

  final String orderId;
  final String symbol;
  final String side;
  final String status;
  final String orderType;
  final String quantity;
  final String price;
  final String currency;
  final String orderedAt;

  factory TossOpenOrder.fromJson(Map<String, dynamic> json) {
    return TossOpenOrder(
      orderId: json['orderId'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
      side: json['side'] as String? ?? '',
      status: json['status'] as String? ?? '',
      orderType: json['orderType'] as String? ?? '',
      quantity: json['quantity'] as String? ?? '',
      price: json['price'] as String? ?? '',
      currency: json['currency'] as String? ?? '',
      orderedAt: json['orderedAt'] as String? ?? '',
    );
  }
}

class TossBuyingPower {
  const TossBuyingPower({
    required this.currency,
    required this.cashBuyingPower,
  });

  final String currency;
  final String cashBuyingPower;

  factory TossBuyingPower.fromJson(Map<String, dynamic> json) {
    return TossBuyingPower(
      currency: json['currency'] as String? ?? '',
      cashBuyingPower: json['cashBuyingPower'] as String? ?? '',
    );
  }
}

double? _doubleOrNull(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  final normalized = value?.toString().replaceAll(',', '').trim() ?? '';
  return double.tryParse(normalized);
}
