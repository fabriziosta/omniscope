import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/app_copy.dart';
import '../data/market/models.dart';
import '../features/quotes/quotes_list_controller.dart';
import 'app_empty_view.dart';
import 'app_error_view.dart';
import 'app_progress.dart';

/// Loading / error / empty / data shell driven by [QuotesListController].
class QuotesAsyncBody extends StatelessWidget {
  const QuotesAsyncBody({
    super.key,
    required this.builder,
    this.emptyMessage = AppCopy.noQuotes,
    this.errorTitle,
    this.showAsOfCaption = true,
  });

  final Widget Function(BuildContext context, List<Quote> quotes) builder;
  final String emptyMessage;
  final String? errorTitle;

  /// Shows a delayed-data / as-of line above the quote list when available.
  final bool showAsOfCaption;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<QuotesListController>();

    if (controller.loading && !controller.hasLoaded) {
      return const Center(child: AppProgress());
    }
    if (controller.hasError) {
      return AppErrorView(
        title: errorTitle ?? controller.errorTitle,
        message: controller.error ?? AppCopy.checkConnection,
        onRetry: controller.refresh,
      );
    }
    if (controller.isEmpty) {
      return AppEmptyView(emptyMessage);
    }
    if (!controller.hasLoaded) {
      return const Center(child: AppProgress());
    }

    final body = builder(context, controller.quotes);
    if (!showAsOfCaption || controller.fetchedAt == null) {
      return body;
    }

    final theme = ShadTheme.of(context);
    final local = controller.fetchedAt!.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '${AppCopy.delayedDataCaption} As of $h:$m.',
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}
