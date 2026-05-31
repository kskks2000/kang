import 'package:web/web.dart' as web;

Future<bool> openGoogleCalendar({DateTime? date}) async {
  web.window.open(_calendarUrl(date), '_blank', 'noopener,noreferrer');
  return true;
}

Future<bool> openGoogleCalendarEventCreate({DateTime? date}) async {
  web.window.open(_eventCreateUrl(date), '_blank', 'noopener,noreferrer');
  return true;
}

String _calendarUrl(DateTime? date) {
  if (date == null) {
    return 'https://calendar.google.com/calendar/u/0/r';
  }
  return 'https://calendar.google.com/calendar/u/0/r/month/'
      '${date.year}/${date.month}/${date.day}';
}

String _eventCreateUrl(DateTime? date) {
  final selectedDate = date;
  if (selectedDate == null) {
    return 'https://calendar.google.com/calendar/u/0/r/eventedit';
  }

  final start = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final end = start.add(const Duration(days: 1));
  final params = Uri(
    queryParameters: {
      'dates': '${_dateStamp(start)}/${_dateStamp(end)}',
      'ctz': 'Asia/Seoul',
    },
  ).query;
  return 'https://calendar.google.com/calendar/u/0/r/eventedit?$params';
}

String _dateStamp(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year$month$day';
}
