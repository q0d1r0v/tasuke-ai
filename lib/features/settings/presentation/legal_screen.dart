import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

enum LegalDocument {
  privacy('assets/legal/privacy_en.md'),
  terms('assets/legal/terms_en.md');

  const LegalDocument(this.asset);

  final String asset;
}

/// Renders the bundled legal text.
///
/// ⚠️ Bundled, not linked. This app's entire premise is that it works with no
/// connection, and a Privacy Policy row that opens a dead page on a plane is a
/// bad look. Apple also expects the EULA to be reachable inside the binary.
/// The hosted copies exist too, for the store listings.
class LegalScreen extends StatefulWidget {
  const LegalScreen({required this.document, super.key});

  final LegalDocument document;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late Future<String> _text;

  @override
  void initState() {
    super.initState();
    _text = rootBundle.loadString(widget.document.asset);
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.document == LegalDocument.privacy
        ? context.l10n.legalPrivacyTitle
        : context.l10n.legalTermsTitle;

    return TasukeScaffold(
      title: title,
      showBack: true,
      child: FutureBuilder<String>(
        future: _text,
        builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              title: context.l10n.errorGenericTitle,
              message: context.l10n.errorGenericBody,
              actionLabel: context.l10n.actionRetry,
              onRetry: () => setState(() {
                _text = rootBundle.loadString(widget.document.asset);
              }),
            );
          }
          if (!snapshot.hasData) return const LoadingState();
          return _Markdown(source: snapshot.data!);
        },
      ),
    );
  }
}

/// A deliberately minimal Markdown renderer.
///
/// Headings, paragraphs and bullets are the only constructs the two legal
/// documents use, so pulling in a full Markdown package for them would add a
/// dependency — and its transitive HTML parser — to ship two static files.
class _Markdown extends StatelessWidget {
  const _Markdown({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    for (final String rawLine in source.split('\n')) {
      final String line = rawLine.trimRight();
      if (line.isEmpty) {
        children.add(const SizedBox(height: TasukeSpacing.md));
        continue;
      }
      if (line.startsWith('# ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: TasukeSpacing.sm),
            child: Text(line.substring(2), style: TasukeTypography.titleMd),
          ),
        );
      } else if (line.startsWith('## ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              top: TasukeSpacing.lg,
              bottom: TasukeSpacing.xs,
            ),
            child: Text(line.substring(3), style: TasukeTypography.titleSm),
          ),
        );
      } else if (line.startsWith('- ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: TasukeSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('•  ', style: TasukeTypography.bodyMd),
                Expanded(
                  child: Text(
                    line.substring(2),
                    style: TasukeTypography.bodyMd,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(Text(line, style: TasukeTypography.bodyMd));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
