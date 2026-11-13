import 'package:omniscope/core/material_compat.dart' show SelectionArea;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/fade_page_route.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('FadePageRoute wraps page in SelectionArea', (tester) async {
    await tester.pumpWidget(
      const ShadApp(
        home: Text('seed'),
      ),
    );
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push<void>(
      FadePageRoute<void>(
        builder: (_) => const Center(child: Text('selectable copy')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SelectionArea), findsWidgets);
    expect(find.text('selectable copy'), findsOneWidget);
  });
}
