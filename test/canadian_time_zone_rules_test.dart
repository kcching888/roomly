import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('Vancouver remains UTC-7 after November 2026', () {
    final location = tz.getLocation('America/Vancouver');
    for (final date in [DateTime.utc(2026, 11, 15, 18), DateTime.utc(2027, 1, 15, 18)]) {
      expect(tz.TZDateTime.from(date, location).timeZoneOffset,
        const Duration(hours: -7));
    }
  });

  test('Edmonton uses Alberta Time UTC-6 after November 2026', () {
    final location = tz.getLocation('America/Edmonton');
    for (final date in [DateTime.utc(2026, 11, 15, 18), DateTime.utc(2027, 1, 15, 18)]) {
      expect(tz.TZDateTime.from(date, location).timeZoneOffset,
        const Duration(hours: -6));
    }
  });

  test('Historical Vancouver and Edmonton winter offsets are preserved', () {
    final winter = DateTime.utc(2025, 1, 15, 18);
    expect(tz.TZDateTime.from(winter, tz.getLocation('America/Vancouver')).timeZoneOffset,
      const Duration(hours: -8));
    expect(tz.TZDateTime.from(winter, tz.getLocation('America/Edmonton')).timeZoneOffset,
      const Duration(hours: -7));
  });
}
