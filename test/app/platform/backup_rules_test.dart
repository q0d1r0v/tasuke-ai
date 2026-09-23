import 'package:flutter_test/flutter_test.dart';

import 'native_source.dart';

/// Guards `android/app/src/main/res/xml/backup_rules.xml` (Android 11 and
/// below) and `data_extraction_rules.xml` (Android 12+).
///
/// Both fail silently. Over Google's 25 MB cloud-backup quota the whole app is
/// skipped, and one `<include>` turns a rule set into an allow-list that drops
/// the task database. Either way the user finds out on a new phone, with no
/// tasks, and there is no server to get them back from.
void main() {
  late String fullBackup;
  late String extraction;

  setUpAll(() {
    String read(String name) => collapseXmlWhitespace(
      stripXmlComments(readProjectFile('android/app/src/main/res/xml/$name')),
    );
    fullBackup = read('backup_rules.xml');
    extraction = read('data_extraction_rules.xml');
  });

  // The models directory under files/: the 57 MB whisper copy, which the app
  // re-creates from its own bundle.
  const String excludeModels = '<exclude domain="file" path="models"/>';

  String section(String xml, String tag) {
    final RegExpMatch? match = RegExp('<$tag>([\\s\\S]*?)</$tag>')
        .firstMatch(xml);
    expect(match, isNotNull, reason: '<$tag> is missing');
    return match!.group(1)!;
  }

  group('Android 11 and below', () {
    test('keeps the model directory out', () {
      expect(
        section(fullBackup, 'full-backup-content'),
        contains(excludeModels),
      );
    });

    test('has no <include>, so everything else stays in', () {
      expect(fullBackup, isNot(contains('<include')));
    });
  });

  group('Android 12 and up', () {
    test('keeps the model directory out of cloud backup', () {
      expect(section(extraction, 'cloud-backup'), contains(excludeModels));
    });

    test('and out of device transfer, like Android 11 and below', () {
      expect(section(extraction, 'device-transfer'), contains(excludeModels));
    });

    test('has no <include>, so everything else stays in', () {
      expect(extraction, isNot(contains('<include')));
    });
  });

  test('excludes nothing but the model directory', () {
    // The database (files/tasuke.sqlite plus -wal/-shm) and shared_prefs must
    // stay in. A broader exclude is how that quietly stops being true.
    for (final String xml in <String>[fullBackup, extraction]) {
      final Iterable<String> excludes = RegExp('<exclude [^>]*/>')
          .allMatches(xml)
          .map((RegExpMatch m) => m.group(0)!);
      expect(excludes.toSet(), <String>{excludeModels});
    }
  });
}
