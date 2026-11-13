import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/brand_colors.dart';
import '../data/market/models.dart';

/// Simple themed line chart — CustomPaint only (no chart UI package).
class PriceLineChart extends StatelessWidget {
  const PriceLineChart({
    super.key,
    required this.candles,
    this.height = 220,
  });

  final List<Candle> candles;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;

    if (candles.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough history to chart',
            style: theme.textTheme.muted,
          ),
        ),
      );
    }

    final first = candles.first.close;
    final last = candles.last.close;
    final up = last >= first;
    final lineColor =
        up ? BrandColors.gainOf(context) : BrandColors.lossOf(context);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _PriceLinePainter(
          candles: candles,
          lineColor: lineColor,
          gridColor: scheme.border,
          labelColor: scheme.mutedForeground,
          fillColor: lineColor.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

class _PriceLinePainter extends CustomPainter {
  _PriceLinePainter({
    required this.candles,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.fillColor,
  });

  final List<Candle> candles;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final prices = candles.map((c) => c.close).toList();
    var minP = prices.reduce(math.min);
    var maxP = prices.reduce(math.max);
    if ((maxP - minP).abs() < 1e-9) {
      minP -= 1;
      maxP += 1;
    }

    const leftPad = 8.0;
    const rightPad = 48.0;
    const topPad = 12.0;
    const bottomPad = 8.0;
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - topPad - bottomPad;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i < 4; i++) {
      final y = topPad + chartHeight * i / 3;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartWidth, y),
        gridPaint,
      );
      final value = maxP - (maxP - minP) * i / 3;
      final tp = TextPainter(
        text: TextSpan(
          text: value >= 1000
              ? value.toStringAsFixed(0)
              : value.toStringAsFixed(2),
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad + chartWidth + 6, y - tp.height / 2));
    }

    Offset pointFor(int i) {
      final x = leftPad + chartWidth * i / (candles.length - 1);
      final y =
          topPad + chartHeight * (1 - (prices[i] - minP) / (maxP - minP));
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointFor(0).dx, pointFor(0).dy);
    for (var i = 1; i < candles.length; i++) {
      path.lineTo(pointFor(i).dx, pointFor(i).dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(pointFor(candles.length - 1).dx, topPad + chartHeight)
      ..lineTo(pointFor(0).dx, topPad + chartHeight)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PriceLinePainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}
