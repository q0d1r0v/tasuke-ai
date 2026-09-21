import 'package:flutter_test/flutter_test.dart';

import 'native_source.dart';

/// Guards `android/app/src/main/AndroidManifest.xml`.
///
/// Manifest mistakes are uniquely silent: a missing permission does not fail a
/// build, it makes one feature do nothing on one OS version. A permission that
/// should not be there does not fail a build either — it fails review, weeks
/// later, in a message that names a guideline and not a file.
void main() {
  late String manifest;
  late String strings;

  setUpAll(() {
    manifest = collapseXmlWhitespace(
      stripXmlComments(
        readProjectFile('android/app/src/main/AndroidManifest.xml'),
      ),
    );
    strings = readProjectFile('android/app/src/main/res/values/strings.xml');
  });

  String permission(String name) =>
      '<uses-permission android:name="android.permission.$name"/>';

  group('permissions', () {
    test('declares RECORD_AUDIO', () {
      expect(manifest, contains(permission('RECORD_AUDIO')));
    });

    test('declares POST_NOTIFICATIONS', () {
      // flutter_local_notifications 22.x does not merge this in. Without it,
      // requesting the permission on Android 13+ resolves false with no dialog
      // and every reminder is dropped in silence.
      expect(manifest, contains(permission('POST_NOTIFICATIONS')));
    });

    test('declares SCHEDULE_EXACT_ALARM', () {
      expect(manifest, contains(permission('SCHEDULE_EXACT_ALARM')));
    });

    test('does NOT declare USE_EXACT_ALARM', () {
      // ⚠️ The one negative assertion in this file that costs a release.
      //
      // USE_EXACT_ALARM is auto-granted, which makes it the tempting way to
      // avoid the permission screen — but Play restricts it to alarm-clock and
      // calendar apps and audits the declaration during review. Declaring it in
      // a productivity app is a rejection, and the rejection arrives after the
      // build has been uploaded and staged.
      expect(
        manifest,
        isNot(contains('USE_EXACT_ALARM')),
        reason:
            'USE_EXACT_ALARM is a Play policy violation for this app; '
            'SCHEDULE_EXACT_ALARM is the user-grantable permission to use.',
      );
    });

    test('declares RECEIVE_BOOT_COMPLETED', () {
      expect(manifest, contains(permission('RECEIVE_BOOT_COMPLETED')));
    });

    test('declares INTERNET', () {
      expect(manifest, contains(permission('INTERNET')));
    });

    test('declares nothing beyond those five', () {
      // The permission list is the whole privacy story and it has to stay
      // defensible on the Data safety form. A seventh permission appearing here
      // is a product decision, not a build detail.
      final Set<String> declared = RegExp(
        r'<uses-permission android:name="android\.permission\.([A-Z_]+)"',
      ).allMatches(manifest).map((RegExpMatch m) => m.group(1)!).toSet();

      expect(declared, <String>{
        'RECORD_AUDIO',
        'POST_NOTIFICATIONS',
        'SCHEDULE_EXACT_ALARM',
        'RECEIVE_BOOT_COMPLETED',
        'INTERNET',
      });
    });
  });

  group('flutter_local_notifications receivers', () {
    const String package = 'com.dexterous.flutterlocalnotifications';

    test('declares ScheduledNotificationReceiver', () {
      expect(manifest, contains('$package.ScheduledNotificationReceiver'));
    });

    test('declares ScheduledNotificationBootReceiver', () {
      expect(manifest, contains('$package.ScheduledNotificationBootReceiver'));
    });

    test('declares ActionBroadcastReceiver', () {
      expect(manifest, contains('$package.ActionBroadcastReceiver'));
    });

    test('the boot receiver listens for all four boot actions', () {
      // BOOT_COMPLETED alone loses every pending reminder on a fast-boot ROM
      // and on an app update — two cases that look like "the reminder just
      // never fired" and are almost impossible to reproduce deliberately.
      for (final String action in <String>[
        'android.intent.action.BOOT_COMPLETED',
        'android.intent.action.MY_PACKAGE_REPLACED',
        'android.intent.action.QUICKBOOT_POWERON',
        'com.htc.intent.action.QUICKBOOT_POWERON',
      ]) {
        expect(manifest, contains(action), reason: '$action is missing');
      }
    });
  });

  group('package visibility', () {
    test('has a <queries> block', () {
      expect(manifest, contains('<queries>'));
    });

    test('queries VIEW + https', () {
      // ⚠️ Without this, url_launcher's canLaunchUrl returns false on API 30+
      // on a phone that plainly has a browser, and the Privacy Policy row in
      // Settings silently does nothing — no error, no crash, no log line.
      final RegExpMatch? queries = RegExp(r'<queries>([\s\S]*?)</queries>')
          .firstMatch(manifest);
      expect(queries, isNotNull);

      final String body = queries!.group(1)!;
      expect(body, contains('android.intent.action.VIEW'));
      expect(body, contains('android:scheme="https"'));
    });
  });

  group('application', () {
    test('is labelled Tasuke AI, and strings.xml agrees', () {
      expect(manifest, contains('android:label="Tasuke AI"'));
      // Two places need the name and neither can reference the other: the
      // manifest label is what the launcher shows, @string/app_name is what the
      // system permission sheets use. A half-done rename ships an app called
      // "Tasuke AI" whose microphone prompt says something else.
      expect(strings, contains('<string name="app_name">Tasuke AI</string>'));
    });

    test('is portrait-only', () {
      expect(manifest, contains('android:screenOrientation="portrait"'));
    });
  });
}
