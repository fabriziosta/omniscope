import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

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
  });

  final Widget Function(BuildContext context, List<Quote> quotes) builder;
  final String emptyMessage;
  final String? errorTitle;

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
    return builder(context, controller.quotes);
  }
}
