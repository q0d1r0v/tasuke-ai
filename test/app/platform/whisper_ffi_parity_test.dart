@Tags(<String>['arch'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android and iOS halves of the vendored whisper binding must export the
/// same symbols, the same way, and stream the same way.
///
/// ⚠️ This repo cannot compile the iOS half: there is no macOS and no Xcode
/// here, and CI has no iOS job. Every iOS defect therefore surfaces for the
/// first time on somebody's Mac, or — for this class of defect — not until a
/// TestFlight build is on a device, because a symbol that is stripped rather
/// than missing is not a build error. It is a `lookupFunction` that throws at
/// runtime, inside an isolate, with the app showing a spinner.
///
/// Reading both files from Dart is the only check available, so it is the one
/// that runs.
void main() {
  final File android = File(
    'packages/whisper_ggml/android/src/whisper/main.cpp',
  );
  final File ios = File(
    'packages/whisper_ggml/ios/Classes/whisper_flutter_plus.cpp',
  );

  /// The names `whisper_live.dart` and `whisper_controller.dart` resolve.
  const List<String> ffiEntryPoints = <String>[
    'request',
    'stream_start',
    'stream_feed',
    'stream_append',
    'stream_stop',
    'stream_abort',
  ];

  setUpAll(() {
    expect(android.existsSync(), isTrue, reason: 'run from the package root');
    expect(ios.existsSync(), isTrue, reason: 'run from the package root');
  });

  test('both platforms define FUNCTION_ATTRIBUTE the same way', () {
    const String gnu =
        '#define FUNCTION_ATTRIBUTE __attribute__((visibility("default"))) '
        '__attribute__((used))';
    expect(
      File('packages/whisper_ggml/android/src/whisper/main.h')
          .readAsStringSync(),
      contains(gnu),
    );
    expect(ios.readAsStringSync(), contains(gnu));
  });

  test('every FFI entry point is exported on both platforms', () {
    for (final String name in ffiEntryPoints) {
      for (final File source in <File>[android, ios]) {
        final List<String> lines = source.readAsLinesSync();
        final int at = lines.indexWhere(
          (String line) => line.contains('char *$name('),
        );
        expect(
          at,
          greaterThan(0),
          reason: '${source.path} does not define $name',
        );
        // Scan upward past blank lines and comments: the attribute is on its
        // own line, but formatting between it and the signature varies.
        int above = at - 1;
        while (above > 0 &&
            (lines[above].trim().isEmpty ||
                lines[above].trimLeft().startsWith('//'))) {
          above--;
        }
        expect(
          lines[above].trim(),
          'FUNCTION_ATTRIBUTE',
          reason:
              '${source.path}: $name is not marked FUNCTION_ATTRIBUTE. '
              'Without it, a build that turns on -fvisibility=hidden or links '
              'the pod statically ships an app whose every transcription '
              'throws, and nothing fails until then.',
        );
      }
    }
  });

  test('the live-transcription code is the same on both platforms', () {
    // Everything from the streaming banner down is hand-kept in step: the
    // gate, the decode parameters, the commit. A fix made to one copy only
    // ships to one platform, and iOS cannot be built here to notice.
    String streaming(File source) {
      final String text = source.readAsStringSync();
      final int at = text.indexOf('// Live (streaming) transcription.');
      expect(at, isNot(-1), reason: '${source.path} lost its banner');
      return text.substring(at);
    }

    expect(streaming(ios), streaming(android));
  });

  test('every stream_start key the Dart side sends is read natively', () {
    // A key the native side does not read is not an error there: nlohmann's
    // `value(key, default)` quietly returns the default. A misspelt
    // `prompt_on_previews` would put the prompt's cost back on every preview
    // with nothing to show for it but a slower Stop on a phone.
    final String dart = File('packages/whisper_ggml/lib/src/whisper_live.dart')
        .readAsStringSync();
    final int at = dart.indexOf("'start',");
    expect(at, isNot(-1), reason: "whisper_live.dart lost its 'start' message");
    final String body = dart.substring(at, dart.indexOf('}),', at));
    final List<String> keys = <String>[
      for (final RegExpMatch m in RegExp(r"'([a-z_]+)':").allMatches(body))
        m.group(1)!,
    ];
    expect(
      keys,
      containsAll(<String>['model', 'prompt_on_previews', 'initial_prompt']),
      reason: 'the regex stopped matching, not the code',
    );
    for (final File source in <File>[android, ios]) {
      final String text = source.readAsStringSync();
      final String streaming = text.substring(
        text.indexOf('// Live (streaming) transcription.'),
      );
      for (final String key in keys) {
        expect(
          streaming,
          anyOf(contains('value("$key"'), contains('contains("$key")')),
          reason: '${source.path}: stream_start never reads "$key"',
        );
      }
    }
  });

  test('the Dart side looks up exactly those symbols and no others', () {
    final String dart = File('packages/whisper_ggml/lib/src/whisper_live.dart')
        .readAsStringSync();
    // ⚠️ `\s*` after the paren: dart format wraps these calls, so the symbol
    // name is usually on the following line.
    final Iterable<RegExpMatch> looked = RegExp(
      r"lookupFunction<[^>]*>\(\s*'([a-z_]+)'",
    ).allMatches(dart);

    expect(
      looked,
      isNotEmpty,
      reason: 'the regex stopped matching, not the code',
    );
    for (final RegExpMatch match in looked) {
      expect(
        ffiEntryPoints,
        contains(match.group(1)),
        reason:
            '${match.group(1)} is resolved at runtime but is not on the list '
            'this test keeps exported',
      );
    }
  });
}
