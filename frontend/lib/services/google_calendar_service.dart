import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'firebase_social_auth.dart';

class GoogleCalendarService {
  GoogleCalendarService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  String? _accessToken;

  Future<GoogleCalendarPreview> loadEventsForDate(
    DateTime date, {
    bool interactive = true,
  }) async {
    final accessToken = await _calendarAccessToken(interactive: interactive);
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final calendars = await _loadCalendars(accessToken);
    final calendarEvents = await Future.wait(
      calendars.map(
        (calendar) => _loadEventsForCalendar(
          calendar: calendar,
          accessToken: accessToken,
          dayStart: dayStart,
          dayEnd: dayEnd,
        ),
      ),
    );
    final events = calendarEvents.expand((events) => events).toList()
      ..sort(_compareEvents);

    return GoogleCalendarPreview(date: dayStart, events: events);
  }

  Future<List<GoogleCalendarInfo>> _loadCalendars(String accessToken) async {
    final uri = Uri.https(
      'www.googleapis.com',
      '/calendar/v3/users/me/calendarList',
      {'maxResults': '250', 'minAccessRole': 'reader', 'showHidden': 'false'},
    );
    final response = await _getWithToken(uri, accessToken);

    _throwForAuthError(response);

    if (response.statusCode == 200) {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final calendars = (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where(
            (item) =>
                item['selected'] == true ||
                item['primary'] == true ||
                item['id'] == 'primary',
          )
          .map(GoogleCalendarInfo.fromJson)
          .toList(growable: false);
      if (calendars.isNotEmpty) {
        return calendars;
      }

      return const [GoogleCalendarInfo(id: 'primary', title: 'Primary')];
    }

    throw GoogleCalendarException(
      'Google Calendar list failed with ${response.statusCode}: ${response.body}',
    );
  }

  Future<List<GoogleCalendarEvent>> _loadEventsForCalendar({
    required GoogleCalendarInfo calendar,
    required String accessToken,
    required DateTime dayStart,
    required DateTime dayEnd,
  }) async {
    final uri = Uri(
      scheme: 'https',
      host: 'www.googleapis.com',
      pathSegments: ['calendar', 'v3', 'calendars', calendar.id, 'events'],
      queryParameters: {
        'maxResults': '50',
        'orderBy': 'startTime',
        'singleEvents': 'true',
        'timeMin': dayStart.toUtc().toIso8601String(),
        'timeMax': dayEnd.toUtc().toIso8601String(),
      },
    );
    final response = await _getWithToken(uri, accessToken);

    _throwForAuthError(response);

    if (response.statusCode == 200) {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((item) => GoogleCalendarEvent.fromJson(item, calendar))
          .toList(growable: false);
    }

    throw GoogleCalendarException(
      'Google Calendar API failed with ${response.statusCode}: ${response.body}',
    );
  }

  void _throwForAuthError(http.Response response) {
    if (response.statusCode != 401 && response.statusCode != 403) {
      return;
    }

    _accessToken = null;
    FirebaseSocialAuth.clearCachedGoogleCalendarAccessToken();
    throw FirebaseAuthException(
      code: 'calendar-scope-denied',
      message:
          'Google Calendar permission was denied, missing, or the access token expired.',
    );
  }

  int _compareEvents(GoogleCalendarEvent a, GoogleCalendarEvent b) {
    if (a.allDay != b.allDay) {
      return a.allDay ? -1 : 1;
    }

    final aStart = a.start;
    final bStart = b.start;
    if (aStart == null && bStart == null) {
      return a.title.compareTo(b.title);
    }
    if (aStart == null) {
      return 1;
    }
    if (bStart == null) {
      return -1;
    }
    return aStart.compareTo(bStart);
  }

  Future<String> _calendarAccessToken({required bool interactive}) async {
    final cachedToken =
        _accessToken ?? FirebaseSocialAuth.cachedCalendarAccessToken;
    if (cachedToken != null && cachedToken.isNotEmpty) {
      _accessToken = cachedToken;
      return cachedToken;
    }

    if (!interactive) {
      throw FirebaseAuthException(
        code: 'missing-google-access-token',
        message: 'Google Calendar access token is not available yet.',
      );
    }

    final accessToken =
        await FirebaseSocialAuth.requestGoogleCalendarAccessToken();
    _accessToken = accessToken;
    return accessToken;
  }

  Future<http.Response> _getWithToken(Uri uri, String accessToken) {
    return _httpClient.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }
}

class GoogleCalendarPreview {
  const GoogleCalendarPreview({required this.date, required this.events});

  final DateTime date;
  final List<GoogleCalendarEvent> events;
}

class GoogleCalendarInfo {
  const GoogleCalendarInfo({required this.id, required this.title});

  final String id;
  final String title;

  factory GoogleCalendarInfo.fromJson(Map<String, dynamic> json) {
    return GoogleCalendarInfo(
      id: json['id'] as String? ?? 'primary',
      title: (json['summary'] as String?)?.trim().isNotEmpty == true
          ? (json['summary'] as String).trim()
          : 'Calendar',
    );
  }
}

class GoogleCalendarEvent {
  const GoogleCalendarEvent({
    required this.id,
    required this.title,
    required this.calendarTitle,
    this.start,
    this.end,
    this.location,
    this.allDay = false,
  });

  final String id;
  final String title;
  final String calendarTitle;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final bool allDay;

  factory GoogleCalendarEvent.fromJson(
    Map<String, dynamic> json,
    GoogleCalendarInfo calendar,
  ) {
    final startJson = json['start'] as Map<String, dynamic>?;
    final endJson = json['end'] as Map<String, dynamic>?;
    final allDay = startJson?['date'] != null;

    return GoogleCalendarEvent(
      id: json['id'] as String? ?? '',
      title: (json['summary'] as String?)?.trim().isNotEmpty == true
          ? (json['summary'] as String).trim()
          : 'Untitled event',
      calendarTitle: calendar.title,
      start: _dateTimeFromEventTime(startJson),
      end: _dateTimeFromEventTime(endJson),
      location: (json['location'] as String?)?.trim().isNotEmpty == true
          ? (json['location'] as String).trim()
          : null,
      allDay: allDay,
    );
  }

  static DateTime? _dateTimeFromEventTime(Map<String, dynamic>? json) {
    final value = json?['dateTime'] as String? ?? json?['date'] as String?;
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}

class GoogleCalendarException implements Exception {
  const GoogleCalendarException(this.message);

  final String message;

  @override
  String toString() => message;
}
