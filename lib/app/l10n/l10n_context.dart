import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// `context.l10n.homeTabToday` instead of `AppLocalizations.of(context)!.…`.
///
/// `nullable-getter: false` in `l10n.yaml` is what makes the `!` unnecessary;
/// this extension is what makes the call site short enough that nobody is
/// tempted to hardcode the string instead.
extension AppL10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
