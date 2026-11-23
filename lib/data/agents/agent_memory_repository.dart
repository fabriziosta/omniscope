import 'package:flutter/foundation.dart';

import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'agent_memory.dart';

/// Shared cross-chat agent memory (facts) under the `agentMemory` config slice.
///
/// Memory-on chats may read/write via Genkit tools; users edit in Settings.
/// Caps keep prompts small: [maxFacts] entries, [maxFactLength] chars each.
class AgentMemoryRepository extends ChangeNotifier {
  AgentMemoryRepository({this.store});

  UserConfigStore? store;

  static const int maxFacts = 50;
  static const int maxFactLength = 280;

  final List<AgentMemoryFact> _facts = [];
  bool _ready = false;

  bool get isReady => _ready;

  List<AgentMemoryFact> get facts => List.unmodifiable(_facts);

  /// Compact summary for system prompts (empty when no facts).
  String toAgentSummary() {
    if (_facts.isEmpty) return '';
    final lines = <String>[];
    for (final fact in _facts) {
      final text = fact.text.trim();
      if (text.isEmpty) continue;
      lines.add('- [${fact.id}] $text (${fact.source.label})');
    }
    if (lines.isEmpty) return '';
    return 'Shared agent memory (durable facts across Memory-on chats):\n'
        '${lines.join('\n')}';
  }

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    _applySlice(this.store?.getSlice(UserConfigKeys.agentMemory));
    _ready = true;
    notifyListeners();
  }

  /// Adds a fact. Dedupes by normalized text; enforces length and count caps.
  ///
  /// Returns the stored fact, or `null` when [text] is empty / oversize.
  Future<AgentMemoryFact?> addFact(
    String text, {
    AgentMemorySource source = AgentMemorySource.user,
    String? id,
  }) async {
    final cleaned = _normalizeText(text);
    if (cleaned == null) return null;

    final existingIndex = _indexOfNormalized(cleaned);
    if (existingIndex >= 0) {
      final prev = _facts[existingIndex];
      final updated = prev.copyWith(
        text: cleaned,
        updatedAt: DateTime.now().toUtc(),
        source: source,
      );
      _facts[existingIndex] = updated;
      _facts
        ..removeAt(existingIndex)
        ..insert(0, updated);
      notifyListeners();
      await _persist();
      return updated;
    }

    final fact = AgentMemoryFact(
      id: (id?.trim().isNotEmpty == true) ? id!.trim() : AgentMemoryFact.newId(),
      text: cleaned,
      updatedAt: DateTime.now().toUtc(),
      source: source,
    );
    _facts.insert(0, fact);
    _trimToCap();
    notifyListeners();
    await _persist();
    return fact;
  }

  Future<AgentMemoryFact?> updateFact(String id, String text) async {
    final key = id.trim();
    if (key.isEmpty) return null;
    final cleaned = _normalizeText(text);
    if (cleaned == null) return null;
    final index = _facts.indexWhere((f) => f.id == key);
    if (index < 0) return null;

    final updated = _facts[index].copyWith(
      text: cleaned,
      updatedAt: DateTime.now().toUtc(),
    );
    _facts.removeAt(index);
    // Drop other facts that now collide on normalized text.
    final norm = _normalizeKey(cleaned);
    _facts.removeWhere((f) => _normalizeKey(f.text) == norm);
    _facts.insert(0, updated);
    notifyListeners();
    await _persist();
    return updated;
  }

  /// Removes by id, or by matching normalized text when [idOrText] is not an id.
  Future<bool> removeFact(String idOrText) async {
    final key = idOrText.trim();
    if (key.isEmpty) return false;
    final byId = _facts.indexWhere((f) => f.id == key);
    if (byId >= 0) {
      _facts.removeAt(byId);
      notifyListeners();
      await _persist();
      return true;
    }
    final normalized = _normalizeKey(key);
    final before = _facts.length;
    _facts.removeWhere((f) => _normalizeKey(f.text) == normalized);
    if (_facts.length == before) return false;
    notifyListeners();
    await _persist();
    return true;
  }

  Future<void> clearAll() async {
    if (_facts.isEmpty) return;
    _facts.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.agentMemory, {
      'facts': [for (final f in _facts) f.toJson()],
    });
  }

  void _applySlice(Object? slice) {
    _facts.clear();
    if (slice is! Map) return;
    final map = Map<String, dynamic>.from(slice);
    final raw = map['facts'];
    if (raw is! List) return;
    final seenText = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final fact = AgentMemoryFact.fromJson(
          Map<String, dynamic>.from(item),
        );
        final text = _normalizeText(fact.text);
        if (text == null) continue;
        final id = fact.id.trim();
        if (id.isEmpty) continue;
        final norm = _normalizeKey(text);
        if (!seenText.add(norm)) continue;
        _facts.add(fact.copyWith(text: text));
        if (_facts.length >= maxFacts) break;
      } catch (_) {
        // Skip corrupt entries.
      }
    }
  }

  void _trimToCap() {
    while (_facts.length > maxFacts) {
      _facts.removeLast();
    }
  }

  int _indexOfNormalized(String cleaned) {
    final key = _normalizeKey(cleaned);
    return _facts.indexWhere((f) => _normalizeKey(f.text) == key);
  }

  /// Returns trimmed text ≤ [maxFactLength], or null if empty / too long.
  static String? _normalizeText(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return null;
    if (cleaned.length > maxFactLength) return null;
    return cleaned;
  }

  static String _normalizeKey(String text) => text.trim().toLowerCase();
}
