import 'dart:convert';

import 'package:http/http.dart' as http;

import 'agent_role_prompts.dart';
import 'chat_models.dart';
import 'models.dart';

class LlmChatException implements Exception {
  LlmChatException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'LlmChatException($statusCode): $message';
}

/// Calls the user's LLM provider with a chat completion (no streaming).
class LlmChatClient {
  LlmChatClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<String> complete({
    required AgentConnection connection,
    required String roleId,
    required List<AgentChatMessage> messages,
    String? marketContext,
  }) async {
    if (!connection.connected || !connection.isConfigured) {
      throw LlmChatException('Connect this agent before chatting.');
    }

    final system = StringBuffer(AgentRolePrompts.forRoleId(roleId));
    if (marketContext != null && marketContext.trim().isNotEmpty) {
      system
        ..writeln()
        ..writeln()
        ..writeln(marketContext.trim());
    }

    final history = messages
        .where((m) => m.role != AgentChatRole.system)
        .where((m) => m.content.trim().isNotEmpty)
        .toList(growable: false);

    return switch (connection.llmProvider) {
      LlmProvider.openAi ||
      LlmProvider.deepSeek ||
      LlmProvider.grok ||
      LlmProvider.custom =>
        _completeOpenAiCompatible(
          connection: connection,
          system: system.toString(),
          messages: history,
        ),
      LlmProvider.anthropic => _completeAnthropic(
          connection: connection,
          system: system.toString(),
          messages: history,
        ),
      LlmProvider.gemini => _completeGemini(
          connection: connection,
          system: system.toString(),
          messages: history,
        ),
    };
  }

  String _openAiBaseUrl(AgentConnection connection) {
    switch (connection.llmProvider) {
      case LlmProvider.openAi:
        return 'https://api.openai.com/v1';
      case LlmProvider.deepSeek:
        return 'https://api.deepseek.com';
      case LlmProvider.grok:
        return 'https://api.x.ai/v1';
      case LlmProvider.custom:
        final raw = connection.baseUrl?.trim() ?? '';
        if (raw.isEmpty) {
          throw LlmChatException('Base URL is required for Custom.');
        }
        return raw.replaceAll(RegExp(r'/+$'), '');
      default:
        return 'https://api.openai.com/v1';
    }
  }

  Future<String> _completeOpenAiCompatible({
    required AgentConnection connection,
    required String system,
    required List<AgentChatMessage> messages,
  }) async {
    final base = _openAiBaseUrl(connection);
    final uri = Uri.parse('$base/chat/completions');
    final body = {
      'model': connection.modelId,
      'messages': [
        {'role': 'system', 'content': system},
        for (final m in messages)
          {
            'role': m.role == AgentChatRole.assistant ? 'assistant' : 'user',
            'content': m.content,
          },
      ],
    };

    final response = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${connection.apiKey}',
      },
      body: jsonEncode(body),
    );
    return _parseOpenAiResponse(response);
  }

  String _parseOpenAiResponse(http.Response response) {
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      json = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final err = json?['error'];
      String detail = 'Request failed (${response.statusCode}).';
      if (err is Map && err['message'] is String) {
        detail = err['message'] as String;
      }
      throw LlmChatException(detail, statusCode: response.statusCode);
    }

    final choices = json?['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw LlmChatException('Empty response from the model.');
    }
    final message = (choices.first as Map)['message'] as Map?;
    final content = message?['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    throw LlmChatException('Empty response from the model.');
  }

  Future<String> _completeAnthropic({
    required AgentConnection connection,
    required String system,
    required List<AgentChatMessage> messages,
  }) async {
    final uri = Uri.parse('https://api.anthropic.com/v1/messages');
    final body = {
      'model': connection.modelId,
      'max_tokens': 2048,
      'system': system,
      'messages': [
        for (final m in messages)
          {
            'role': m.role == AgentChatRole.assistant ? 'assistant' : 'user',
            'content': m.content,
          },
      ],
    };

    final response = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': connection.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    );

    Map<String, dynamic>? json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      json = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final err = json?['error'];
      String detail = 'Request failed (${response.statusCode}).';
      if (err is Map && err['message'] is String) {
        detail = err['message'] as String;
      }
      throw LlmChatException(detail, statusCode: response.statusCode);
    }

    final content = json?['content'] as List?;
    if (content == null || content.isEmpty) {
      throw LlmChatException('Empty response from the model.');
    }
    final parts = <String>[];
    for (final block in content) {
      if (block is Map && block['type'] == 'text' && block['text'] is String) {
        parts.add(block['text'] as String);
      }
    }
    final text = parts.join('\n').trim();
    if (text.isEmpty) {
      throw LlmChatException('Empty response from the model.');
    }
    return text;
  }

  Future<String> _completeGemini({
    required AgentConnection connection,
    required String system,
    required List<AgentChatMessage> messages,
  }) async {
    final model = Uri.encodeComponent(connection.modelId);
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'
      '?key=${Uri.encodeQueryComponent(connection.apiKey)}',
    );

    final contents = <Map<String, dynamic>>[];
    for (final m in messages) {
      contents.add({
        'role': m.role == AgentChatRole.assistant ? 'model' : 'user',
        'parts': [
          {'text': m.content},
        ],
      });
    }

    final body = {
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': contents,
    };

    final response = await _http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    Map<String, dynamic>? json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      json = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final err = json?['error'];
      String detail = 'Request failed (${response.statusCode}).';
      if (err is Map && err['message'] is String) {
        detail = err['message'] as String;
      }
      throw LlmChatException(detail, statusCode: response.statusCode);
    }

    final candidates = json?['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw LlmChatException('Empty response from the model.');
    }
    final content = (candidates.first as Map)['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw LlmChatException('Empty response from the model.');
    }
    final texts = <String>[];
    for (final p in parts) {
      if (p is Map && p['text'] is String) {
        texts.add(p['text'] as String);
      }
    }
    final text = texts.join('\n').trim();
    if (text.isEmpty) {
      throw LlmChatException('Empty response from the model.');
    }
    return text;
  }
}
