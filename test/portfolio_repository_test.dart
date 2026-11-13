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
}
