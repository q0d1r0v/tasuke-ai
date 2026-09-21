@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';

import '_harness.dart';

/// Pixel comparisons against the design sheet.
///
/// ⚠️ Tagged `golden` and excluded from the default run on purpose. The default
/// comparator is an exact match and the headless rasteriser does not render
/// `BoxShadow` identically across machines, so a font or engine difference is a
/// red build with nothing useful to look at. Design drift is worth catching; it
/// is not worth blocking every unrelated change on.
///
/// Regenerate with:  flutter test --tags golden --update-goldens
void main() {
  Future<void> golden(
    WidgetTester tester,
    String name,
    Widget child, {
    double width = 375,
  }) async {
    await pumpWidgetUnderTest(
      tester,
      Padding(
        padding: const EdgeInsets.all(TasukeSpacing.gutter),
        child: child,
      ),
      surface: Size(width, 812),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
    await tearDownTree(tester);
  }

  testWidgets('buttons', (WidgetTester tester) async {
    await golden(
      tester,
      'buttons',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PrimaryButton(label: 'Save Tasks', onPressed: () {}),
          const SizedBox(height: TasukeSpacing.md),
          const PrimaryButton(label: 'Disabled', onPressed: null),
          const SizedBox(height: TasukeSpacing.md),
          PrimaryButton(label: 'Busy', busy: true, onPressed: () {}),
          const SizedBox(height: TasukeSpacing.md),
          SecondaryButton(label: 'Cancel', onPressed: () {}),
          const SizedBox(height: TasukeSpacing.md),
          DangerButton(label: 'Stop', filled: true, onPressed: () {}),
          const SizedBox(height: TasukeSpacing.md),
          DangerButton(label: 'Delete Task', onPressed: () {}),
        ],
      ),
    );
  });

  testWidgets('task list tile', (WidgetTester tester) async {
    await golden(
      tester,
      'task_list_tile',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TaskListTile(
            task: makeTask(title: 'Design app UI'),
            relativeDayLabel: 'Today',
            timeLabel: '10:00 AM',
            onToggle: (_) {},
          ),
          const SizedBox(height: TasukeSpacing.cardGap),
          TaskListTile(
            task: makeTask(title: 'Send the build to James'),
            relativeDayLabel: 'Today',
            timeLabel: '3:00 PM',
            onToggle: (_) {},
          ),
          const SizedBox(height: TasukeSpacing.cardGap),
          TaskListTile(
            task: makeTask(title: 'Buy groceries', completed: true),
            relativeDayLabel: 'Apr 23',
            timeLabel: 'All day',
            onToggle: (_) {},
          ),
        ],
      ),
    );
  });

  testWidgets('settings group', (WidgetTester tester) async {
    await golden(
      tester,
      'settings_group',
      SettingsGroup(
        children: <Widget>[
          SettingsRow(
            title: 'Notifications',
            leading: const IconTile(
              icon: Icon(Icons.notifications_none_rounded),
            ),
            showChevron: false,
            trailing: TasukeSwitch(value: true, onChanged: (_) {}),
          ),
          SettingsRow(
            title: 'Language',
            leading: const IconTile(icon: Icon(Icons.language_rounded)),
            trailing: const Text('English'),
          ),
          SettingsRow(
            title: 'Subscription',
            leading: const IconTile(
              icon: Icon(Icons.workspace_premium_outlined),
            ),
            isLast: true,
            trailing: const Text('Free Plan'),
          ),
        ],
      ),
    );
  });

  testWidgets('permission cards', (WidgetTester tester) async {
    await golden(
      tester,
      'permission_cards',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PermissionCard(
            title: 'Microphone',
            subtitle: 'To record your voice',
            icon: const Icon(Icons.mic_none_rounded),
            state: PermissionState.notDetermined,
            onTap: () {},
          ),
          const SizedBox(height: TasukeSpacing.cardGap),
          PermissionCard(
            title: 'Notifications',
            subtitle: 'To remind you about your tasks',
            icon: const Icon(Icons.notifications_none_rounded),
            state: PermissionState.granted,
            onTap: () {},
          ),
        ],
      ),
    );
  });

  testWidgets('plan cards', (WidgetTester tester) async {
    await golden(
      tester,
      'plan_cards',
      Row(
        children: <Widget>[
          Expanded(
            child: PlanCard(
              title: 'Monthly',
              price: r'$4.99',
              period: '1 month',
              selected: true,
              onTap: () {},
            ),
          ),
          const SizedBox(width: TasukeSpacing.cardGap),
          Expanded(
            child: PlanCard(
              title: 'Yearly',
              price: r'$39.99',
              period: '1 year',
              badge: 'Save 33%',
              selected: false,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  });

  testWidgets('states', (WidgetTester tester) async {
    await golden(
      tester,
      'states',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const EmptyState(
            title: 'Nothing for today',
            message: "Tap the microphone and say what's on your mind.",
            icon: Icons.mic_none_rounded,
          ),
          const SizedBox(height: TasukeSpacing.xxl),
          ErrorState(
            title: "We didn't catch that",
            message: 'Try again a little closer to the microphone.',
            actionLabel: 'Try again',
            onRetry: () {},
            secondaryLabel: 'Type a task instead',
            onSecondary: () {},
          ),
        ],
      ),
    );
  });

  testWidgets('brand', (WidgetTester tester) async {
    await golden(
      tester,
      'brand',
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TasukeLogo(size: 96),
          SizedBox(height: TasukeSpacing.xxl),
          TasukeBanner(
            message: 'Reminders may arrive a few minutes late on this device.',
            icon: Icons.info_outline_rounded,
            tone: BannerTone.warning,
          ),
        ],
      ),
    );
  });

  testWidgets('segmented tabs and chips', (WidgetTester tester) async {
    await golden(
      tester,
      'tabs',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SegmentedTabs(
            labels: const <String>['Today', 'Upcoming', 'Completed'],
            selected: 0,
            onSelected: (_) {},
          ),
          const SizedBox(height: TasukeSpacing.xl),
          DateChip(dateLabel: 'Tomorrow', timeLabel: '3:00 PM', onTap: () {}),
          const SizedBox(height: TasukeSpacing.md),
          const DateChip(dateLabel: 'Friday', timeLabel: 'All day'),
          const SizedBox(height: TasukeSpacing.xl),
          DashedAddRow(label: 'Add another task', onTap: () {}),
        ],
      ),
    );
  });

  testWidgets('paywall stack on the smallest phone', (
    WidgetTester tester,
  ) async {
    // ⚠️ 320pt wide on purpose. Every store-required disclosure — period,
    // price, auto-renew, Restore, both legal links — has to be reachable on the
    // smallest supported phone, and this is the golden that proves it.
    await golden(
      tester,
      'paywall_small_320',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CrownHeader(
            title: 'Tasuke Pro',
            subtitle: 'Unlock your full potential',
          ),
          const SizedBox(height: TasukeSpacing.xl),
          const BenefitRow(label: 'Unlimited voice processing'),
          const BenefitRow(label: 'Multiple tasks from one voice input'),
          const BenefitRow(label: 'Advanced AI processing'),
          const SizedBox(height: TasukeSpacing.xl),
          PrimaryButton(label: 'Subscribe', onPressed: () {}),
          const SizedBox(height: TasukeSpacing.md),
          TextLinkButton(label: 'Restore Purchases', onPressed: () {}),
        ],
      ),
      width: 320,
    );
  });
}
