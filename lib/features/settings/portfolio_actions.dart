import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../widgets/app_toast.dart';

/// Confirm + reset the local practice portfolio. Returns true when reset ran.
Future<bool> confirmAndResetPracticePortfolio(BuildContext context) async {
  final portfolio = context.read<PortfolioRepository>();
  final cashLabel = formatMoney(portfolio.startingCash);
  final ok = await showShadDialog<bool>(
    context: context,
    builder: (context) => ShadDialog.alert(
      title: const Text('Reset practice holdings?'),
      description: Text(
        'This restores $cashLabel cash and clears all practice holdings. '
        'Live exchange balances are not affected. This cannot be undone.',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ShadButton.destructive(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  await portfolio.reset();
  if (!context.mounted) return true;
  showAppToast(
    context,
    title: 'Practice holdings reset',
    description: 'Back to $cashLabel cash with no holdings.',
  );
  return true;
}
