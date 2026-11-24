import 'package:flutter/widgets.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders assistant chat Markdown with compact, chat-sized typography.
///
/// Headings stay only slightly larger than body text (chat bubbles, not a
/// document). Callers typically pass [ShadTheme]'s `small` style.
class AgentMarkdownBody extends StatelessWidget {
  const AgentMarkdownBody({
    super.key,
    required this.data,
    this.style,
  });

  final String data;
  final TextStyle? style;

  /// Body size used when [style] omits [TextStyle.fontSize].
  static const double bodyFontSize = 14;

  static Future<void> openLink(String url, String title) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      debugPrint('Agent markdown link failed ($title): $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shad = ShadTheme.of(context);
    final base = (style ?? shad.textTheme.small).copyWith(
      fontSize: style?.fontSize ?? bodyFontSize,
      height: style?.height ?? 1.4,
    );
    final bodySize = base.fontSize ?? bodyFontSize;
    final fg = base.color ?? shad.colorScheme.foreground;
    TextStyle heading(double size) => base.copyWith(
          color: fg,
          fontSize: size,
          fontWeight: FontWeight.w600,
          height: 1.3,
        );

    return GptMarkdownTheme(
      gptThemeData: GptMarkdownThemeData(
        brightness: shad.brightness,
        autoAddDividerLineAfterH1: false,
        linkColor: shad.colorScheme.primary,
        linkHoverColor: shad.colorScheme.primary,
        h1: heading(bodySize + 1),
        h2: heading(bodySize + 1),
        h3: heading(bodySize),
        h4: heading(bodySize),
        h5: heading(bodySize),
        h6: heading(bodySize),
        styleSheet: const GptMarkdownStyleSheet(
          blockSpacing: 6,
          heading: HeadingStyle(
            showDivider: false,
            padding: EdgeInsets.only(top: 2, bottom: 1),
          ),
        ),
      ),
      child: GptMarkdown(
        data,
        style: base,
        onLinkTap: openLink,
      ),
    );
  }
}
