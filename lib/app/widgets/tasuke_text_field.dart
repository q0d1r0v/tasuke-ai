import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// The app's only text input.
///
/// Thin on purpose: every visual decision already lives in
/// `TasukeTheme.light().inputDecorationTheme`, and a field that restates the
/// border here is a field that stops matching the others.
class TasukeTextField extends StatelessWidget {
  const TasukeTextField({
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.prefix,
    this.suffix,
    super.key,
  });

  final TextEditingController controller;
  final String? hint;

  /// Grows to this many lines, then scrolls. Null is not offered: an unbounded
  /// field inside a scroll view has no height the layout can agree on.
  final int maxLines;

  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final Widget? prefix;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      cursorColor: TasukeColors.primary,
      style: TasukeTypography.bodyMd.copyWith(color: TasukeColors.ink),
      // Sentences, not `words`: task titles are spoken phrases, and word
      // capitalisation turns "call the dentist" into a headline.
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
      ),
    );
  }
}
