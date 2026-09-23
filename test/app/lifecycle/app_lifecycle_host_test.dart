import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/lifecycle/app_lifecycle_host.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/lifecycle/app_lifecycle.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/core/notifications/tz_service.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';

/// Counts sweeps, so a test can say "the resume re-synced" out loud.
final class CountingScheduler implements ReminderScheduler {
  int syncs = 0;

  @override
  Future<SyncOutcome> sync() async {
    syncs++;
    return const SyncOutcome(scheduled: 0, cancelled: 0, exact: true);
  }

  @override
  Future<void> cancelAll() async {}
}

void main() {
  late MutableClock clock;
  late StreamController<int> resumes;
  late StreamController<String> zones;
  late CountingScheduler scheduler;
  late ProviderContainer container;
  int zoneLookups = 0;

  setUp(() {
    zoneLookups = 0;
    clock = MutableClock(DateTime(2026, 9, 21, 22));
    resumes = StreamController<int>.broadcast();
    zones = StreamController<String>.broadcast();
    scheduler = CountingScheduler();
  });

  tearDown(() async {
    await resumes.close();
    await zones.close();
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          clockProvider.overrideWithValue(clock),
          appResumedProvider.overrideWith((Ref ref) => resumes.stream),
          timezoneChangesProvider.overrideWith((Ref ref) => zones.stream),
          reminderSchedulerProvider.overrideWithValue(scheduler),
          tzServiceProvider.overrideWithValue(
            TzService(
              lookup: () async {
                zoneLookups++;
                return 'Asia/Tashkent';
              },
            ),
          ),
        ],
        child: const AppLifecycleHost(
          child: MaterialApp(home: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
    container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );
  }

  testWidgets('a resume rolls the day over — and does it EVERY time', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    expect(container.read(todayProvider), const LocalDate(2026, 9, 21));

    // First resume, two hours later: past midnight.
    clock.instant = DateTime(2026, 9, 22, 0, 30);
    resumes.add(1);
    await tester.pump();
    expect(container.read(todayProvider), const LocalDate(2026, 9, 22));
    expect(scheduler.syncs, 1);

    // ⚠️ THE assertion. `appResumedProvider` used to be a
    // `StreamProvider<void>`; riverpod compares AsyncValues structurally, so
    // every `AsyncData<void>(null)` equalled the last one and the listener
    // fired exactly ONCE per process. The app rescued its stale day on the
    // first resume of the morning and then went quiet — which looks identical
    // to working.
    clock.instant = DateTime(2026, 9, 23, 9);
    resumes.add(2);
    await tester.pump();
    expect(
      container.read(todayProvider),
      const LocalDate(2026, 9, 23),
      reason: 'the second resume must notify too',
    );
    expect(scheduler.syncs, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a resume re-reads the device timezone before re-syncing', (
    WidgetTester tester,
  ) async {
    // ⚠️ Android does not restart a live process on a zone change, and this
    // is the only re-read after startup. Without it a user who flew from
    // Tashkent to Tokyo kept resolving new reminders against Tashkent.
    await pumpHost(tester);
    expect(zoneLookups, 0);

    resumes.add(1);
    await tester.pump();

    expect(zoneLookups, 1);
    expect(scheduler.syncs, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the midnight timer rolls the day over with no resume at all', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    expect(container.read(todayProvider), const LocalDate(2026, 9, 21));

    // Two hours to midnight from 22:00. The phone stays awake in the user's
    // hand; nothing resumes because nothing was ever backgrounded.
    clock.instant = DateTime(2026, 9, 22, 0, 0, 1);
    await tester.pump(const Duration(hours: 2));

    expect(container.read(todayProvider), const LocalDate(2026, 9, 22));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a timezone change re-resolves the reminders', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    expect(scheduler.syncs, 0);

    zones.add('Europe/London');
    await tester.pump();

    expect(
      scheduler.syncs,
      1,
      reason:
          'every pending reminder is resolved against a zone, so one flight '
          'invalidates all of them at once',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('it leaves no timer behind', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    // The framework asserts on a pending timer at teardown; reaching here is
    // the assertion.
    expect(find.byType(AppLifecycleHost), findsNothing);
  });
}
