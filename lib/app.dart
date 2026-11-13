import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/brand_colors.dart';
import 'data/settings/theme_settings.dart';
import 'features/shell/home_shell.dart';
import 'widgets/app_error_gate.dart';

class OmniscopeApp extends StatelessWidget {
  const OmniscopeApp({super.key, this.navigatorKey});

  /// Shared with [AppErrorController] so [goHome] can pop pushed routes.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeSettings>().mode;

    return ShadApp(
      title: 'Omniscope',
      navigatorKey: navigatorKey,
      themeMode: themeMode,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: BrandColors.lightScheme(),
        cardTheme: ShadCardTheme(
          border: ShadBorder.all(color: BrandColors.borderLight),
        ),
        primaryToastTheme: const ShadToastTheme(
          alignment: Alignment.topCenter,
        ),
        destructiveToastTheme: const ShadToastTheme(
          alignment: Alignment.topCenter,
        ),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: BrandColors.darkScheme(),
        cardTheme: ShadCardTheme(
          border: ShadBorder.all(color: BrandColors.borderDark),
        ),
        primaryToastTheme: const ShadToastTheme(
          alignment: Alignment.topCenter,
        ),
        destructiveToastTheme: const ShadToastTheme(
          alignment: Alignment.topCenter,
        ),
      ),
      builder: (context, child) => AppErrorGate(child: child),
      home: const HomeShell(),
    );
  }
}
