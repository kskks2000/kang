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
    final uri = Uri.https(
      'www.googleapis.com',
      '/calendar/v3/calendars/primary/events',
      {
        'maxResults': '50',
        'orderBy': 'startTime',
        'singleEvents': 'true',
        'timeMin': dayStart.toUtc().toIso8601String(),
        'timeMax': dayEnd.toUtc().toIso8601String(),
      },
    );

    final response = await _getWithToken(uri, accessToken);

    if (response.statusCode == 200) {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final items = (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GoogleCalendarEvent.fromJson)
          .toList(growable: false);
      return GoogleCalendarPreview(date: dayStart, events: items);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      _accessToken = null;
      FirebaseSocialAuth.clearCachedGoogleCalendarAccessToken();
      throw FirebaseAuthException(
        code: 'calendar-scope-denied',
        message:
            'Google Calendar permission was denied or the access token expired.',
      );
    }

    throw GoogleCalendarException(
      'Google Calendar API failed with ${response.statusCode}: ${response.body}',
    );
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

class GoogleCalendarEvent {
  const GoogleCalendarEvent({
    required this.id,
    required this.title,
    this.start,
    this.end,
    this.location,
    this.allDay = false,
  });

  final String id;
  final String title;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final bool allDay;

  factory GoogleCalendarEvent.fromJson(Map<String, dynamic> json) {
    final startJson = json['start'] as Map<String, dynamic>?;
    final endJson = json['end'] as Map<String, dynamic>?;
    final allDay = startJson?['date'] != null;

    return GoogleCalendarEvent(
      id: json['id'] as String? ?? '',
      title: (json['summary'] as String?)?.trim().isNotEmpty == true
          ? (json['summary'] as String).trim()
          : 'Untitled event',
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
