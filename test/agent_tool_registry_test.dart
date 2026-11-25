import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/genkit/agent_tool_registry.dart';

void main() {
  group('AgentToolRegistry', () {
    test('catalog ids match AgentToolIds.all', () {
      expect(
        AgentToolRegistry.catalog.map((t) => t.id).toList(),
        AgentToolIds.all,
      );
    });

    test('toolIdsForRole matches known specialty ACL', () {
      expect(
        AgentToolRegistry.toolIdsForRole('marketResearch'),
        [
          AgentToolIds.getQuotes,
          AgentToolIds.getHistory,
          AgentToolIds.getInvestInterest,
          AgentToolIds.getMandate,
          AgentToolIds.getAgentMemory,
          AgentToolIds.rememberFact,
          AgentToolIds.forgetFact,
          AgentToolIds.getAgentFleetStatus,
          AgentToolIds.setChatAutopilot,
          AgentToolIds.getChatFocusSymbols,
          AgentToolIds.pinChatSymbols,
          AgentToolIds.unpinChatSymbols,
          AgentToolIds.proposeInvestInterestDiff,
        ],
      );
      expect(
        AgentToolRegistry.toolIdsForRole('liveBalanceExplainer'),
        [
          AgentToolIds.getLiveBalances,
          AgentToolIds.getQuotes,
          AgentToolIds.getMandate,
          AgentToolIds.getAgentMemory,
          AgentToolIds.rememberFact,
          AgentToolIds.forgetFact,
          AgentToolIds.getAgentFleetStatus,
          AgentToolIds.setChatAutopilot,
          AgentToolIds.getChatFocusSymbols,
          AgentToolIds.pinChatSymbols,
          AgentToolIds.unpinChatSymbols,
        ],
      );
      expect(
        AgentToolRegistry.toolIdsForRole('portfolioGuide'),
        containsAll([
          AgentToolIds.getPracticePortfolio,
          AgentToolIds.getLiveBalances,
          AgentToolIds.getAgentPnl,
          AgentToolIds.getAgentMemory,
          AgentToolIds.getAgentFleetStatus,
          AgentToolIds.setChatAutopilot,
          AgentToolIds.getChatFocusSymbols,
          AgentToolIds.pinChatSymbols,
          AgentToolIds.unpinChatSymbols,
          AgentToolIds.proposeInvestInterestDiff,
        ]),
      );
      expect(
        AgentToolRegistry.toolIdsForRole('intradayTrading'),
        containsAll([
          AgentToolIds.getHistory,
          AgentToolIds.getAgentFleetStatus,
          AgentToolIds.setChatAutopilot,
          AgentToolIds.pinChatSymbols,
        ]),
      );
      expect(
        AgentToolRegistry.toolIdsForRole('cryptoSpotGuide'),
        [
          AgentToolIds.getQuotes,
          AgentToolIds.getHistory,
          AgentToolIds.getInvestInterest,
          AgentToolIds.getMandate,
          AgentToolIds.getAgentMemory,
          AgentToolIds.rememberFact,
          AgentToolIds.forgetFact,
          AgentToolIds.getAgentFleetStatus,
          AgentToolIds.setChatAutopilot,
          AgentToolIds.getChatFocusSymbols,
          AgentToolIds.pinChatSymbols,
          AgentToolIds.unpinChatSymbols,
        ],
      );
      expect(
        AgentToolRegistry.toolIdsForRole('marketsLiteracy'),
        AgentToolRegistry.toolIdsForRole('cryptoSpotGuide'),
      );
      expect(
        AgentToolRegistry.toolIdsForRole('cryptoSpotGuide'),
        isNot(contains(AgentToolIds.proposeInvestInterestDiff)),
      );
      expect(
        AgentToolRegistry.toolIdsForRole(
          'marketResearch',
          memoryEnabled: false,
        ),
        isNot(contains(AgentToolIds.rememberFact)),
      );
      expect(
        AgentToolRegistry.toolIdsForRole(
          'marketResearch',
          memoryEnabled: false,
        ),
        contains(AgentToolIds.getAgentFleetStatus),
      );
      expect(
        AgentToolRegistry.toolIdsForRole(
          'marketResearch',
          memoryEnabled: false,
        ),
        contains(AgentToolIds.pinChatSymbols),
      );
    });

    test('unknown role falls back to defaultToolIds', () {
      expect(
        AgentToolRegistry.toolIdsForRole('futureUnknownRole'),
        AgentToolRegistry.defaultToolIds,
      );
    });

    test('rolesForTool inverts ACL', () {
      expect(
        AgentToolRegistry.rolesForTool(AgentToolIds.proposeInvestInterestDiff),
        ['marketResearch', 'portfolioGuide', 'intradayTrading'],
      );
      expect(
        AgentToolRegistry.rolesForTool(AgentToolIds.getLiveBalances),
        ['liveBalanceExplainer', 'portfolioGuide', 'intradayTrading'],
      );
      expect(
        AgentToolRegistry.rolesForTool(AgentToolIds.getAgentPnl),
        ['portfolioGuide', 'intradayTrading'],
      );
      expect(
        AgentToolRegistry.rolesForTool(AgentToolIds.getAgentFleetStatus),
        [
          'marketResearch',
          'liveBalanceExplainer',
          'portfolioGuide',
          'intradayTrading',
          'cryptoSpotGuide',
          'marketsLiteracy',
        ],
      );
      expect(
        AgentToolRegistry.rolesForTool(AgentToolIds.pinChatSymbols),
        AgentToolRegistry.rolesForTool(AgentToolIds.getAgentFleetStatus),
      );
      expect(
        AgentToolRegistry.rolesForTool(AgentToolIds.setChatAutopilot),
        AgentToolRegistry.rolesForTool(AgentToolIds.getAgentFleetStatus),
      );
    });

    test('describeToolsForRole lists granted tools', () {
      final text = AgentToolRegistry.describeToolsForRole('marketResearch');
      expect(text, startsWith('Available tools:'));
      expect(text, contains(AgentToolIds.getQuotes));
      expect(text, contains(AgentToolIds.getHistory));
      expect(text, contains(AgentToolIds.proposeInvestInterestDiff));
      expect(text, isNot(contains(AgentToolIds.getPracticePortfolio)));
    });

    test('every toolsByRole entry uses catalog ids only', () {
      final catalogIds = AgentToolIds.all.toSet();
      for (final entry in AgentToolRegistry.toolsByRole.entries) {
        for (final id in entry.value) {
          expect(
            catalogIds.contains(id),
            isTrue,
            reason: '${entry.key} grants unknown tool $id',
          );
        }
      }
    });

    test('AgentRolePrompts injects Available tools from registry', () {
      final system = AgentRolePrompts.forRoleId('liveBalanceExplainer');
      expect(system, contains('Available tools:'));
      expect(system, contains(AgentToolIds.getLiveBalances));
      expect(system, contains(AgentToolIds.getQuotes));
      expect(system, isNot(contains(AgentToolIds.getPracticePortfolio)));
      expect(
        AgentRolePrompts.toolsPreamble('marketResearch'),
        contains(AgentToolIds.proposeInvestInterestDiff),
      );
    });
  });
}
