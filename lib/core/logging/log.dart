import 'package:flutter/foundation.dart';

/// Diagnostics.
///
/// Two rules, both of which the app's privacy promise depends on:
///
/// 1. **Nothing is printed in a release build.** Every method here compiles to
///    a no-op under `kReleaseMode`. `avoid_print` is on in
///    `analysis_options.yaml` and a guard test forbids `print(` anywhere in
///    `lib/`, so this is the only way anything reaches a log at all.
/// 2. **Transcripts and task titles are never logged, even in debug.** They are
///    the most sensitive thing the app holds. Pass them through [redact].
abstract final class Log {
  static void d(String message) {
    if (kReleaseMode) return;
    debugPrint('[tasuke] $message');
  }

  static void w(String message) {
    if (kReleaseMode) return;
    debugPrint('[tasuke][warn] $message');
  }

  static void e(String message, [Object? error, StackTrace? stack]) {
    if (kReleaseMode) return;
    debugPrint('[tasuke][error] $message${error == null ? '' : ' — $error'}');
    if (stack != null) debugPrintStack(stackTrace: stack);
  }

  /// Replaces user content with its shape.
  ///
  /// `redact("Send the build to James")` → `<text:23 chars>`. Enough to debug a
  /// length or an empty-string bug; useless to anyone reading a log.
  static String redact(String? value) {
    if (value == null) return '<null>';
    if (value.isEmpty) return '<empty>';
    return '<text:${value.length} chars>';
  }
}
