import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:omniscope/widgets/agent_markdown_body.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('AgentMarkdownBody renders Markdown without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ShadApp(
        home: Center(
          child: SingleChildScrollView(
            child: AgentMarkdownBody(
              data: '## Brief\n\n- Point one\n- **bold figure**\n',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AgentMarkdownBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AgentMarkdownBody uses compact chat heading theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ShadApp(
        home: Center(
          child: SingleChildScrollView(
            child: AgentMarkdownBody(
              data: '# Title\n\nBody line\n',
              style: TextStyle(fontSize: AgentMarkdownBody.bodyFontSize),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final theme = tester
        .widget<GptMarkdownTheme>(find.byType(GptMarkdownTheme))
        .gptThemeData;
    expect(theme.autoAddDividerLineAfterH1, isFalse);
    expect(theme.h1?.fontSize, AgentMarkdownBody.bodyFontSize + 1);
    expect(theme.h2?.fontSize, AgentMarkdownBody.bodyFontSize + 1);
    expect(
      theme.styleSheet.blockSpacing,
      6,
      reason: 'chat replies should use tighter block spacing',
    );
  });
}
