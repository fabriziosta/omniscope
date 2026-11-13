import 'package:flutter/foundation.dart';

import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/llm_chat_client.dart';
import '../../data/agents/market_context_builder.dart';
import '../../data/agents/models.dart';
import '../../data/market/market_data_client.dart';

/// UI feedback from a chat send attempt.
sealed class AgentChatSendResult {
  const AgentChatSendResult();
}

class AgentChatSendOk extends AgentChatSendResult {
  const AgentChatSendOk();
}

class AgentChatSendFailed extends AgentChatSendResult {
  const AgentChatSendFailed(this.message);

  final String message;
}

/// Screen-scoped chat send / clear orchestration for one agent role.
class AgentChatController extends ChangeNotifier {
  AgentChatController({
    required this.role,
    required this._agents,
    required this._chats,
    required this._marketData,
    required this._llm,
  });

  final AgentRoleDefinition role;
  final AgentsRepository _agents;
  final AgentChatRepository _chats;
  final MarketDataClient _marketData;
  final LlmChatClient _llm;

  var _sending = false;

  bool get sending => _sending;

  Future<AgentChatSendResult> sendFreeform(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) {
      return const AgentChatSendOk();
    }
    return sendUserMessage(
      content: trimmed,
      kind: AgentChatMessageKind.freeform,
      symbolHint: MarketContextBuilder.extractSymbolHint(trimmed),
    );
  }

  Future<AgentChatSendResult> sendRun({
    required String symbol,
    String? side,
    double? quantity,
  }) {
    final prompt = AgentRolePrompts.runUserPrompt(
      roleId: role.id,
      symbol: symbol,
      side: side,
      quantity: quantity,
    );
    return sendUserMessage(
      content: prompt,
      kind: AgentChatMessageKind.run,
      symbolHint: symbol,
    );
  }

  Future<AgentChatSendResult> sendUserMessage({
    required String content,
    required AgentChatMessageKind kind,
    String? symbolHint,
  }) async {
    final connection = _agents.forRoleId(role.id);
    if (!connection.connected) {
      return const AgentChatSendFailed('Connect this agent before chatting.');
    }

    final userMessage = AgentChatMessage(
      id: AgentChatMessage.newId(),
      role: AgentChatRole.user,
      content: content,
      createdAt: DateTime.now().toUtc(),
      kind: kind,
    );
    await _chats.append(roleId: role.id, message: userMessage);

    _sending = true;
    notifyListeners();

    try {
      String? marketContext;
      final hint = symbolHint?.trim();
      if (hint != null && hint.isNotEmpty) {
        marketContext =
            await MarketContextBuilder(_marketData).buildForSymbol(hint);
      }

      final thread = _chats.threadFor(role.id);
      final reply = await _llm.complete(
        connection: connection,
        roleId: role.id,
        messages: thread.messages,
        marketContext: marketContext,
      );

      await _chats.append(
        roleId: role.id,
        message: AgentChatMessage(
          id: AgentChatMessage.newId(),
          role: AgentChatRole.assistant,
          content: reply,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      return const AgentChatSendOk();
    } on LlmChatException catch (e) {
      return AgentChatSendFailed(e.message);
    } catch (e, st) {
      debugPrint('Agent chat send failed: $e\n$st');
      return const AgentChatSendFailed(
        'Could not reach the model. Try again.',
      );
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> clearThread() => _chats.clearThread(role.id);
}
