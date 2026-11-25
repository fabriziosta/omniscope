import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/portfolio/models.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults starting cash to 10000 and reset restores it', () async {
    final store = await memoryConfig();
    final repo = PortfolioRepository(store: store);
    await repo.load();
    expect(repo.startingCash, PortfolioState.defaultStartingCash);
    expect(repo.state.cash, PortfolioState.defaultStartingCash);

    final buy = await repo.buy(symbol: 'AAPL', shares: 1, price: 100);
    expect(buy.success, isTrue);
    expect(repo.state.cash, lessThan(PortfolioState.defaultStartingCash));
    expect(repo.state.holdings, isNotEmpty);

    await repo.reset();
    expect(repo.state.cash, PortfolioState.defaultStartingCash);
    expect(repo.state.holdings, isEmpty);
  });

  test('setStartingCash persists and applies on reset only', () async {
    final store = await memoryConfig();
    final repo = PortfolioRepository(store: store);
    await repo.load();

    await repo.buy(symbol: 'AAPL', shares: 1, price: 50);
    final cashBefore = repo.state.cash;
    await repo.setStartingCash(25000);
    expect(repo.startingCash, 25000);
    expect(repo.state.cash, cashBefore);
    expect(repo.state.holdings, isNotEmpty);

    await repo.reset();
    expect(repo.state.cash, 25000);
    expect(repo.state.holdings, isEmpty);

    final again = PortfolioRepository(store: store);
    await again.load();
    expect(again.startingCash, 25000);
  });

  test('Practice allows fractional BTC when cash cannot cover a whole coin',
      () async {
    final store = await memoryConfig();
    final repo = PortfolioRepository(store: store);
    await repo.load();
    expect(repo.state.cash, PortfolioState.defaultStartingCash);

    const btcPrice = 90000.0;
    final whole = await repo.buy(
      symbol: 'BTC_USD',
      shares: 1,
      price: btcPrice,
    );
    expect(whole.success, isFalse);
    expect(whole.error, contains('Not enough cash'));
    expect(repo.state.holdings, isEmpty);
    expect(repo.state.cash, PortfolioState.defaultStartingCash);

    final fractional = await repo.buy(
      symbol: 'BTC_USD',
      shares: 0.01,
      price: btcPrice,
    );
    expect(fractional.success, isTrue);
    expect(repo.state.holdings, hasLength(1));
    expect(repo.state.holdings.single.symbol, 'BTC_USD');
    expect(repo.state.holdings.single.shares, closeTo(0.01, 1e-9));
    expect(
      repo.state.cash,
      closeTo(PortfolioState.defaultStartingCash - 900, 1e-6),
    );
  });
}
