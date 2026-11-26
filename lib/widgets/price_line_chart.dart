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
/// Draws price ticks on the Y-axis and date ticks on the X-axis.
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
  _ChartAxisLabelLayout? _axisLabels;

  static const _leftPad = 8.0;
  static const _rightPad = 56.0;

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

  @override
  void didUpdateWidget(covariant PriceLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candles, widget.candles)) {
      _axisLabels = null;
    }
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

  _ChartAxisLabelLayout _axisLabelsFor({
    required List<Candle> candles,
    required PriceFormat priceFormat,
    required Color labelColor,
    required double chartWidth,
    required double chartHeight,
    required double minP,
    required double maxP,
  }) {
    final key = _ChartAxisCacheKey(
      candles: candles,
      priceFormat: priceFormat,
      labelColor: labelColor,
      chartWidth: chartWidth,
      chartHeight: chartHeight,
      minP: minP,
      maxP: maxP,
    );
    final cached = _axisLabels;
    if (cached != null && cached.cacheKey == key) return cached;
    final built = _ChartAxisLabelLayout.build(
      cacheKey: key,
      candles: candles,
      priceFormat: priceFormat,
      labelColor: labelColor,
      chartWidth: chartWidth,
      chartHeight: chartHeight,
      minP: minP,
      maxP: maxP,
      leftPad: _leftPad,
      rightPad: _rightPad,
    );
    _axisLabels = built;
    return built;
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
    final priceFormat =
        context.select<DisplaySettings, PriceFormat>((s) => s.priceFormat);
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
              final prices = candles.map((c) => c.close).toList();
              var minP = prices.reduce(math.min);
              var maxP = prices.reduce(math.max);
              if ((maxP - minP).abs() < 1e-9) {
                minP -= 1;
                maxP += 1;
              }

              const topPad = 12.0;
              const bottomPad = 24.0;
              final chartWidth = constraints.maxWidth - _leftPad - _rightPad;
              final chartHeight =
                  constraints.maxHeight - topPad - bottomPad;

              final axisLabels = _axisLabelsFor(
                candles: candles,
                priceFormat: priceFormat,
                labelColor: scheme.mutedForeground,
                chartWidth: chartWidth,
                chartHeight: chartHeight,
                minP: minP,
                maxP: maxP,
              );

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _setScrub(d.localPosition, constraints.maxWidth),
                onHorizontalDragStart: (d) =>
                    _setScrub(d.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _setScrub(d.localPosition, constraints.maxWidth),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: _PriceLineChartPainter(
                          candles: candles,
                          lineColor: lineColor,
                          gridColor: scheme.border,
                          fillColor: lineColor.withValues(alpha: 0.12),
                          leftPad: _leftPad,
                          rightPad: _rightPad,
                          minP: minP,
                          maxP: maxP,
                          axisLabels: axisLabels,
                        ),
                      ),
                    ),
                    if (_scrubIndex != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: _PriceLineScrubPainter(
                            candles: candles,
                            scrubColor: scheme.primary,
                            scrubIndex: _scrubIndex,
                            leftPad: _leftPad,
                            rightPad: _rightPad,
                            minP: minP,
                            maxP: maxP,
                          ),
                        ),
                      ),
                  ],
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

/// Formats a Y-axis price tick for the chart (compact axis labels).
@visibleForTesting
String formatChartPriceAxis(double value, PriceFormat priceFormat) {
  if (value.isNaN) return '—';
  // Prefer compact currency on axis so labels fit the right gutter.
  if (priceFormat == PriceFormat.compact || value.abs() >= 10000) {
    return formatCompactMoney(value);
  }
  if (value.abs() >= 1000) {
    return NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(value);
  }
  return formatMoney(value);
}

/// Formats an X-axis date tick from the candle span.
@visibleForTesting
String formatChartDateAxis(DateTime time, {required Duration span}) {
  final local = time.toLocal();
  if (span.inHours < 48) {
    return DateFormat('MMM d · HH:mm').format(local);
  }
  if (span.inDays > 300) {
    return DateFormat('MMM yyyy').format(local);
  }
  return DateFormat('MMM d').format(local);
}

class _ChartAxisCacheKey {
  const _ChartAxisCacheKey({
    required this.candles,
    required this.priceFormat,
    required this.labelColor,
    required this.chartWidth,
    required this.chartHeight,
    required this.minP,
    required this.maxP,
  });

  final List<Candle> candles;
  final PriceFormat priceFormat;
  final Color labelColor;
  final double chartWidth;
  final double chartHeight;
  final double minP;
  final double maxP;

  @override
  bool operator ==(Object other) {
    return other is _ChartAxisCacheKey &&
        identical(candles, other.candles) &&
        priceFormat == other.priceFormat &&
        labelColor == other.labelColor &&
        chartWidth == other.chartWidth &&
        chartHeight == other.chartHeight &&
        minP == other.minP &&
        maxP == other.maxP;
  }

  @override
  int get hashCode => Object.hash(
        candles,
        priceFormat,
        labelColor,
        chartWidth,
        chartHeight,
        minP,
        maxP,
      );
}

class _ChartAxisLabelLayout {
  const _ChartAxisLabelLayout({
    required this.cacheKey,
    required this.yTicks,
    required this.xTicks,
  });

  final _ChartAxisCacheKey cacheKey;
  final List<({TextPainter painter, Offset offset})> yTicks;
  final List<({TextPainter painter, Offset offset})> xTicks;

