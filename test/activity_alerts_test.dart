import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_repository.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/notifications/app_notification.dart';
import 'package:omniscope/data/notifications/app_notification_repository.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/activity/activity_screen.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Activity Alerts lists unread rows and Dismiss all',
      (tester) async {
    final store = await memoryConfig();
    final roles = await AgentRoleCatalog.load();
    final agents = AgentsRepository(store: store, roleCatalog: roles);
    await agents.load(roleCatalog: roles);
    final chats = AgentChatRepository(store: store);
    await chats.load();
    final proposals = TradeProposalRepository(store: store);
    await proposals.load();
    final investInterest = InvestInterestProposalRepository(store: store);
    await investInterest.load();
    final activity = AgentActivityRepository(store: store);
    await activity.load();
    final notifications = AppNotificationRepository(store: store);
    await notifications.load();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final appSettings = AgentAppSettings(store: store);
    await appSettings.load();
    final market = FakeMarketDataClient();
    final shellNav = ShellNavigationController();

    await notifications.enqueue(
      AppNotification(
        id: AppNotification.newId(),
        kind: AppNotificationKind.scheduledRunCompleted,
        roleId: 'orchestrator',
        createdAt: DateTime.utc(2026, 1, 2),
        title: 'Scheduled agent run',
        body: 'Finished AAPL — open the chat to review.',
        symbol: 'AAPL',
        chatId: 'chat-1',
      ),
    );
    expect(notifications.unreadCount, 1);

    shellNav.goToActivity(openAlerts: true);

    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShellNavigationController>.value(
            value: shellNav,
          ),
          ChangeNotifierProvider.value(value: agents),
          ChangeNotifierProvider.value(value: chats),
          ChangeNotifierProvider.value(value: proposals),
          ChangeNotifierProvider.value(value: investInterest),
          ChangeNotifierProvider.value(value: activity),
          ChangeNotifierProvider.value(value: notifications),
          ChangeNotifierProvider.value(value: dataSources),
          ChangeNotifierProvider.value(value: portfolio),
          ChangeNotifierProvider.value(value: appSettings),
          Provider<MarketDataClient>.value(value: market),
          Provider<TradeExecutor>.value(
            value: RoutingTradeExecutor(
              cryptoRegistry: const CryptoExchangeRegistry([]),
              brokerRegistry: BrokerExchangeRegistry.empty,
              dataSources: dataSources,
              portfolio: portfolio,
              marketData: market,
            ),
          ),
          Provider.value(value: const CryptoExchangeRegistry([])),
        ],
        child: const ShadApp(
          home: ActivityScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alerts'), findsWidgets);
    expect(find.text('Scheduled agent run'), findsOneWidget);
    expect(find.text('Dismiss all'), findsOneWidget);

    await tester.tap(find.text('Dismiss all'));
    await tester.pumpAndSettle();

    expect(notifications.active, isEmpty);
    expect(notifications.unreadCount, 0);
    expect(find.textContaining('No alerts yet'), findsOneWidget);
  });
}
