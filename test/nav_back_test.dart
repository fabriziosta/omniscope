import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/widgets/in_tab_back.dart';
import 'package:omniscope/widgets/master_detail_shell.dart';
import 'package:omniscope/widgets/nav_back_button.dart';
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
    testWidgets('shows NavBackButton with parent label when showBack',
        (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        ShadApp(
          home: MasterDetailContentPane(
            title: 'Indices',
            subtitle: 'Grouped by exchange.',
            showBack: true,
            backLabel: 'Markets',
            onBack: () => tapped = true,
            body: const SizedBox.expand(),
          ),
        ),
      );

      expect(find.text('Markets'), findsOneWidget);
      expect(find.text('Indices'), findsOneWidget);
      expect(find.text('Back'), findsNothing);

      await tester.tap(find.byType(NavBackButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('hides back control when showBack is false', (tester) async {
      await tester.pumpWidget(
        const ShadApp(
          home: MasterDetailContentPane(
            title: 'Indices',
            subtitle: 'Grouped by exchange.',
            body: SizedBox.expand(),
          ),
        ),
      );

      expect(find.byType(NavBackButton), findsNothing);
      expect(find.text('Indices'), findsOneWidget);
    });
  });
}
