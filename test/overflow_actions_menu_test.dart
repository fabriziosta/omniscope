import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/widgets/app_tooltip.dart';
import 'package:omniscope/widgets/overflow_actions_menu.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('OverflowActionsMenu opens and taps action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      ShadApp(
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: BrandColors.lightScheme(),
        ),
        home: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Center(
            child: OverflowActionsMenu(
              actions: [
                OverflowAction(
                  label: 'Rename',
                  icon: LucideIcons.pencil,
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('menu inside AppTooltip + GestureDetector like chat tile',
      (tester) async {
    var renamed = false;
    await tester.pumpWidget(
      ShadApp(
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: BrandColors.lightScheme(),
        ),
        home: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Center(
            child: SizedBox(
              width: 320,
              child: Builder(
                builder: (context) {
                  final theme = ShadTheme.of(context);
                  return AppTooltip(
                    message: 'Chat title',
                    wrapDetector: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          child: Row(
                            children: [
                              const Expanded(child: Text('Chat title')),
                              OverflowActionsMenu(
                                actions: [
                                  OverflowAction(
                                    label: 'Rename',
                                    icon: LucideIcons.pencil,
                                    onTap: () => renamed = true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(renamed, isTrue);
  });

  testWidgets('RowActionCluster overflow on narrow width', (tester) async {
    var investigated = false;
    await tester.pumpWidget(
      ShadApp(
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: BrandColors.lightScheme(),
        ),
        home: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: MediaQuery(
            // Force collapse regardless of the test surface size.
            data: const MediaQueryData(size: Size(390, 844)),
            child: Center(
              child: RowActionCluster(
                actions: [
                  OverflowAction(
                    label: 'Investigate',
                    icon: LucideIcons.sparkles,
                    onTap: () => investigated = true,
                  ),
                ],
                inlineChildren: const [SizedBox(width: 44, height: 44)],
                child: const Text(r'$100.00'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
    await tester.pumpAndSettle();
    expect(find.text('Investigate'), findsOneWidget);
    await tester.tap(find.text('Investigate'));
    await tester.pumpAndSettle();
    expect(investigated, isTrue);
  });
}
