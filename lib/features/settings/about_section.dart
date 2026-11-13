import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/app_info.dart';

class AboutSectionBody extends StatelessWidget {
  const AboutSectionBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppInfo.name, style: theme.textTheme.large),
        const SizedBox(height: 4),
        Text(AppCopy.tagline, style: theme.textTheme.muted),
        const SizedBox(height: 4),
        Text(
          'Version ${AppInfo.version}',
          style: theme.textTheme.small.copyWith(
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 16),
        Text(AppCopy.aboutBody, style: theme.textTheme.p),
        const SizedBox(height: 12),
        Text(
          'Omniscope is not a brokerage, does not provide financial advice, '
          'and does not execute real trades.',
          style: theme.textTheme.p,
        ),
        const SizedBox(height: 12),
        Text(
          'Practice portfolio balances are paper money stored only on this '
          'device. Live balances (when configured) are read-only snapshots from '
          'your exchange.',
          style: theme.textTheme.p,
        ),
        const SizedBox(height: 12),
        Text(
          'Market data may come from Yahoo Finance (equities) and Crypto.com '
          'Exchange (crypto), plus any other providers you enable in Settings. '
          'Quotes can be delayed; use this app for learning only.',
          style: theme.textTheme.p,
        ),
      ],
    );
  }
}
