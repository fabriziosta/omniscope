import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/settings/display_settings.dart';
import 'package:omniscope/widgets/price_line_chart.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('shows empty history copy when fewer than 2 candles',
      (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: ChangeNotifierProvider(
          create: (_) => DisplaySettings(),
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: PriceLineChart(
              candles: [
                Candle(time: DateTime.utc(2026, 1, 1), close: 10),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Not enough history to chart'), findsOneWidget);
  });

  testWidgets('scrubs to show date and price readout', (tester) async {
    final candles = [
      Candle(time: DateTime.utc(2026, 1, 1), close: 100),
      Candle(time: DateTime.utc(2026, 1, 2), close: 110),
      Candle(time: DateTime.utc(2026, 1, 3), close: 105),
    ];
    await tester.pumpWidget(
      ShadApp(
        home: ChangeNotifierProvider(
          create: (_) => DisplaySettings(),
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Center(
              child: SizedBox(
                width: 320,
                child: PriceLineChart(candles: candles),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paint = find.byType(CustomPaint);
    expect(paint, findsWidgets);
    final box = tester.renderObject(paint.first) as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    await tester.tapAt(center);
    await tester.pump();
    expect(find.textContaining('2026-01-'), findsOneWidget);
  });
}
