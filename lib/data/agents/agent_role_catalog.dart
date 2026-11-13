import 'dart:convert';

import 'package:flutter/services.dart';

import 'models.dart';

/// Loads available agent roles from the Python agents package manifest.
///
/// Source of truth: [agents/omniscope_agents/manifest.json] — add a role there
/// when you add a CrewAI or LangGraph package under `agents/omniscope_agents/`.
class AgentRoleCatalog {
  AgentRoleCatalog._(this.roles);

  static const assetPath = 'agents/omniscope_agents/manifest.json';

  final List<AgentRoleDefinition> roles;

  List<String> get roleIds => [for (final r in roles) r.id];

  AgentRoleDefinition? byId(String id) {
    for (final role in roles) {
      if (role.id == id) return role;
    }
    return null;
  }

  List<AgentRoleDefinition> forWorkload(AgentWorkload workload) {
    return [for (final r in roles) if (r.workload == workload) r];
  }

  static Future<AgentRoleCatalog> load({
    AssetBundle? bundle,
    String path = assetPath,
  }) async {
    final raw = await (bundle ?? rootBundle).loadString(path);
    return AgentRoleCatalog.parse(raw);
  }

  static AgentRoleCatalog parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['roles'] as List? ?? const [];
    final roles = <AgentRoleDefinition>[];
    for (final item in list) {
      try {
        roles.add(
          AgentRoleDefinition.fromJson(item as Map<String, dynamic>),
        );
      } catch (_) {
        // Skip corrupt role entries.
      }
    }
    return AgentRoleCatalog._(roles);
  }
}
