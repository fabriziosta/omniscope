import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_activity.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/invest_interest_proposal.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_actions.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InvestInterestProposalParser', () {
    test('extracts fenced invest interest JSON', () {
      const reply = '''
Here is a watchlist tweak.

```json
{"type":"invest_interest","add":["AAPL","spy"],"remove":["MSFT"],"rationale":"Focus large caps"}
```
''';
      final map = InvestInterestProposalParser.extractJsonMap(reply);
      expect(map, isNotNull);
      expect(map!['add'], ['AAPL', 'spy']);
      expect(map['remove'], ['MSFT']);
    });

    test('ignores trade JSON', () {
      const reply = '''
```json
{"ticker":"AAPL","action":"buy","quantity":1,"rationale":"x","risk_approved":true}
```
''';
      expect(InvestInterestProposalParser.extractJsonMap(reply), isNull);
    });
  });

  group('InvestInterestProposalActions', () {
    Future<
        ({
          InvestInterestProposalActions actions,
          InvestInterestProposalRepository proposals,
          FavoritesRepository favorites,
          AgentActivityRepository activity,
          MandateSettings mandate,
        })> harness() async {
      final store = await memoryConfig();
      final favorites = FavoritesRepository(store: store);
      await favorites.load();
      await favorites.toggleInvestInterest('MSFT');
      await favorites.toggleInvestInterest('SPY');

      final mandate = MandateSettings(store: store);
      await mandate.load();
      await mandate.setMaxSymbolCount(3);

      final proposals = InvestInterestProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();

      final actions = InvestInterestProposalActions(
        proposals: proposals,
        activity: activity,
        favorites: favorites,
        mandate: mandate,
      );
      return (
        actions: actions,
        proposals: proposals,
        favorites: favorites,
        activity: activity,
        mandate: mandate,
      );
    }

    test('confirm applies add/remove and marks managed', () async {
      final h = await harness();
      final proposal = InvestInterestProposal.fromToolInput(
        {
          'add': ['AAPL'],
          'remove': ['MSFT'],
          'rationale': 'Rotate into AAPL',
        },
        roleId: 'marketResearch',
        chatId: 'c_ii_1',
        sourceMessageId: 'msg_ii',
      );
      expect(proposal.chatId, 'c_ii_1');
      expect(proposal.sourceMessageId, 'msg_ii');
      expect(
        InvestInterestProposal.fromJson(proposal.toJson()).chatId,
        'c_ii_1',
      );
      await h.proposals.upsert(proposal);

      final err = await h.actions.confirm(proposal.id);
      expect(err, isNull);
      expect(
        h.proposals.byId(proposal.id)!.status,
        InvestInterestProposalStatus.confirmed,
      );
      expect(h.favorites.investInterestSymbols, ['SPY', 'AAPL']);
      expect(h.favorites.investInterestManagedByAgent, isTrue);
      expect(h.favorites.investInterestManagedByRoleId, 'marketResearch');
      expect(
        h.activity.events.any(
          (e) => e.kind == AgentActivityKind.investInterestConfirmed,
        ),
        isTrue,
      );

      final slice = h.favorites.store!.getSlice(UserConfigKeys.favorites) as Map;
      expect(slice['investInterest'], ['SPY', 'AAPL']);
      expect(slice['investInterestManagedByRoleId'], 'marketResearch');
    });

    test('confirm caps to mandate maxSymbolCount', () async {
      final h = await harness();
      final proposal = InvestInterestProposal.fromToolInput(
        {
          'set': ['AAPL', 'MSFT', 'SPY', 'QQQ', 'IWM'],
          'rationale': 'Too many',
        },
        roleId: 'portfolioGuide',
      );
      await h.proposals.upsert(proposal);

      final err = await h.actions.confirm(proposal.id);
      expect(err, isNull);
      expect(h.favorites.investInterestSymbols.length, 3);
      expect(h.favorites.investInterestSymbols, ['AAPL', 'MSFT', 'SPY']);
    });

    test('dismiss leaves favorites unchanged', () async {
      final h = await harness();
      final before = List<String>.from(h.favorites.investInterestSymbols);
      final proposal = InvestInterestProposal.fromToolInput(
        {
          'add': ['AAPL'],
          'rationale': 'Nope',
        },
        roleId: 'marketResearch',
      );
      await h.proposals.upsert(proposal);

      final err = await h.actions.dismiss(proposal.id);
      expect(err, isNull);
      expect(
        h.proposals.byId(proposal.id)!.status,
        InvestInterestProposalStatus.dismissed,
      );
      expect(h.favorites.investInterestSymbols, before);
      expect(h.favorites.investInterestManagedByAgent, isFalse);
    });

    test('manual toggle clears managed badge', () async {
      final h = await harness();
      final proposal = InvestInterestProposal.fromToolInput(
        {
          'set': ['AAPL'],
          'rationale': 'Managed',
        },
        roleId: 'marketResearch',
      );
      await h.proposals.upsert(proposal);
      await h.actions.confirm(proposal.id);
      expect(h.favorites.investInterestManagedByAgent, isTrue);

      await h.favorites.toggleInvestInterest('MSFT');
      expect(h.favorites.investInterestManagedByAgent, isFalse);
    });
  });
}
