import 'package:flutter/widgets.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders assistant chat Markdown with brand-friendly text styling.
class AgentMarkdownBody extends StatelessWidget {
  const AgentMarkdownBody({
    super.key,
    required this.data,
    this.style,
  });

  final String data;
  final TextStyle? style;

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
    return GptMarkdown(
      data,
      style: style,
      onLinkTap: openLink,
    );
  }
}
