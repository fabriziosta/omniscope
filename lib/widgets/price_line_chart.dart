import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/brand_colors.dart';
import '../core/formatting.dart';
import '../data/market/models.dart';
import '../data/settings/display_settings.dart';

/// Simple themed line chart — CustomPaint only (no chart UI package).
///
/// Supports touch/mouse scrubbing for date + price readout.
class PriceLineChart extends StatefulWidget {
  const PriceLineChart({
    super.key,
    required this.candles,
    this.height = 220,
  });

  final List<Candle> candles;
  final double height;

  @override
  State<PriceLineChart> createState() => _PriceLineChartState();
}

class _PriceLineChartState extends State<PriceLineChart> {
  int? _scrubIndex;

  static const _leftPad = 8.0;
  static const _rightPad = 48.0;

  int? _indexForDx(double dx, double width) {
    final candles = widget.candles;
    if (candles.length < 2) return null;
    final chartWidth = width - _leftPad - _rightPad;
    if (chartWidth <= 0) return null;
    final x = (dx - _leftPad).clamp(0.0, chartWidth);
    final t = x / chartWidth;
    final index = (t * (candles.length - 1)).round().clamp(
          0,
          candles.length - 1,
        );
    return index;
  }

  void _setScrub(Offset? local, double width) {
    if (local == null) {
      if (_scrubIndex != null) setState(() => _scrubIndex = null);
      return;
    }
    final next = _indexForDx(local.dx, width);
    if (next != _scrubIndex) {
      setState(() => _scrubIndex = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final candles = widget.candles;

    if (candles.length < 2) {
      return SizedBox(
        height: widget.height,
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
    final priceFormat = context.watch<DisplaySettings>().priceFormat;
    final scrub = _scrubIndex == null ? null : candles[_scrubIndex!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scrub != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text(
              '${_formatScrubDate(scrub.time)}  ·  '
              '${formatDisplayMoney(scrub.close, priceFormat)}',
              style: theme.textTheme.small.copyWith(
                color: scheme.foreground,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _setScrub(d.localPosition, constraints.maxWidth),
                onHorizontalDragStart: (d) =>
                    _setScrub(d.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _setScrub(d.localPosition, constraints.maxWidth),
                child: CustomPaint(
                  painter: _PriceLinePainter(
                    candles: candles,
                    lineColor: lineColor,
                    gridColor: scheme.border,
                    labelColor: scheme.mutedForeground,
                    fillColor: lineColor.withValues(alpha: 0.12),
                    scrubColor: scheme.primary,
                    scrubIndex: _scrubIndex,
                    leftPad: _leftPad,
                    rightPad: _rightPad,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatScrubDate(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '${time.year}-$m-$d';
  }
}

class _PriceLinePainter extends CustomPainter {
  _PriceLinePainter({
    required this.candles,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.fillColor,
    required this.scrubColor,
    required this.scrubIndex,
    required this.leftPad,
    required this.rightPad,
  });

  final List<Candle> candles;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final Color fillColor;
  final Color scrubColor;
  final int? scrubIndex;
  final double leftPad;
  final double rightPad;

  @override
  void paint(Canvas canvas, Size size) {
    final prices = candles.map((c) => c.close).toList();
    var minP = prices.reduce(math.min);
    var maxP = prices.reduce(math.max);
    if ((maxP - minP).abs() < 1e-9) {
      minP -= 1;
      maxP += 1;
    }

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

    final scrub = scrubIndex;
    if (scrub != null && scrub >= 0 && scrub < candles.length) {
      final p = pointFor(scrub);
      final scrubPaint = Paint()
        ..color = scrubColor
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(p.dx, topPad),
        Offset(p.dx, topPad + chartHeight),
        scrubPaint,
      );
      canvas.drawCircle(p, 4, Paint()..color = scrubColor);
    }
  }

  @override
  bool shouldRepaint(covariant _PriceLinePainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.scrubIndex != scrubIndex ||
        oldDelegate.scrubColor != scrubColor;
  }
}
