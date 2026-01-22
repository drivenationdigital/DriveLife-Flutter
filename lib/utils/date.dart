import 'package:intl/intl.dart';

class DateHelpers {
  static String formatDate(String? date, String time, bool isSingleDay) {
    if (date == null) return '';

    try {
      final parsed = DateTime.parse(date);
      final formatted =
          '${_weekday(parsed.weekday)}, ${parsed.day.toString().padLeft(2, '0')} '
          '${_month(parsed.month)} ${parsed.year}';

      return '$formatted ${time.isNotEmpty ? time : ''}';
    } catch (_) {
      return date;
    }
  }

  static String _weekday(int day) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[day - 1];
  }

  static String _month(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  static String formatEventDate(String dateStr) {
    try {
      // Parse "01/26/2026 18:00" format
      final parts = dateStr.split(' ');
      if (parts.isEmpty) return dateStr;

      final datePart = parts[0].split('/');
      if (datePart.length != 3) return dateStr;

      final month = int.parse(datePart[0]);
      final day = int.parse(datePart[1]);
      final year = int.parse(datePart[2]);

      final date = DateTime(year, month, day);
      final formatter = DateFormat('EEE, d MMM yy');

      return formatter.format(date);
    } catch (e) {
      return dateStr;
    }
  }

  static String formatEventTime(String startDate, String endDate) {
    try {
      final startParts = startDate.split(' ');
      final endParts = endDate.split(' ');

      if (startParts.length < 2 || endParts.length < 2) return '';

      final startTime = startParts[1];
      final endTime = endParts[1];

      // Convert 24h to 12h format
      final startHour = int.parse(startTime.split(':')[0]);
      final endHour = int.parse(endTime.split(':')[0]);

      final startPeriod = startHour >= 12 ? 'PM' : 'AM';
      final endPeriod = endHour >= 12 ? 'PM' : 'AM';

      final start12h = startHour > 12
          ? startHour - 12
          : (startHour == 0 ? 12 : startHour);
      final end12h = endHour > 12
          ? endHour - 12
          : (endHour == 0 ? 12 : endHour);

      return '$start12h$startPeriod - $end12h$endPeriod';
    } catch (e) {
      return '';
    }
  }
}
