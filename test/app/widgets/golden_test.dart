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
/// ⚠️ Tagged `golden` so that `tool/verify.sh` can leave it out of its run
/// (`--exclude-tags`), on purpose. The default comparator is an exact match
/// and the headless rasteriser does not render `BoxShadow` identically across
/// machines, so a font or engine difference is a red build with nothing useful
/// to look at. Design drift is worth catching; it is not worth blocking every
/// unrelated change on. `dart_test.yaml` only declares the tag and excludes
/// nothing, so a `flutter test` that names this directory runs these too.
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
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PlanCard(
            title: 'Monthly',
            price: r'$4.99',
            period: '1 month',
            selected: true,
            onTap: () {},
          ),
          const SizedBox(height: TasukeSpacing.cardGap),
          PlanCard(
            title: 'Yearly',
            price: r'$39.99',
            period: '1 year',
            badge: 'Save 33%',
            footnote: 'USD 3.33 per month, billed yearly',
            selected: false,
            onTap: () {},
          ),
          const SizedBox(height: TasukeSpacing.cardGap),
          // A long store string goes under the title at full size; it never
          // wraps, and it is not shrunk to squeeze in beside it.
          PlanCard(
            title: 'Yearly',
            price: 'UZS 499 000,00',
            period: '1 year',
            selected: false,
            onTap: () {},
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
    // 320pt wide on purpose: the header, benefit rows and buttons the paywall
    // is built from, on the smallest supported phone.
    //
    // ⚠️ Not the paywall, and not its copy. The labels are sample text from
    // before the benefits were cut to what Pro really unlocks; the real rows
    // are pinned by "promise only what Pro unlocks" in paywall_screen_test.
    // Nor does this prove the store-required disclosures fit (period, price,
    // auto-renew, both legal links: none is drawn here). paywall_screen_test
    // does that on the real screen at 320×568.
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
