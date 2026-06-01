import 'package:intl/intl.dart';

/// Project-wide clock helpers that pin every user-facing date / time to
/// US Eastern (America/New_York) regardless of the device's locale or
/// timezone. The factory is in Mulberry, FL — the team thinks in EST/EDT,
/// so the app should too.
///
/// We don't pull in the full `timezone` package because the DST rules
/// we care about are well-known and stable since 2007:
///
///   * EDT (UTC-4): from the second Sunday in March (02:00 local) to the
///     first Sunday in November (02:00 local).
///   * EST (UTC-5): the rest of the year.
///
/// All helpers accept a [DateTime] (UTC or local) and emit a string. The
/// date-only helper bypasses DST entirely since a calendar date doesn't
/// shift on the boundary day.
class EstClock {
  EstClock._();

  /// Returns the Eastern (EST or EDT) offset in hours for a given UTC
  /// instant. We compute the second-Sunday-of-March and first-Sunday-of-
  /// November transitions on the fly so we never desync from the rule.
  static int _easternOffsetHours(DateTime utc) {
    final year = utc.year;
    final dstStart = _utcInstantOfLocal(year, 3, _nthSunday(year, 3, 2), 2, 0);
    final dstEnd = _utcInstantOfLocal(year, 11, _nthSunday(year, 11, 1), 2, 0);
    // DST window: [dstStart, dstEnd) interpreted as UTC instants where the
    // local clock is currently advanced by an hour. Outside the window we
    // sit on EST (UTC-5); inside we sit on EDT (UTC-4).
    final inDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
    return inDst ? -4 : -5;
  }

  /// nth Sunday of a month — e.g. (2026, 3, 2) → second Sunday of March 2026.
  static int _nthSunday(int year, int month, int n) {
    // Day-of-week for the 1st of the month, Sunday = 7 in Dart.
    final firstDow = DateTime.utc(year, month, 1).weekday;
    // Days to the first Sunday from the 1st.
    final daysToFirstSunday = (7 - firstDow) % 7 + 1;
    return daysToFirstSunday + (n - 1) * 7;
  }

  /// Compute the UTC instant that corresponds to a given wall-clock time
  /// in Eastern, assuming EST (UTC-5). Used only for DST transition
  /// boundaries where the offset switch happens.
  static DateTime _utcInstantOfLocal(
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    // At the moment of transition the local clock is on EST (UTC-5) and
    // jumps to EDT, or vice versa. Either way, treat the boundary as if
    // the local clock had been EST when scheduling, which is enough to
    // bracket the DST window.
    return DateTime.utc(year, month, day, hour + 5, minute);
  }

  /// Convert a [DateTime] (UTC or local) into a Dart DateTime whose
  /// fields read as Eastern wall-clock. The returned instance is *not*
  /// timezone-aware — it's a "naive" carrier of EST/EDT values that's
  /// safe to pass to [DateFormat] for display.
  static DateTime toEastern(DateTime dt) {
    final utc = dt.isUtc ? dt : dt.toUtc();
    final offset = _easternOffsetHours(utc);
    return utc.add(Duration(hours: offset));
  }

  /// Eastern wall-clock label like "Jun 1, 2026 4:32 PM EDT". Includes
  /// the abbreviation so the user knows the time zone explicitly.
  static String dateTime(DateTime dt) {
    final utc = dt.isUtc ? dt : dt.toUtc();
    final eastern = toEastern(utc);
    final abbr = _easternOffsetHours(utc) == -4 ? 'EDT' : 'EST';
    return '${DateFormat('MMM d, yyyy h:mm a').format(eastern)} $abbr';
  }

  /// Eastern date label like "Jun 1, 2026" — no timezone suffix because
  /// a calendar date doesn't shift across the DST boundary day.
  static String date(DateTime dt) {
    return DateFormat('MMM d, yyyy').format(toEastern(dt));
  }
}
