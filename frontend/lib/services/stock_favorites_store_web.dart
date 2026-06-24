import 'package:web/web.dart' as web;

class StockFavoritesStore {
  StockFavoritesStore(this.key);

  final String key;

  List<String> read() {
    try {
      return _decode(web.window.localStorage.getItem(key));
    } catch (_) {
      return const [];
    }
  }

  void write(List<String> symbols) {
    try {
      web.window.localStorage.setItem(key, symbols.join(','));
    } catch (_) {
      // Browsers can block storage in private or restricted contexts.
    }
  }

  List<String> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    return raw
        .split(',')
        .map((item) => item.trim().toUpperCase())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
}
