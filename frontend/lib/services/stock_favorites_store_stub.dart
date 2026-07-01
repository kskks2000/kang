class StockFavoritesStore {
  StockFavoritesStore(this.key);

  final String key;
  static final Map<String, String> _memory = {};

  List<String> read() {
    return _decode(_memory[key]);
  }

  String? readRaw() {
    return _memory[key];
  }

  void write(List<String> symbols) {
    _memory[key] = symbols.join(',');
  }

  void writeRaw(String value) {
    _memory[key] = value;
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
