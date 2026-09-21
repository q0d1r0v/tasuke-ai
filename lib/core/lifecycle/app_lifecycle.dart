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
/// A `StreamProvider<void>` rather than a listener each caller installs: one
/// [AppLifecycleListener] for the app, many watchers.
final StreamProvider<void> appResumedProvider = StreamProvider<void>((Ref ref) {
  final StreamController<void> resumes = StreamController<void>.broadcast();
  final AppLifecycleListener listener = AppLifecycleListener(
    onResume: () => resumes.add(null),
  );
  ref.onDispose(() {
    listener.dispose();
    unawaited(resumes.close());
  });
  return resumes.stream;
});
