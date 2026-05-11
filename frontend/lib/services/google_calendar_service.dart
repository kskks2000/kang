import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'firebase_social_auth.dart';

class GoogleCalendarService {
  GoogleCalendarService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<GoogleCalendarPreview> loadUpcomingEvents() async {
    final accessToken =
        await FirebaseSocialAuth.requestGoogleCalendarAccessToken();
    final uri = Uri.https(
      'www.googleapis.com',
      '/calendar/v3/calendars/primary/events',
      {
        'maxResults': '5',
        'orderBy': 'startTime',
        'singleEvents': 'true',
        'timeMin': DateTime.now().toUtc().toIso8601String(),
      },
    );

    final response = await _httpClient.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GoogleCalendarEvent.fromJson)
          .toList(growable: false);
      return GoogleCalendarPreview(events: items);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
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
}

class GoogleCalendarPreview {
  const GoogleCalendarPreview({required this.events});

  final List<GoogleCalendarEvent> events;
}

class GoogleCalendarEvent {
  const GoogleCalendarEvent({
    required this.id,
    required this.title,
    this.start,
    this.end,
  });

  final String id;
  final String title;
  final DateTime? start;
  final DateTime? end;

  factory GoogleCalendarEvent.fromJson(Map<String, dynamic> json) {
    final startJson = json['start'] as Map<String, dynamic>?;
    final endJson = json['end'] as Map<String, dynamic>?;

    return GoogleCalendarEvent(
      id: json['id'] as String? ?? '',
      title: (json['summary'] as String?)?.trim().isNotEmpty == true
          ? (json['summary'] as String).trim()
          : 'Untitled event',
      start: _dateTimeFromEventTime(startJson),
      end: _dateTimeFromEventTime(endJson),
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
