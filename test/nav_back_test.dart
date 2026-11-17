import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/widgets/in_tab_back.dart';
import 'package:omniscope/widgets/master_detail_shell.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  group('InTabBackRegistry', () {
    test('arms and handles per tab', () {
      final registry = InTabBackRegistry();
      var markets = 0;
      var settings = 0;

      registry.setHandler(0, () => markets++);
      registry.setHandler(4, () => settings++);

      expect(registry.handle(0), isTrue);
      expect(markets, 1);
      expect(registry.handle(4), isTrue);
      expect(settings, 1);
      expect(registry.handle(2), isFalse);

      registry.setHandler(0, null);
      expect(registry.handle(0), isFalse);
    });
  });

  group('MasterDetailContentPane', () {
    testWidgets('shows burger menu that invokes onOpenMenu', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        ShadApp(
          home: MasterDetailContentPane(
            title: 'Indices',
            subtitle: 'Grouped by exchange.',
            onOpenMenu: () => tapped = true,
            body: const SizedBox.expand(),
          ),
        ),
      );

      expect(find.byType(MasterDetailMenuButton), findsOneWidget);
      expect(find.text('Indices'), findsOneWidget);

      await tester.tap(find.byType(MasterDetailMenuButton));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
