import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/fade_page_route.dart';
import '../asset_detail/asset_detail_screen.dart';

/// Focus symbols for this chat — shown just above the composer.
///
/// Read-only for the user: tap opens asset detail. Only the agent may
/// pin / unpin via `pinChatSymbols` / `unpinChatSymbols`.
class FocusSymbolChips extends StatelessWidget {
  const FocusSymbolChips({super.key, required this.symbols});

  final List<String> symbols;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'In this chat',
            style: theme.textTheme.muted.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final symbol in symbols) FocusSymbolChip(symbol: symbol),
            ],
          ),
        ],
      ),
    );
  }
}

class FocusSymbolChip extends StatelessWidget {
  const FocusSymbolChip({super.key, required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: ShadButton.ghost(
        size: ShadButtonSize.sm,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        onPressed: () {
          pushFadePage(context, AssetDetailScreen(symbol: symbol));
        },
        child: Text(
          symbol,
          style: theme.textTheme.small.copyWith(
            fontSize: 12,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
