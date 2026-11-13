import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/widgets/app_toast.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('showAppToast displays title and description', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: ShadButton(
                onPressed: () => showAppToast(
                  context,
                  title: 'Agent connected',
                  description: 'Market Research is saved for local paper runs.',
                ),
                child: const Text('Notify'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Notify'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Agent connected'), findsOneWidget);
    expect(
      find.text('Market Research is saved for local paper runs.'),
      findsOneWidget,
    );
  });
}
