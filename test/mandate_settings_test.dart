import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults then persists goal / universe / rails', () async {
    final store = await memoryConfig();
    final mandate = MandateSettings(store: store);
    await mandate.load();

    expect(mandate.goal, MandateGoal.learn);
    expect(mandate.horizon, MandateHorizon.medium);
    expect(mandate.universe, MandateUniverse.both);
    expect(mandate.maxSymbolCount, 20);
    expect(mandate.maxOpenProposals, 3);
    expect(mandate.maxNotionalPerProposal, isNull);
    expect(mandate.cadencePreference, AgentScheduleInterval.hour1);

    await mandate.setGoal(MandateGoal.grow);
    await mandate.setHorizon(MandateHorizon.long);
    await mandate.setUniverse(MandateUniverse.equities);
    await mandate.setMaxSymbolCount(8);
    await mandate.setMaxOpenProposals(2);
    await mandate.setMaxNotionalPerProposal(250);
    await mandate.setCadencePreference(AgentScheduleInterval.hours4);

    final again = MandateSettings(store: store);
    await again.load();
    expect(again.goal, MandateGoal.grow);
    expect(again.horizon, MandateHorizon.long);
    expect(again.universe, MandateUniverse.equities);
    expect(again.maxSymbolCount, 8);
    expect(again.maxOpenProposals, 2);
    expect(again.maxNotionalPerProposal, 250);
    expect(again.cadencePreference, AgentScheduleInterval.hours4);

    final slice = store.getSlice(UserConfigKeys.mandate) as Map;
    expect(slice['goal'], 'grow');
    expect(slice['universe'], 'equities');
    expect(slice['maxSymbolCount'], 8);
  });

  test('clamps symbol and open-proposal counts', () async {
    final store = await memoryConfig();
    final mandate = MandateSettings(store: store);
    await mandate.load();

    await mandate.setMaxSymbolCount(0);
    expect(mandate.maxSymbolCount, MandateSettings.minSymbolCount);
    await mandate.setMaxSymbolCount(999);
    expect(mandate.maxSymbolCount, MandateSettings.maxSymbolCountCap);
    await mandate.setMaxOpenProposals(0);
    expect(mandate.maxOpenProposals, MandateSettings.minOpenProposals);
  });

  test('toAgentSummary includes rails', () async {
    final store = await memoryConfig();
    final mandate = MandateSettings(store: store);
    await mandate.load();
    await mandate.setMaxNotionalPerProposal(100);
    final text = mandate.toAgentSummary();
    expect(text, contains('goal=learn'));
    expect(text, contains('max notional \$100'));
    expect(text, contains('maxOpenProposals=3'));
  });
}
