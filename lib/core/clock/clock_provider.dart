import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/time/local_date.dart';

/// The app's [Clock].
///
/// Everything that needs "now" watches this instead of calling
/// `DateTime.now()`, which is what lets a widget test pin the whole app to a
/// Tuesday in March by overriding one provider.
final Provider<Clock> clockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

/// Today, on the device's local calendar.
///
/// ⚠️ This is a cached value, not a ticking one. It is read once and then held
/// until something invalidates it — which is correct for a provider and wrong
/// for a user whose phone is open across midnight. Whoever owns the app
/// lifecycle must `ref.invalidate(todayProvider)` on resume and on a
/// day-boundary timer; without that, "Today" keeps meaning yesterday and every
/// overdue task quietly stays out of the list.
final Provider<LocalDate> todayProvider = Provider<LocalDate>(
  (Ref ref) => LocalDate.today(ref.watch(clockProvider).nowLocal()),
);
