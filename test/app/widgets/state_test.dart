import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

import '_harness.dart';

void main() {
  group('AsyncValueView', () {
    testWidgets('renders data', (WidgetTester tester) async {
      await pumpWidgetUnderTest(
        tester,
        AsyncValueView<String>(
          value: const AsyncValue<String>.data('12 tasks'),
          data: (String value) => Text(value),
        ),
      );

      expect(find.text('12 tasks'), findsOneWidget);
    });

    testWidgets('falls back to LoadingState, and takes an override', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        AsyncValueView<String>(
          value: const AsyncValue<String>.loading(),
          data: (String value) => Text(value),
        ),
      );
      expect(find.byType(LoadingState), findsOneWidget);

      await pumpWidgetUnderTest(
        tester,
        AsyncValueView<String>(
          value: const AsyncValue<String>.loading(),
          loading: const Text('one moment'),
          data: (String value) => Text(value),
        ),
      );
      expect(find.text('one moment'), findsOneWidget);

      await tearDownTree(tester);
    });

    testWidgets('an error with no handler shows the generic copy', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        AsyncValueView<String>(
          value: AsyncValue<String>.error(Exception('boom'), StackTrace.empty),
          data: (String value) => Text(value),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      // Never an ErrorState here: there is no retry to offer, and a button
      // that cannot retry is a button that lies.
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('an error handler is given the error and the stack', (
      WidgetTester tester,
    ) async {
      Object? seen;
      await pumpWidgetUnderTest(
        tester,
        AsyncValueView<String>(
          value: AsyncValue<String>.error('no mic', StackTrace.empty),
          data: (String value) => Text(value),
          error: (Object e, StackTrace _) {
            seen = e;
            return Text('$e');
          },
        ),
      );

      expect(seen, 'no mic');
      expect(find.text('no mic'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('shows a title, a message and an optional action', (
      WidgetTester tester,
    ) async {
      int actions = 0;
      await pumpWidgetUnderTest(
        tester,
        EmptyState(
          title: 'Nothing for today',
          message: "Tap the microphone and say what's on your mind.",
          actionLabel: 'Speak',
          icon: Icons.checklist_rounded,
          onAction: () => actions++,
        ),
      );

      expect(find.text('Nothing for today'), findsOneWidget);
      expect(find.byType(IconTile), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton));
      expect(actions, 1);
    });

    testWidgets('has no button when it has nothing to do', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const EmptyState(title: 'Nothing completed yet'),
      );

      expect(find.byType(PrimaryButton), findsNothing);
      expect(find.byType(IconTile), findsNothing);
    });
  });

  group('ErrorState', () {
    testWidgets('offers a retry, and a second way out when it has one', (
      WidgetTester tester,
    ) async {
      int retries = 0;
      int others = 0;
      await pumpWidgetUnderTest(
        tester,
        ErrorState(
          title: "We didn't catch that",
          message: 'Try again a little closer to the microphone.',
          actionLabel: 'Try again',
          onRetry: () => retries++,
          secondaryLabel: 'Type a task instead',
          onSecondary: () => others++,
        ),
      );

      await tester.tap(find.byType(PrimaryButton));
      await tester.tap(find.byType(TextLinkButton));
      expect(retries, 1);
      expect(others, 1);
    });

    testWidgets('leaves the secondary out when there is no callback', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        ErrorState(
          title: 'Something went wrong',
          actionLabel: 'Try again',
          onRetry: () {},
          secondaryLabel: 'Type a task instead',
        ),
      );

      expect(find.byType(TextLinkButton), findsNothing);
    });
  });

  group('LoadingState', () {
    testWidgets('spins, with or without something to read', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const LoadingState(message: 'Preparing your AI'),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Preparing your AI'), findsOneWidget);

      await tearDownTree(tester);
    });
  });

  group('PermissionDeniedState', () {
    testWidgets('sends the user wherever the caller says', (
      WidgetTester tester,
    ) async {
      int actions = 0;
      await pumpWidgetUnderTest(
        tester,
        PermissionDeniedState(
          title: 'Tasuke needs your microphone',
          message: 'It is used only while you are recording a task.',
          actionLabel: 'Open Settings',
          onAction: () => actions++,
        ),
      );

      await tester.tap(find.text('Open Settings'));
      expect(actions, 1);
    });
  });
}
