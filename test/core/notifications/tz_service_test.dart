import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/notifications/tz_service.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:timezone/timezone.dart' as tz;

Future<TzService> serviceIn(String zone) async {
  final TzService service = TzService(lookup: () async => zone);
  await service.initialise();
  return service;
}

void main() {
  group('shiftDays', () {
    test('keeps the wall clock across a spring-forward boundary', () async {
      final TzService service = await serviceIn('America/New_York');
      final tz.Location newYork = tz.getLocation('America/New_York');

      // 09:00 on 7 March 2026 (EST) plus one calendar day is 09:00 on the 8th
      // (EDT) — the same time on the user's clock, 23 absolute hours later.
      final tz.TZDateTime before = tz.TZDateTime(newYork, 2026, 3, 7, 9);
      final tz.TZDateTime after = TzService.shiftDays(before, 1);

      expect(after.hour, 9);
      expect(after.day, 8);
      expect(
        after.difference(before),
        const Duration(hours: 23),
        reason: 'the wall clock is preserved, so the elapsed time is not',
      );
      await service.dispose();
    });

    test('is what Duration arithmetic would have got wrong', () async {
      final TzService service = await serviceIn('America/New_York');
      final tz.Location newYork = tz.getLocation('America/New_York');
      final tz.TZDateTime before = tz.TZDateTime(newYork, 2026, 3, 7, 9);

      // The bug this helper exists to prevent, stated as a test so nobody
      // "simplifies" shiftDays back into it.
      expect(before.add(const Duration(hours: 24)).hour, 10);
      expect(TzService.shiftDays(before, 1).hour, 9);
      await service.dispose();
    });
  });

  group('zone changes', () {
    test('emit only when the zone actually differs', () async {
      String zone = 'Asia/Tashkent';
      final TzService service = TzService(lookup: () async => zone);
      final List<String> seen = <String>[];
      service.zoneChanges.listen(seen.add);

      await service.initialise();
      expect(await service.refresh(), isFalse);

      zone = 'Asia/Tokyo';
      expect(await service.refresh(), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(seen, <String>['Asia/Tashkent', 'Asia/Tokyo']);
      expect(service.zoneName, 'Asia/Tokyo');
      await service.dispose();
    });

    test('an unknown zone name is ignored rather than fatal', () async {
      String zone = 'Asia/Tashkent';
      final TzService service = TzService(lookup: () async => zone);
      await service.initialise();

      zone = 'Mars/Olympus_Mons';
      expect(await service.refresh(), isFalse);
      expect(service.zoneName, 'Asia/Tashkent');
      await service.dispose();
    });

    test('a lookup that throws leaves the previous zone in place', () async {
      final TzService service = TzService(
        lookup: () async => throw StateError('no platform channel here'),
      );
      await service.initialise();

      expect(service.zoneName, 'UTC');
      expect(await service.refresh(), isFalse);
      await service.dispose();
    });
  });

  group('resolve', () {
    test('falls back to UTC for a zone the database does not carry', () async {
      final TzService service = await serviceIn('Asia/Tashkent');

      final tz.TZDateTime at = service.resolve(
        LocalDateTime(LocalDate(2026, 9, 21), const LocalTimeOfDay.hm(9, 0)),
        zoneName: 'Mars/Olympus_Mons',
      );

      expect(at.timeZoneOffset, Duration.zero);
      expect(at.hour, 9);
      await service.dispose();
    });
  });
}
