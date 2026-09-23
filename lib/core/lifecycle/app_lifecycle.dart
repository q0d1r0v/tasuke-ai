import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fires every time the app comes back to the foreground.
///
/// Three things go stale while the app is away and all of them are silent
/// failures: the device may have changed timezone (every pending reminder is
/// then off by the offset difference), the user may have flipped a permission
/// in the Settings app, and the OS may have dropped alarms during an update.
/// Something has to re-ask, and "when the user looks at the app again" is the
/// only moment that is both cheap and timely.
///
/// A `StreamProvider<int>` rather than a listener each caller installs: one
/// [AppLifecycleListener] for the app, many watchers.
///
/// ⚠️ `int`, and the value is a counter nobody reads. It must NOT be
/// `StreamProvider<void>`.
///
/// riverpod gates every listener behind `previous != next`, and
/// `AsyncValue`'s equality compares a structural record of (value, kind,
/// source). Two `AsyncData<void>(null)` values are equal, so a void stream
/// notifies on the FIRST resume and never again — the app would rescue its
/// stale day and its stale permissions exactly once per process and then go
/// quiet, which is indistinguishable from working.
final StreamProvider<int> appResumedProvider = StreamProvider<int>((Ref ref) {
  final StreamController<int> resumes = StreamController<int>.broadcast();
  int count = 0;
  final AppLifecycleListener listener = AppLifecycleListener(
    onResume: () => resumes.add(++count),
  );
  ref.onDispose(() {
    listener.dispose();
    unawaited(resumes.close());
  });
  return resumes.stream;
});
