import 'dart:io';

// ⚠️ `integration_test_driver_extended.dart`, not `integration_test_driver.dart`.
// Only the extended driver accepts `onScreenshot`; the plain one compiles to
// "No named parameter with the name 'onScreenshot'", which reads like a version
// problem rather than the wrong import.
import 'package:integration_test/integration_test_driver_extended.dart';

/// The host half of `flutter drive`.
///
/// ⚠️ Bare `integrationDriver()` runs the test and writes **nothing**: the
/// screenshot bytes come back over the wire and are dropped unless an
/// `onScreenshot` handler takes them. The run is green either way, which is why
/// it looks like the capture silently did nothing.
Future<void> main() => integrationDriver(
  onScreenshot:
      (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final File file = File('store/screenshots/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        stdout.writeln('screenshot: ${file.path} (${bytes.length} bytes)');
        return true;
      },
);
