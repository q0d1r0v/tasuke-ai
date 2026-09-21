import 'dart:io';

/// Helpers for the tests that read the native build files off disk.
///
/// These four tests are the only thing on a Linux machine that can check the
/// Android manifest, the Gradle script, the iOS plists and the privacy
/// manifest. There is no Xcode here and a Gradle build is off limits, so
/// "assert the text of the file" is not laziness — it is the entire available
/// surface. Everything they guard fails at upload time or on a device, which is
/// the most expensive place to find out.

/// Reads a file relative to the package root, failing with a path rather than a
/// `FileSystemException` when it has moved.
String readProjectFile(String relativePath) {
  final File file = File(relativePath);
  if (!file.existsSync()) {
    throw StateError(
      'Expected $relativePath to exist (cwd: ${Directory.current.path}). '
      'If it moved, the platform tests must move with it.',
    );
  }
  return file.readAsStringSync();
}

/// Strips `<!-- … -->` before asserting anything about an XML file.
///
/// ⚠️ Not optional, and the reason these tests have a helper file at all.
///
/// Every one of these files documents the keys it deliberately does NOT
/// declare — `USE_EXACT_ALARM`, `NSPhotoLibraryUsageDescription`,
/// `UIBackgroundModes` — by naming them in a comment that explains why. A
/// `contains('USE_EXACT_ALARM')` check would match the explanation and report
/// the file as broken precisely because it is well documented, which trains the
/// next person to delete the comment.
String stripXmlComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

/// The value element that follows `<key>[key]</key>`, or null when the key is
/// absent. `<true/>` comes back as `<true/>`; `<string>x</string>` as `x`.
String? plistValue(String plist, String key) {
  final RegExpMatch? match = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*(<[a-z]+\\s*/>|<([a-z]+)>([\\s\\S]*?)</\\2>)',
  ).firstMatch(plist);
  if (match == null) {
    return null;
  }
  return match.group(3) ?? match.group(1);
}

bool plistHasKey(String plist, String key) =>
    RegExp('<key>${RegExp.escape(key)}</key>').hasMatch(plist);

/// Collapses XML to one space between tokens.
///
/// ⚠️ Native config files are rewritten by codegen — `flutter_native_splash`
/// and `flutter_launcher_icons` both reflow attributes onto their own lines.
/// A test that matches the raw text then fails on a formatting change while the
/// manifest still declares exactly the same thing, which trains everyone to
/// ignore it. Every assertion here is about content, so every assertion reads
/// the collapsed form.
String collapseXmlWhitespace(String source) =>
    source.replaceAll(RegExp(r'\s+'), ' ').replaceAll(' />', '/>');
