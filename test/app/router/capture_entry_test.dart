import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// How the app gets INTO the capture flow — the half nothing tested.
///
/// ⚠️ The bug this guards against shipped, and looked like slowness.
///
/// The capture screens are moved by the router's redirect as the pipeline's
/// phase advances: /capture -> /capture/processing -> /capture/confirm. The
/// mic button opened the flow with `context.push('/capture')`. go_router hands
/// a top-level redirect the BASE location of the match list, and a pushed page
/// is not the base — so the redirect saw "/home", its capture rule never
/// matched, and the phase advanced underneath a Recording screen that could
/// never leave. On a phone that read as "Finishing up..." for minutes. Whisper
/// had finished in two seconds.
///
/// Every router test passed throughout, because every one of them entered the
/// flow with `go`.
void main() {
  group('the go_router behaviour the capture flow depends on', () {
    /// A redirect with the same shape as the app's capture rule.
    GoRouter routerWith(ValueNotifier<int> phase, List<String> seen) {
      return GoRouter(
        initialLocation: '/home',
        refreshListenable: phase,
        redirect: (BuildContext context, GoRouterState state) {
          seen.add(state.matchedLocation);
          if (!state.matchedLocation.startsWith('/capture')) return null;
          final String want = phase.value == 0
              ? '/capture'
              : '/capture/processing';
          return state.matchedLocation == want ? null : want;
        },
        routes: <RouteBase>[
          GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
          GoRoute(
            path: '/capture',
            builder: (_, _) => const Text('RECORDING'),
            routes: <RouteBase>[
              GoRoute(
                path: 'processing',
                builder: (_, _) => const Text('PROCESSING'),
              ),
            ],
          ),
        ],
      );
    }

    testWidgets('a PUSHED page is invisible to the top-level redirect', (
      WidgetTester tester,
    ) async {
      // ⚠️ This test documents the trap, it does not guard our code. If a
      // go_router upgrade ever changes this, it fails — and then the choice of
      // `go` in HomeShell is worth revisiting rather than blindly keeping.
      final ValueNotifier<int> phase = ValueNotifier<int>(0);
      final List<String> seen = <String>[];
      final GoRouter router = routerWith(phase, seen);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      unawaited(router.push<void>('/capture'));
      await tester.pump();
      await tester.pump();
      expect(find.text('RECORDING'), findsOneWidget);

      seen.clear();
      phase.value = 1;
      await tester.pump();
      await tester.pump();

      expect(seen, everyElement('/home'), reason: 'the redirect never sees it');
      expect(
        find.text('RECORDING'),
        findsOneWidget,
        reason: 'and so the phase advances while the screen stays put',
      );
    });

    testWidgets('a page reached with GO is moved on by the redirect', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int> phase = ValueNotifier<int>(0);
      final GoRouter router = routerWith(phase, <String>[]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      router.go('/capture');
      await tester.pump();
      await tester.pump();
      expect(find.text('RECORDING'), findsOneWidget);

      phase.value = 1;
      await tester.pump();
      await tester.pump();

      expect(find.text('PROCESSING'), findsOneWidget);
      expect(find.text('RECORDING'), findsNothing);
    });
  });

  group('HomeShell enters the capture flow with go', () {
    // A source guard, in the style of test/arch/: the real mic path cannot be
    // pumped end to end under FakeAsync without deadlocking on stream teardown
    // (see redirect_test.dart group 4), so the one line that matters is pinned
    // where it lives.
    final String shell = File('lib/app/router/home_shell.dart')
        .readAsStringSync();

    test('capture destinations are opened with go', () {
      expect(
        shell,
        contains('if (destination.startsWith(kCapturePathPrefix)) {'),
      );
      // Through the router held before `begin`, whose wait can outlive the
      // shell's own context.
      expect(shell, contains('router.go(destination);'));
    });

    test('the wait for the last capture opens /capture with go too', () {
      expect(shell, contains('router.go(AppRoute.capture.path);'));
      expect(
        shell,
        isNot(matches(RegExp(r'push(<[^>]*>)?\(AppRoute\.capture'))),
        reason: 'a pushed /capture is invisible to the phase-driven redirect',
      );
    });

    test('a capture destination is never pushed', () {
      final int branch = shell.indexOf(
        'if (destination.startsWith(kCapturePathPrefix)) {',
      );
      final int elseAt = shell.indexOf('} else {', branch);
      expect(branch, greaterThan(0));
      expect(
        shell.substring(branch, elseAt),
        isNot(contains('push')),
        reason:
            'a pushed /capture is invisible to the phase-driven redirect, and '
            'the Recording screen then outlives the recording',
      );
    });
  });
}
