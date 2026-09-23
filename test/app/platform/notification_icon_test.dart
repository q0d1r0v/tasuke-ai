import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/notifications/flutter_local_notifier.dart';

import 'native_source.dart';

/// Guards the reminder's small icon, which is the one Android resource the app
/// refers to only from Dart.
///
/// ⚠️ This is a release-only, device-only, fires-at-the-reminder-minute bug,
/// and it shipped once. The icon was `@mipmap/ic_launcher`; the release
/// resource shrinker deleted it because nothing it can read referred to it; the
/// plugin therefore never stored a default icon; and its alarm receiver crashed
/// in `setSmallIcon` at the exact minute of every reminder. Debug builds do not
/// shrink, so everything looked fine until a phone was holding a release build
/// at 6:11 PM. Three files have to agree, and nothing but this test checks it.
void main() {
  const String name = PluginNotificationHost.smallIcon;

  test('the icon is a drawable, not a mipmap', () {
    // flutter_local_notifications resolves the name with
    // getIdentifier(name, "drawable", …). A mipmap never resolves there.
    expect(name, isNot(contains('/')));
    expect(name, isNot(startsWith('@')));
  });

  test('the drawable exists', () {
    final String xml = stripXmlComments(
      readProjectFile('android/app/src/main/res/drawable/$name.xml'),
    );
    expect(xml, contains('<vector'));
  });

  test('the drawable is alpha-only white, so it is not a white square', () {
    final String xml = stripXmlComments(
      readProjectFile('android/app/src/main/res/drawable/$name.xml'),
    );
    expect(xml, contains('android:strokeColor="#FFFFFFFF"'));
    expect(xml, contains('android:fillColor="#00000000"'));
  });

  test('the release resource shrinker is told to keep it', () {
    final String keep = stripXmlComments(
      readProjectFile('android/app/src/main/res/raw/keep.xml'),
    );
    expect(keep, contains('tools:keep='));
    expect(keep, contains('@drawable/$name'));
  });

  test('the notifier uses it both as default and per notification', () {
    final String source = readProjectFile(
      'lib/core/notifications/flutter_local_notifier.dart',
    );
    expect(source, contains('AndroidInitializationSettings(smallIcon)'));
    expect(source, contains('icon: smallIcon'));
    expect(source, isNot(contains('ic_launcher\')')));
  });
}
