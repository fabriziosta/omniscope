import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/app_error_controller.dart';
import 'package:omniscope/core/app_error_handling.dart';
import 'package:omniscope/widgets/app_error_gate.dart';
import 'package:omniscope/widgets/app_error_view.dart';
import 'package:omniscope/widgets/app_fatal_error_screen.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('AppErrorView shows friendly copy and retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      ShadApp(
        home: AppErrorView(
          title: 'Could not load markets',
          message: 'Check your connection, then try again.',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Could not load markets'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  test('ErrorWidget.builder returns crash view without exception text', () {
    final navigatorKey = GlobalKey<NavigatorState>();
    final errors = AppErrorController(navigatorKey: navigatorKey);
    installAppErrorHandling(errors);

    final widget = ErrorWidget.builder(
      FlutterErrorDetails(exception: StateError('secret stack details')),
    );

    expect(widget, isA<AppErrorView>());
    final view = widget as AppErrorView;
    expect(view.title, 'Something went wrong');
    expect(view.message.contains('secret'), isFalse);
  });

  testWidgets('uncaught async error shows fatal overlay', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final errors = AppErrorController(navigatorKey: navigatorKey);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppErrorController>.value(
        value: errors,
        child: ShadApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => AppErrorGate(child: child),
          home: const ColoredBox(
            color: Color(0xFFCCFBF1),
            child: Center(child: Text('Home marker')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home marker'), findsOneWidget);

    errors.reportUnhandled(StateError('secret async boom'), StackTrace.current);
    await tester.pumpAndSettle();

    expect(find.byType(AppFatalErrorScreen), findsOneWidget);
    expect(find.text('Go home'), findsOneWidget);
    expect(find.textContaining('secret async boom'), findsNothing);
    expect(find.text('Home marker'), findsNothing);
    expect(errors.isActive, isTrue);

    await tester.tap(find.text('Go home'));
    await tester.pumpAndSettle();

    expect(errors.isActive, isFalse);
    expect(find.byType(AppFatalErrorScreen), findsNothing);
    expect(find.text('Home marker'), findsOneWidget);
  });
}
