import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../features/quotes/quotes_list_controller.dart';
import 'app_toast.dart';

/// Toasts soft [QuotesListController.lastPagingError] values, then clears them.
class QuotesPagingErrorListener extends StatefulWidget {
  const QuotesPagingErrorListener({super.key, required this.child});

  final Widget child;

  @override
  State<QuotesPagingErrorListener> createState() =>
      _QuotesPagingErrorListenerState();
}

class _QuotesPagingErrorListenerState extends State<QuotesPagingErrorListener> {
  QuotesListController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<QuotesListController>();
    if (!identical(_controller, next)) {
      _controller?.removeListener(_onController);
      _controller = next..addListener(_onController);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final message = controller.lastPagingError;
    if (message == null) return;
    showAppToast(
      context,
      description: message,
      destructive: true,
    );
    controller.clearPagingError();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
