import 'package:genkit/genkit.dart';

import '../../settings/mandate_settings.dart';
import '../invest_interest_proposal.dart';
import 'omniscope_agent_tool_helpers.dart';
import 'omniscope_agent_tools.dart';

/// Registers Invest interest proposal tools on [ai].
List<Tool<dynamic, dynamic>> defineOmniscopeProposalTools(
  Genkit ai,
  OmniscopeAgentToolDeps deps,
) {
  final inputSchema = OmniscopeAgentToolHelpers.symbolInput;

  final proposeInvestInterestDiff = ai.defineTool(
    name: 'proposeInvestInterestDiff',
    description:
        'Propose a change to Markets → Invest interest. '
        'Input: {"add":["AAPL"],"remove":["MSFT"],"rationale":"why"} '
        'or {"set":["AAPL","SPY"],"rationale":"why"} for a full replace. '
        'Respect getMandate maxSymbols and universe. '
        '${deps.autopilotEnabled ? 'Autopilot is ON: add-only proposals '
            '(non-empty add, empty remove, no set) from investigation '
            'roles may apply without Confirm; remove/set still need '
            'Confirm. Prefer add-only when suggesting new symbols. ' : ''}'
        'Otherwise the user taps Confirm under the proposal card in this '
        'chat — do not claim the list already changed unless Autopilot '
        'applied an add. Activity is read-only archive (Open chat).',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final propose = deps.proposeInvestInterest;
      if (propose == null) {
        return .response(
          'Invest interest proposals are not available in this turn.',
        );
      }
      final map = OmniscopeAgentToolHelpers.asMap(input);
      final add = OmniscopeAgentToolHelpers.readSymbolList(map['add']);
      final remove = OmniscopeAgentToolHelpers.readSymbolList(map['remove']);
      final setRaw = map['set'] ?? map['symbols'];
      final setSymbols =
          setRaw is List ? OmniscopeAgentToolHelpers.readSymbolList(setRaw) : null;
      final rationale = (map['rationale'] as String? ?? '').trim();
      if (rationale.isEmpty) {
        return .response('Provide a short rationale.');
      }
      if (add.isEmpty && remove.isEmpty && (setSymbols == null)) {
        return .response(
          'Provide add/remove lists, or a set list to replace Invest interest.',
        );
      }
      // Soft universe hint (Confirm still applies the proposal as-is
      // within maxSymbols).
      final mandate = deps.mandate;
      if (mandate != null && mandate.universe != MandateUniverse.both) {
        final candidates = [
          ...add,
          ...?setSymbols,
        ];
        for (final s in candidates) {
          final looksCrypto = s.contains('_') || s.contains('-');
          if (mandate.universe == MandateUniverse.equities && looksCrypto) {
            return .response(
              'Mandate universe is equities-only; do not propose crypto '
              'symbol $s. Adjust the list and try again.',
            );
          }
          if (mandate.universe == MandateUniverse.crypto && !looksCrypto) {
            return .response(
              'Mandate universe is crypto-only; do not propose equity '
              'symbol $s. Adjust the list and try again.',
            );
          }
        }
      }
      try {
        final draft = InvestInterestProposal.fromToolInput(
          {
            'add': add,
            'remove': remove,
            'set': ?setSymbols,
            'rationale': rationale,
          },
          roleId: 'tool',
        );
        if (!draft.isActionable) {
          return .response('Proposal has no actionable changes.');
        }
        return .response(
          await propose(
            add: add,
            remove: remove,
            setSymbols: setSymbols,
            rationale: rationale,
          ),
        );
      } catch (e) {
        return .response('Could not create proposal: $e');
      }
    },
  );

  return [proposeInvestInterestDiff];
}