  static const _yTickCount = 5;
  static const _xTickCount = 3;

  factory _ChartAxisLabelLayout.build({
    required _ChartAxisCacheKey cacheKey,
    required List<Candle> candles,
    required PriceFormat priceFormat,
    required Color labelColor,
    required double chartWidth,
    required double chartHeight,
    required double minP,
    required double maxP,
    required double leftPad,
    required double rightPad,
  }) {
    const topPad = 12.0;
    const labelStyle = TextStyle(fontSize: 10);
    final span = candles.last.time.difference(candles.first.time);

    final yTicks = <({TextPainter painter, Offset offset})>[];
    final yIntervals = _yTickCount - 1;
    for (var i = 0; i < _yTickCount; i++) {
      final t = i / yIntervals;
      final y = topPad + chartHeight * t;
      final value = maxP - (maxP - minP) * t;
      final tp = TextPainter(
        text: TextSpan(
          text: formatChartPriceAxis(value, priceFormat),
          style: labelStyle.copyWith(color: labelColor),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: rightPad - 4);
      yTicks.add(
        (
          painter: tp,
          offset: Offset(leftPad + chartWidth + 6, y - tp.height / 2),
        ),
      );
    }

    final xTicks = <({TextPainter painter, Offset offset})>[];
    final xIntervals = _xTickCount - 1;
    for (var i = 0; i < _xTickCount; i++) {
      final t = i / xIntervals;
      final index = (t * (candles.length - 1)).round();
      final x = leftPad + chartWidth * t;
      final label = formatChartDateAxis(candles[index].time, span: span);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(color: labelColor),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      var labelX = x - tp.width / 2;
      if (i == 0) {
        labelX = x;
      } else if (i == _xTickCount - 1) {
        labelX = x - tp.width;
      }
      xTicks.add(
        (
          painter: tp,
          offset: Offset(labelX, topPad + chartHeight + 6),
        ),
      );
    }

    return _ChartAxisLabelLayout(
      cacheKey: cacheKey,
      yTicks: yTicks,
      xTicks: xTicks,
    );
  }
}

class _PriceLineChartPainter extends CustomPainter {
  _PriceLineChartPainter({
    required this.candles,
    required this.lineColor,
    required this.gridColor,
    required this.fillColor,
    required this.leftPad,
    required this.rightPad,
    required this.minP,
    required this.maxP,
    required this.axisLabels,
  });

  final List<Candle> candles;
  final Color lineColor;
  final Color gridColor;
  final Color fillColor;
  final double leftPad;
  final double rightPad;
  final double minP;
  final double maxP;
  final _ChartAxisLabelLayout axisLabels;

  static const _yTickCount = 5;
  static const _topPad = 12.0;
  static const _bottomPad = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final prices = candles.map((c) => c.close).toList();
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - _topPad - _bottomPad;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final yIntervals = _yTickCount - 1;
    for (var i = 0; i < _yTickCount; i++) {
      final t = i / yIntervals;
      final y = _topPad + chartHeight * t;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartWidth, y),
        gridPaint,
      );
    }

    for (final tick in axisLabels.yTicks) {
      tick.painter.paint(canvas, tick.offset);
    }
    for (final tick in axisLabels.xTicks) {
      tick.painter.paint(canvas, tick.offset);
    }

    Offset pointFor(int i) {
      final x = leftPad + chartWidth * i / (candles.length - 1);
      final y =
          _topPad + chartHeight * (1 - (prices[i] - minP) / (maxP - minP));
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointFor(0).dx, pointFor(0).dy);
    for (var i = 1; i < candles.length; i++) {
      path.lineTo(pointFor(i).dx, pointFor(i).dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(pointFor(candles.length - 1).dx, _topPad + chartHeight)
      ..lineTo(pointFor(0).dx, _topPad + chartHeight)
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
  bool shouldRepaint(covariant _PriceLineChartPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.leftPad != leftPad ||
        oldDelegate.rightPad != rightPad ||
        oldDelegate.minP != minP ||
        oldDelegate.maxP != maxP ||
        oldDelegate.axisLabels.cacheKey != axisLabels.cacheKey;
  }
}

class _PriceLineScrubPainter extends CustomPainter {
  _PriceLineScrubPainter({
    required this.candles,
    required this.scrubColor,
    required this.scrubIndex,
    required this.leftPad,
    required this.rightPad,
    required this.minP,
    required this.maxP,
  });

  final List<Candle> candles;
  final Color scrubColor;
  final int? scrubIndex;
  final double leftPad;
  final double rightPad;
  final double minP;
  final double maxP;

  static const _topPad = 12.0;
  static const _bottomPad = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scrub = scrubIndex;
    if (scrub == null || scrub < 0 || scrub >= candles.length) return;

    final prices = candles.map((c) => c.close).toList();
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - _topPad - _bottomPad;

    final x = leftPad + chartWidth * scrub / (candles.length - 1);
    final y =
        _topPad + chartHeight * (1 - (prices[scrub] - minP) / (maxP - minP));
    final p = Offset(x, y);

    final scrubPaint = Paint()
      ..color = scrubColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(p.dx, _topPad),
      Offset(p.dx, _topPad + chartHeight),
      scrubPaint,
    );
    canvas.drawCircle(p, 4, Paint()..color = scrubColor);
  }

  @override
  bool shouldRepaint(covariant _PriceLineScrubPainter oldDelegate) {
    return oldDelegate.scrubIndex != scrubIndex;
  }
}
