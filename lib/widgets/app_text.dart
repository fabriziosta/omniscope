import 'package:flutter/widgets.dart';

/// Identity / label copy: wrap up to [maxLines], then ellipsis as last resort.
class AppEllipsisText extends StatelessWidget {
  const AppEllipsisText(
    this.data, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.textAlign,
  });

  final String data;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      softWrap: true,
    );
  }
}

/// Money / P&L / prices: keep one line and scale down instead of clipping.
class AppMoneyText extends StatelessWidget {
  const AppMoneyText(
    this.data, {
    super.key,
    this.style,
    this.textAlign = TextAlign.end,
  });

  final String data;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: textAlign == TextAlign.start
          ? Alignment.centerLeft
          : textAlign == TextAlign.center
              ? Alignment.center
              : Alignment.centerRight,
      child: Text(
        data,
        style: style,
        maxLines: 1,
        softWrap: false,
        textAlign: textAlign,
      ),
    );
  }
}
