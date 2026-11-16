import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/features/settings/llm_api_keys_section.dart';

void main() {
  test('providersOrderedByConfiguredKey puts keyed providers first', () {
    final ordered = providersOrderedByConfiguredKey(
      (p) => p == LlmProvider.anthropic || p == LlmProvider.grok,
    );

    expect(
      ordered.take(2),
      [LlmProvider.anthropic, LlmProvider.grok],
    );
    expect(ordered.skip(2), [
      LlmProvider.gemini,
      LlmProvider.openAi,
      LlmProvider.deepSeek,
      LlmProvider.custom,
    ]);
    expect(ordered.toSet(), LlmProvider.values.toSet());
  });
}
