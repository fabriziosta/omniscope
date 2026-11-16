import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
