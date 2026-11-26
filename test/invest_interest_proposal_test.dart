import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_activity.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/invest_interest_proposal.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_actions.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/invest_interest_provenance.dart';
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
          AgentChatRepository chats,
          String chatId,
        })> harness() async {
      final store = await memoryConfig();
      final favorites = FavoritesRepository(store: store);
      await favorites.load();
      await favorites.toggleInvestInterest('MSFT');
      await favorites.toggleInvestInterest('SPY');

      final chats = AgentChatRepository(store: store);
      await chats.load();
      final chat = await chats.createChat(title: 'II');
      await chats.setMandate(
        chat.chatId,
        const ChatMandate(maxSymbolCount: 3),
      );

      final proposals = InvestInterestProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();

      final actions = InvestInterestProposalActions(
        proposals: proposals,
        activity: activity,
        favorites: favorites,
        chats: chats,
      );
      return (
        actions: actions,
        proposals: proposals,
        favorites: favorites,
        activity: activity,
        chats: chats,
        chatId: chat.chatId,
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
        chatId: h.chatId,
        sourceMessageId: 'msg_ii',
      );
      expect(proposal.chatId, h.chatId);
      expect(proposal.sourceMessageId, 'msg_ii');
      expect(
        InvestInterestProposal.fromJson(proposal.toJson()).chatId,
        h.chatId,
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
      expect(h.favorites.sourceFor('SPY'), InvestInterestSource.user);
      expect(h.favorites.sourceFor('AAPL'), InvestInterestSource.agent);
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
        chatId: h.chatId,
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
        chatId: h.chatId,
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
        chatId: h.chatId,
      );
      await h.proposals.upsert(proposal);
      await h.actions.confirm(proposal.id);
      expect(h.favorites.investInterestManagedByAgent, isTrue);

      await h.favorites.toggleInvestInterest('MSFT');
      expect(h.favorites.investInterestManagedByAgent, isFalse);
      expect(h.favorites.sourceFor('MSFT'), InvestInterestSource.user);
    });

    test('autopilot applies add-only investigation proposals', () async {
      final h = await harness();
      final proposal = InvestInterestProposal.fromToolInput(
        {
          'add': ['AAPL'],
          'rationale': 'Autopilot add',
        },
        roleId: 'marketResearch',
        chatId: h.chatId,
      );
      await h.proposals.upsert(proposal);

      final err = await h.actions.confirm(proposal.id, autopilot: true);
      expect(err, isNull);
      expect(
        h.proposals.byId(proposal.id)!.status,
        InvestInterestProposalStatus.confirmed,
      );
      expect(h.favorites.investInterestSymbols, ['MSFT', 'SPY', 'AAPL']);
      expect(h.favorites.sourceFor('AAPL'), InvestInterestSource.agent);
      expect(h.favorites.sourceFor('MSFT'), InvestInterestSource.user);
      expect(
        h.activity.events.any(
          (e) => e.kind == AgentActivityKind.autopilotInvestInterestApplied,
        ),
        isTrue,
      );
    });

    test('autopilot rejects remove/set proposals', () async {
      final h = await harness();
      final withRemove = InvestInterestProposal.fromToolInput(
        {
          'add': ['AAPL'],
          'remove': ['MSFT'],
          'rationale': 'Mixed',
        },
        roleId: 'marketResearch',
        chatId: h.chatId,
      );
      await h.proposals.upsert(withRemove);
      final err = await h.actions.confirm(withRemove.id, autopilot: true);
      expect(err, isNotNull);
      expect(
        h.proposals.byId(withRemove.id)!.status,
        InvestInterestProposalStatus.pending,
      );
      expect(h.favorites.investInterestSymbols, ['MSFT', 'SPY']);
    });

    test('autopilot rejects trading-role invest interest', () async {
      final h = await harness();
      final proposal = InvestInterestProposal.fromToolInput(
        {
          'add': ['AAPL'],
          'rationale': 'Trading role',
        },
        roleId: 'intradayTrading',
        chatId: h.chatId,
      );
      await h.proposals.upsert(proposal);
      expect(
        InvestInterestProposalActions.isAutopilotAddOnlyEligible(proposal),
        isFalse,
      );
      final err = await h.actions.confirm(proposal.id, autopilot: true);
      expect(err, isNotNull);
      expect(
        h.proposals.byId(proposal.id)!.status,
        InvestInterestProposalStatus.pending,
      );
    });

    test('autopilot accepts orchestrator add-only proposals', () async {
      final h = await harness();
      final proposal = InvestInterestProposal.fromToolInput(
        {
          'add': ['ETH_USD'],
          'rationale': 'Freeform orchestrator chat',
        },
        roleId: 'orchestrator',
        chatId: 'c_orch_1',
      );
      await h.proposals.upsert(proposal);
      expect(
        InvestInterestProposalActions.isAutopilotAddOnlyEligible(proposal),
        isTrue,
      );
      final err = await h.actions.confirm(proposal.id, autopilot: true);
      expect(err, isNull);
      expect(
        h.proposals.byId(proposal.id)!.status,
        InvestInterestProposalStatus.confirmed,
      );
      expect(h.favorites.investInterestSymbols, contains('ETH_USD'));
    });

    test('applyPendingAutopilotAddsForChat flushes add-only only', () async {
      final h = await harness();
      final addOnly = InvestInterestProposal.fromToolInput(
        {
          'add': ['ETH_USD'],
          'rationale': 'Add ETH',
        },
        roleId: 'orchestrator',
        chatId: 'c_flush_1',
      );
      final withRemove = InvestInterestProposal.fromToolInput(
        {
          'add': ['SOL_USD'],
          'remove': ['MSFT'],
          'rationale': 'Needs Confirm',
        },
        roleId: 'marketResearch',
        chatId: 'c_flush_1',
      );
      final otherChat = InvestInterestProposal.fromToolInput(
        {
          'add': ['AAPL'],
          'rationale': 'Other chat',
        },
        roleId: 'marketResearch',
        chatId: 'c_flush_2',
      );
      await h.proposals.upsert(addOnly);
      await h.proposals.upsert(withRemove);
      await h.proposals.upsert(otherChat);

      final applied =
          await h.actions.applyPendingAutopilotAddsForChat('c_flush_1');
      expect(applied, 1);
      expect(
        h.proposals.byId(addOnly.id)!.status,
        InvestInterestProposalStatus.confirmed,
      );
      expect(
        h.proposals.byId(withRemove.id)!.status,
        InvestInterestProposalStatus.pending,
      );
      expect(
        h.proposals.byId(otherChat.id)!.status,
        InvestInterestProposalStatus.pending,
      );
      expect(h.favorites.investInterestSymbols, contains('ETH_USD'));
      expect(h.favorites.investInterestSymbols, isNot(contains('SOL_USD')));
    });
  });
}
