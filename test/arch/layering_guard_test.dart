@Tags(<String>['arch'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture rules, enforced by reading the source.
///
/// Nothing else in the repo can check these: the analyzer has no concept of a
/// layer, and a violation compiles perfectly well right up until the day
/// somebody tries to unit-test the domain and discovers it needs a Flutter
/// binding.
void main() {
  final Directory lib = Directory('lib');

  setUpAll(() {
    // ⚠️ Guard the guard. A rule that silently scans nothing passes forever.
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'Run tests from the package root; lib/ was not found.',
    );
  });

  group('pure Dart layers', () {
    const List<String> pureDirectories = <String>[
      'lib/core/time',
      'lib/core/clock/clock.dart',
      'lib/features/tasks/domain',
      'lib/features/extraction/domain',
      'lib/features/settings/domain',
      'lib/features/usage/domain',
      'lib/features/capture/domain',
      'lib/features/reminders/domain',
      'lib/features/subscription/domain',
    ];

    const List<String> forbidden = <String>[
      'package:flutter/',
      'package:drift/',
      'package:flutter_riverpod/',
      'package:sqlite3/',
      'package:go_router/',
    ];

    test('domain and time layers import no framework', () {
      final List<String> violations = <String>[];

      for (final String path in pureDirectories) {
        for (final File file in _dartFilesUnder(path)) {
          // `capture_state.dart` is the one file allowed a Flutter import, and
          // it is not: amplitude_track.dart carries the ChangeNotifier and
          // lives in pipeline/domain, which is not on this list.
          for (final String line in file.readAsLinesSync()) {
            if (!line.startsWith('import ')) continue;
            for (final String banned in forbidden) {
              if (line.contains(banned)) {
                violations.add('${file.path}: $line');
              }
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Domain layers must stay pure Dart:\n${violations.join('\n')}',
      );
    });
  });

  group('single plugin importer', () {
    // Each plugin is a MethodChannel or an FFI binding. A feature that reaches
    // one directly throws inside a Future under flutter_test, lands in an
    // AsyncValue.error, and the test passes having exercised nothing.
    const Map<String, String> owners = <String, String>{
      'package:record/': 'lib/core/audio/record_audio_recorder.dart',
      'package:whisper_ggml/': 'lib/core/speech/whisper_speech_recognizer.dart',
      'package:flutter_local_notifications/':
          'lib/core/notifications/flutter_local_notifier.dart',
      'package:permission_handler/':
          'lib/core/permissions/handler_permission_service.dart',
      'package:in_app_purchase/':
          'lib/core/purchases/store_purchase_gateway.dart',
      'package:llamadart/':
          'lib/features/extraction/data/llm_task_extractor.dart',
    };

    test('each platform plugin has exactly one importer', () {
      final Map<String, List<String>> importers = <String, List<String>>{};

      for (final File file in _dartFilesUnder('lib')) {
        for (final String line in file.readAsLinesSync()) {
          if (!line.startsWith('import ')) continue;
          for (final String package in owners.keys) {
            if (line.contains(package)) {
              importers.putIfAbsent(package, () => <String>[]).add(file.path);
            }
          }
        }
      }

      final List<String> violations = <String>[];
      owners.forEach((String package, String owner) {
        final List<String> found = importers[package] ?? <String>[];
        if (found.isEmpty) return; // Not wired up yet; not a layering problem.
        final Set<String> unexpected = found
            .where((String path) => path != owner)
            .toSet();
        if (unexpected.isNotEmpty) {
          violations.add('$package imported outside $owner by $unexpected');
        }
      });

      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('time discipline', () {
    test('DateTime.now() appears only in core/clock', () {
      final List<String> violations = <String>[];

      for (final File file in _dartFilesUnder('lib')) {
        if (file.path.startsWith('lib/core/clock/')) continue;
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('DateTime.now(') ||
              line.contains('DateTime.timestamp(')) {
            violations.add('${file.path}:${i + 1}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Take a Clock instead of reading the wall clock:\n'
            '${violations.join('\n')}',
      );
    });

    test('no Duration-based day arithmetic in time-sensitive code', () {
      // ⚠️ Duration is absolute elapsed time. Adding Duration(days: 1) to a
      // zoned date-time shifts the wall clock by an hour across a
      // daylight-saving boundary. A sibling app in this repo has exactly that
      // bug, and it is why this rule exists.
      final List<String> violations = <String>[];

      for (final String path in <String>[
        'lib/core/time',
        'lib/core/notifications',
        'lib/features/extraction/domain',
        'lib/features/reminders',
      ]) {
        for (final File file in _dartFilesUnder(path)) {
          final List<String> lines = file.readAsLinesSync();
          for (int i = 0; i < lines.length; i++) {
            final String line = lines[i];
            if (line.trimLeft().startsWith('//')) continue;
            if (RegExp(r'Duration\(\s*days:').hasMatch(line) ||
                RegExp(r'Duration\(\s*hours:\s*24').hasMatch(line)) {
              violations.add('${file.path}:${i + 1}  $line');
            }
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('logging', () {
    test('print() is never used', () {
      final List<String> violations = <String>[];

      for (final File file in _dartFilesUnder('lib')) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (RegExp(r'(^|[^.\w])print\(').hasMatch(line)) {
            violations.add('${file.path}:${i + 1}');
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('debugPrint is confined to the logger', () {
      final List<String> violations = <String>[];

      for (final File file in _dartFilesUnder('lib')) {
        if (file.path == 'lib/core/logging/log.dart') continue;
        for (final String line in file.readAsLinesSync()) {
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('debugPrint')) violations.add(file.path);
        }
      }

      expect(violations.toSet(), isEmpty, reason: violations.join('\n'));
    });
  });

  group('ink shape', () {
    test('every Material hosting an InkWell clips to a shape', () {
      // ⚠️ The regression this pins shipped to a device: pressing a rounded
      // button flashed a RECTANGLE.
      //
      // `InkWell.borderRadius` only shapes the splash that InkWell itself
      // creates. The ink is painted into the enclosing Material's layer, so a
      // highlight, a different splash factory, or a renderer that takes another
      // path will paint the Material's own bounds — square — over a rounded
      // control. Giving the Material a `borderRadius`/`shape` plus a
      // `clipBehavior` makes the shape a property of the surface rather than a
      // promise each ink feature has to keep.
      final List<String> violations = <String>[];

      for (final File file in _dartFilesUnder('lib/app/widgets')) {
        final String source = file.readAsStringSync();
        if (!source.contains('InkWell(') && !source.contains('InkResponse(')) {
          continue;
        }
        if (!source.contains('Material(')) continue;
        final bool shaped =
            source.contains('borderRadius:') || source.contains('shape:');
        final bool clipped = source.contains('clipBehavior:');
        if (!shaped || !clipped) {
          violations.add(
            '${file.path}: Material hosts an ink feature but '
            '${shaped ? '' : 'has no borderRadius/shape'}'
            '${!shaped && !clipped ? ' and ' : ''}'
            '${clipped ? '' : 'does not set clipBehavior'}',
          );
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('the sparkle splash is not reinstated', () {
      // `InkSparkle` is the Android 12 sparkle ripple. It renders as a bright
      // rectangular flash on a rounded control on real hardware, and a
      // glittering ripple appears nowhere in this design sheet.
      final List<String> violations = <String>[];
      for (final File file in _dartFilesUnder('lib')) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          // The comment in app_theme.dart that explains why it is gone must
          // not itself trip the guard.
          if (lines[i].trimLeft().startsWith('//')) continue;
          if (lines[i].contains('InkSparkle')) {
            violations.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('design tokens', () {
    test('no raw colours outside the theme', () {
      final List<String> violations = <String>[];
      final RegExp raw = RegExp(
        r'Color\(0x|Colors\.(white|black|grey|red|blue|green)',
      );

      for (final File file in _dartFilesUnder('lib')) {
        if (file.path.startsWith('lib/app/theme/')) continue;
        if (file.path.startsWith('lib/app/l10n/')) continue;
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          // Colors.transparent is not a colour decision; it is "do not paint".
          if (line.contains('Colors.transparent')) continue;
          if (raw.hasMatch(line)) {
            violations.add('${file.path}:${i + 1}  ${line.trim()}');
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('store compliance', () {
    test('no hardcoded prices in the subscription feature', () {
      // ⚠️ The paywall must render ProductDetails.price. A literal shows the
      // wrong currency to most of the world and is an App Review rejection.
      final List<String> violations = <String>[];
      final RegExp money = RegExp(
        r'[\u0022\u0027][\u0024\u20AC\u00A3\u00A5]\s?\d',
      );

      for (final File file in _dartFilesUnder('lib/features/subscription')) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].trimLeft().startsWith('//')) continue;
          if (money.hasMatch(lines[i])) {
            violations.add('${file.path}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });
}

List<File> _dartFilesUnder(String path) {
  final FileSystemEntity entity = FileSystemEntity.isDirectorySync(path)
      ? Directory(path)
      : File(path);
  if (entity is File) {
    return entity.existsSync() ? <File>[entity] : <File>[];
  }
  final Directory directory = entity as Directory;
  if (!directory.existsSync()) return <File>[];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .where((File file) => !file.path.endsWith('.g.dart'))
      .where((File file) => !file.path.endsWith('.freezed.dart'))
      .toList();
}
