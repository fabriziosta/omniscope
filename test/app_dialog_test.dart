import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/widgets/app_dialog.dart';
import 'package:omniscope/widgets/overflow_actions_menu.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('showAppDialog focuses the primary text field', (tester) async {
    final controller = TextEditingController(text: 'Chat title');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: BrandColors.lightScheme(),
        ),
        home: Builder(
          builder: (context) {
            return ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Center(
                child: ShadButton(
                  onPressed: () {
                    showAppDialog<void>(
                      context: context,
                      builder: (context) => ShadDialog(
                        title: const Text('Rename chat'),
                        child: ShadInput(
                          controller: controller,
                          autofocus: true,
                          placeholder: const Text('Chat name'),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    // Two post-frame callbacks + dialog transition.
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);
  });

  testWidgets('Rename from overflow menu focuses the input', (tester) async {
    final controller = TextEditingController(text: 'Old name');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: BrandColors.lightScheme(),
        ),
        home: Builder(
          builder: (context) {
            return ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Center(
                child: OverflowActionsMenu(
                  actions: [
                    OverflowAction(
                      label: 'Rename',
                      icon: LucideIcons.pencil,
                      onTap: () {
                        showAppDialog<void>(
                          context: context,
                          builder: (context) => ShadDialog(
                            title: const Text('Rename chat'),
                            child: ShadInput(
                              controller: controller,
                              autofocus: true,
                              placeholder: const Text('Chat name'),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);
  });
}
