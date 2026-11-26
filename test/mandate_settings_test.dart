import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';

void main() {
  test('defaults then round-trips via JSON', () {
    expect(ChatMandate.defaults.goal, MandateGoal.learn);
    expect(ChatMandate.defaults.horizon, MandateHorizon.medium);
    expect(ChatMandate.defaults.universe, MandateUniverse.both);
    expect(ChatMandate.defaults.maxSymbolCount, 20);
    expect(ChatMandate.defaults.maxOpenProposals, 3);
    expect(ChatMandate.defaults.maxNotionalPerProposal, isNull);
    expect(ChatMandate.defaults.cadencePreference, AgentScheduleInterval.hour1);

    final mandate = ChatMandate(
      goal: MandateGoal.grow,
      horizon: MandateHorizon.long,
      universe: MandateUniverse.equities,
      maxSymbolCount: 8,
      maxOpenProposals: 2,
      maxNotionalPerProposal: 250,
      cadencePreference: AgentScheduleInterval.hours4,
    );
    final again = ChatMandate.fromJson(mandate.toJson());
    expect(again.goal, MandateGoal.grow);
    expect(again.horizon, MandateHorizon.long);
    expect(again.universe, MandateUniverse.equities);
    expect(again.maxSymbolCount, 8);
    expect(again.maxOpenProposals, 2);
    expect(again.maxNotionalPerProposal, 250);
    expect(again.cadencePreference, AgentScheduleInterval.hours4);
  });

  test('fromJson clamps symbol and open-proposal counts', () {
    final mandate = ChatMandate.fromJson({
      'maxSymbolCount': 0,
      'maxOpenProposals': 999,
      'maxAutopilotFillsPerDay': 0,
    });
    expect(mandate.maxSymbolCount, ChatMandate.minSymbolCount);
    expect(mandate.maxOpenProposals, ChatMandate.maxOpenProposalsCap);
    expect(mandate.maxAutopilotFillsPerDay, ChatMandate.minAutopilotFillsPerDay);
  });

  test('toAgentSummary includes rails', () {
    final mandate = const ChatMandate(maxNotionalPerProposal: 100);
    final text = mandate.toAgentSummary();
    expect(text, contains('goal=learn'));
    expect(text, contains('max notional \$100'));
    expect(text, contains('maxOpenProposals=3'));
  });

  test('missing or invalid JSON uses defaults', () {
    expect(ChatMandate.fromJson(null), ChatMandate.defaults);
    expect(ChatMandate.fromJson({'goal': 'yolo'}).goal, MandateGoal.learn);
  });
}
