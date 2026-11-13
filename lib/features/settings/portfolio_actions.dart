import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_toast.dart';

/// Confirm + reset the local practice portfolio. Returns true when reset ran.
Future<bool> confirmAndResetPracticePortfolio(BuildContext context) async {
  final portfolio = context.read<PortfolioRepository>();
  final cashLabel = formatMoney(portfolio.startingCash);
  final ok = await confirmDestructiveAction(
    context,
    title: 'Reset practice holdings?',
    description:
        'This restores $cashLabel cash and clears all practice holdings. '
        'Live exchange balances are not affected. This cannot be undone.',
    confirmLabel: 'Reset',
  );
  if (!ok || !context.mounted) return false;
  await portfolio.reset();
  if (!context.mounted) return true;
  showAppToast(
    context,
    title: 'Practice holdings reset',
    description: 'Back to $cashLabel cash with no holdings.',
  );
  return true;
}
