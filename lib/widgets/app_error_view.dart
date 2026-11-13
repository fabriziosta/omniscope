import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/brand_colors.dart';

/// Friendly error surface. Never shows raw exception text to the user.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    this.title = 'Something went wrong',
    this.message = 'Please try again in a moment.',
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  /// Unexpected widget/build failure — used by [ErrorWidget.builder].
  const AppErrorView.crash({super.key})
      : title = 'Something went wrong',
        message =
            'This screen hit an unexpected problem. Go back or restart the app.',
        onRetry = null,
        retryLabel = 'Try again';

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.maybeOf(context);
    if (theme != null) {
      return _ThemedErrorBody(
        title: title,
        message: message,
        onRetry: onRetry,
        retryLabel: retryLabel,
        theme: theme,
      );
    }

    final brightness =
        MediaQuery.maybeOf(context)?.platformBrightness ?? Brightness.light;
    return _FallbackErrorBody(
      title: title,
      message: message,
      onRetry: onRetry,
      retryLabel: retryLabel,
      brightness: brightness,
    );
  }
}

class _ThemedErrorBody extends StatelessWidget {
  const _ThemedErrorBody({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.retryLabel,
    required this.theme,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.large,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.muted,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ShadButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Theme-free fallback for [ErrorWidget] when [ShadTheme] is unavailable.
class _FallbackErrorBody extends StatelessWidget {
  const _FallbackErrorBody({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.retryLabel,
    required this.brightness,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final primary = BrandColors.primary(brightness);
    final background = BrandColors.secondary(brightness);
    final foreground = brightness == Brightness.dark
        ? BrandColors.secondaryForegroundDark
        : BrandColors.secondaryForegroundLight;
    final onPrimary = brightness == Brightness.dark
        ? BrandColors.primaryForegroundDark
        : BrandColors.primaryForegroundLight;

    return ColoredBox(
      color: background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.circleAlert, size: 40, color: primary),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.8),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetry,
                  child: Container(
                    constraints:
                        const BoxConstraints(minHeight: 44, minWidth: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      retryLabel,
                      style: TextStyle(
                        color: onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
