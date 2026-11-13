import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/trading/trade_executor.dart';

/// Asks the user to pick Practice or a live venue before Confirm.
Future<String?> showPortfolioPickerDialog(
  BuildContext context, {
  required List<TradableVenue> venues,
}) {
  return showShadDialog<String>(
    context: context,
    builder: (context) => _PortfolioPickerDialog(venues: venues),
  );
}

class _PortfolioPickerDialog extends StatefulWidget {
  const _PortfolioPickerDialog({required this.venues});

  final List<TradableVenue> venues;

  @override
  State<_PortfolioPickerDialog> createState() => _PortfolioPickerDialogState();
}

class _PortfolioPickerDialogState extends State<_PortfolioPickerDialog> {
  late String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.venues.isEmpty ? null : widget.venues.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDialog(
      title: const Text('Choose portfolio'),
      description: const Text(
        'Pick Practice or a live exchange for this order.',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          enabled: _selected != null,
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Continue'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Portfolio', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadSelect<String>(
            minWidth: double.infinity,
            initialValue: _selected,
            placeholder: const Text('Select portfolio'),
            options: [
              for (final v in widget.venues)
                ShadOption(value: v.id, child: Text(v.displayName)),
            ],
            selectedOptionBuilder: (context, value) {
              for (final v in widget.venues) {
                if (v.id == value) return Text(v.displayName);
              }
              return Text(value);
            },
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selected = value);
            },
          ),
        ],
      ),
    );
  }
}
