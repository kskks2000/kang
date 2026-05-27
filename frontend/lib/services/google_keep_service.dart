import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'firebase_social_auth.dart';

class GoogleKeepService {
  GoogleKeepService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  String? _accessToken;

  Future<GoogleKeepNotesDataset> loadNotes({bool interactive = true}) async {
    final accessToken = _keepAccessToken();
    final notes = <GoogleKeepNote>[];
    String? pageToken;

    for (var page = 0; page < 4; page++) {
      final uri = Uri.https('keep.googleapis.com', '/v1/notes', {
        'pageSize': '50',
        'filter': 'trashed=false',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      });
      final response = await _getWithToken(uri, accessToken);

      if (_isAuthError(response)) {
        _accessToken = null;
        return const GoogleKeepNotesDataset(notes: [], apiUnavailable: true);
      }

      if (response.statusCode != 200) {
        throw GoogleKeepException(
          'Google Keep API failed with ${response.statusCode}: ${response.body}',
        );
      }

      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      notes.addAll(
        (decoded['notes'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(GoogleKeepNote.fromJson),
      );
      pageToken = decoded['nextPageToken'] as String?;
      if (pageToken == null || pageToken.isEmpty) {
        break;
      }
    }

    notes.sort((a, b) {
      final updated = b.updatedAt.compareTo(a.updatedAt);
      return updated != 0 ? updated : b.createdAt.compareTo(a.createdAt);
    });

    return GoogleKeepNotesDataset(notes: notes);
  }

  bool _isAuthError(http.Response response) {
    return response.statusCode == 401 || response.statusCode == 403;
  }

  String _keepAccessToken() {
    final cachedToken =
        _accessToken ?? FirebaseSocialAuth.cachedGoogleAccessToken;
    if (cachedToken != null && cachedToken.isNotEmpty) {
      _accessToken = cachedToken;
      return cachedToken;
    }

    throw FirebaseAuthException(
      code: 'missing-google-access-token',
      message: 'Google login access token is not available yet.',
    );
  }

  Future<http.Response> _getWithToken(Uri uri, String accessToken) {
    return _httpClient.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }
}

class GoogleKeepNotesDataset {
  const GoogleKeepNotesDataset({
    required this.notes,
    this.apiUnavailable = false,
  });

  final List<GoogleKeepNote> notes;
  final bool apiUnavailable;

  int get textNoteCount => notes.where((note) => !note.isChecklist).length;
  int get checklistCount => notes.where((note) => note.isChecklist).length;
}

class GoogleKeepNote {
  const GoogleKeepNote({
    required this.name,
    required this.title,
    required this.text,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    required this.attachmentCount,
  });

  final String name;
  final String title;
  final String text;
  final List<GoogleKeepListItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int attachmentCount;

  bool get isChecklist => items.isNotEmpty;
  int get completedItemCount => items.where((item) => item.checked).length;
  int get pendingItemCount => items.length - completedItemCount;

  String get displayTitle {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isNotEmpty) {
      return trimmedTitle;
    }
    final fallback = preview.trim();
    return fallback.isEmpty ? '제목 없는 메모' : fallback;
  }

  String get preview {
    if (isChecklist) {
      return items
          .map((item) => item.text)
          .where((text) => text.isNotEmpty)
          .join(' · ');
    }
    return text.trim();
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return title.toLowerCase().contains(normalized) ||
        text.toLowerCase().contains(normalized) ||
        items.any((item) => item.text.toLowerCase().contains(normalized));
  }

  factory GoogleKeepNote.fromJson(Map<String, dynamic> json) {
    final body = json['body'] as Map<String, dynamic>? ?? const {};
    final textBody = body['text'] as Map<String, dynamic>?;
    final listBody = body['list'] as Map<String, dynamic>?;
    final items = (listBody?['listItems'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .expand(GoogleKeepListItem.fromJsonWithChildren)
        .toList(growable: false);

    return GoogleKeepNote(
      name: json['name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      text: textBody?['text'] as String? ?? '',
      items: items,
      createdAt: _dateTimeOrEpoch(json['createTime']),
      updatedAt: _dateTimeOrEpoch(json['updateTime']),
      attachmentCount:
          (json['attachments'] as List<dynamic>? ?? const []).length,
    );
  }
}

class GoogleKeepListItem {
  const GoogleKeepListItem({
    required this.text,
    required this.checked,
    this.child = false,
  });

  final String text;
  final bool checked;
  final bool child;

  static Iterable<GoogleKeepListItem> fromJsonWithChildren(
    Map<String, dynamic> json,
  ) sync* {
    yield GoogleKeepListItem.fromJson(json);
    final children = json['childListItems'] as List<dynamic>? ?? const [];
    for (final child in children.whereType<Map<String, dynamic>>()) {
      yield GoogleKeepListItem.fromJson(child, child: true);
    }
  }

  factory GoogleKeepListItem.fromJson(
    Map<String, dynamic> json, {
    bool child = false,
  }) {
    final textJson = json['text'] as Map<String, dynamic>? ?? const {};
    return GoogleKeepListItem(
      text: textJson['text'] as String? ?? '',
      checked: json['checked'] as bool? ?? false,
      child: child,
    );
  }
}

class GoogleKeepException implements Exception {
  const GoogleKeepException(this.message);

  final String message;

  @override
  String toString() => message;
}

DateTime _dateTimeOrEpoch(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
