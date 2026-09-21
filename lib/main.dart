import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override`, `ProviderListenable` or the
// `*Family` types from its main library — only from `misc.dart`. Naming any of
// them without this import is a `non_type_as_type_argument` error that reads
// like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/app/app.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge is mandatory on Android 15 (targetSdk 35+) with no opt-out, so
  // it is requested explicitly here rather than being a surprise on one OS
  // version. Every screen lays out against MediaQuery padding accordingly.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  // ⚠️ Loaded before the first frame on purpose: GoRouter.redirect is
  // synchronous and cannot await, and the onboarding and permissions-primer
  // flags are read inside it. A Future-backed store here means the guard reads
  // a stale value on the one frame that decides which screen the app opens on.
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const TasukeApp(),
    ),
  );
}
