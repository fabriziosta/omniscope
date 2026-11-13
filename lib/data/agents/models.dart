enum AgentFramework {
  crewAi,
  langGraph,
}

extension AgentFrameworkX on AgentFramework {
  String get label => switch (this) {
        AgentFramework.crewAi => 'CrewAI',
        AgentFramework.langGraph => 'LangGraph',
      };

  static AgentFramework parse(String raw) {
    return AgentFramework.values.byName(raw);
  }
}

/// How heavy a model recommendation should be for this role.
enum AgentWorkload {
  /// Market investigation / research — prefer lighter models.
  investigation,

  /// Trading / risk / execution — prefer heavier models.
  trading,
}

extension AgentWorkloadX on AgentWorkload {
  String get label => switch (this) {
        AgentWorkload.investigation => 'Investigation',
        AgentWorkload.trading => 'Trading',
      };

  /// Preferred model weight for suggestions.
  ModelWeight get preferredModelWeight => switch (this) {
        AgentWorkload.investigation => ModelWeight.light,
        AgentWorkload.trading => ModelWeight.heavy,
      };
}

enum ModelWeight {
  light,
  heavy,
}

extension ModelWeightX on ModelWeight {
  static ModelWeight parse(String? raw) {
    if (raw == 'heavy') return ModelWeight.heavy;
    return ModelWeight.light;
  }
}

enum LlmProvider {
  gemini,
  openAi,
  anthropic,
  deepSeek,
  grok,
  custom,
}

extension LlmProviderX on LlmProvider {
  String get label => switch (this) {
        LlmProvider.gemini => 'Gemini',
        LlmProvider.openAi => 'ChatGPT',
        LlmProvider.anthropic => 'Claude',
        LlmProvider.deepSeek => 'DeepSeek',
        LlmProvider.grok => 'Grok',
        LlmProvider.custom => 'Custom',
      };

  /// Key used in [assets/agents/llm_models.json].
  String get catalogKey => name;
}

/// A role discovered from [agents/omniscope_agents/manifest.json].
class AgentRoleDefinition {
  const AgentRoleDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.framework,
    required this.module,
    required this.packagePath,
    required this.workload,
    required this.suggestedModels,
    this.suggestionNote,
  });

  final String id;
  final String title;
  final String description;
  final AgentFramework framework;
  final String module;
  final String packagePath;
  final AgentWorkload workload;
  final Map<LlmProvider, String> suggestedModels;
  final String? suggestionNote;

  String get frameworkLabel => framework.label;

  String? suggestedModelId(LlmProvider provider) => suggestedModels[provider];

  factory AgentRoleDefinition.fromJson(Map<String, dynamic> json) {
    final suggestedRaw =
        json['suggestedModels'] as Map<String, dynamic>? ?? const {};
    final suggested = <LlmProvider, String>{};
    for (final provider in LlmProvider.values) {
      if (provider == LlmProvider.custom) continue;
      final id = suggestedRaw[provider.catalogKey] as String?;
      if (id != null && id.isNotEmpty) {
        suggested[provider] = id;
      }
    }

    return AgentRoleDefinition(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      framework: AgentFrameworkX.parse(json['framework'] as String),
      module: json['module'] as String? ?? '',
      packagePath: json['packagePath'] as String? ?? '',
      workload: AgentWorkload.values.byName(json['workload'] as String),
      suggestedModels: suggested,
      suggestionNote: json['suggestionNote'] as String?,
    );
  }
}

class AgentConnection {
  const AgentConnection({
    required this.roleId,
    required this.llmProvider,
    required this.apiKey,
    required this.modelId,
    this.baseUrl,
    required this.connected,
  });

  final String roleId;
  final LlmProvider llmProvider;
  final String apiKey;
  final String modelId;
  final String? baseUrl;
  final bool connected;

  /// True when both a model and an API key are assigned.
  bool get isConfigured =>
      apiKey.trim().isNotEmpty && modelId.trim().isNotEmpty;

  AgentConnection copyWith({
    String? roleId,
    LlmProvider? llmProvider,
    String? apiKey,
    String? modelId,
    String? baseUrl,
    bool clearBaseUrl = false,
    bool? connected,
  }) {
    return AgentConnection(
      roleId: roleId ?? this.roleId,
      llmProvider: llmProvider ?? this.llmProvider,
      apiKey: apiKey ?? this.apiKey,
      modelId: modelId ?? this.modelId,
      baseUrl: clearBaseUrl ? null : (baseUrl ?? this.baseUrl),
      connected: connected ?? this.connected,
    );
  }

  Map<String, dynamic> toJson() => {
        // Persist as both keys for forward/back compatibility.
        'roleId': roleId,
        'role': roleId,
        'llmProvider': llmProvider.name,
        'apiKey': apiKey,
        'modelId': modelId,
        if (baseUrl != null && baseUrl!.isNotEmpty) 'baseUrl': baseUrl,
        'connected': connected,
      };

  factory AgentConnection.fromJson(Map<String, dynamic> json) {
    final roleId =
        (json['roleId'] as String?) ?? (json['role'] as String?) ?? '';
    return AgentConnection(
      roleId: roleId,
      llmProvider: LlmProvider.values.byName(json['llmProvider'] as String),
      apiKey: json['apiKey'] as String? ?? '',
      modelId: json['modelId'] as String? ?? '',
      baseUrl: json['baseUrl'] as String?,
      connected: json['connected'] as bool? ?? false,
    );
  }

  static AgentConnection disconnected(String roleId) {
    return AgentConnection(
      roleId: roleId,
      llmProvider: LlmProvider.openAi,
      apiKey: '',
      modelId: '',
      connected: false,
    );
  }
}

class AgentsState {
  const AgentsState({required this.connections});

  final List<AgentConnection> connections;

  AgentConnection forRoleId(String roleId) {
    for (final c in connections) {
      if (c.roleId == roleId) return c;
    }
    return AgentConnection.disconnected(roleId);
  }

  AgentsState withConnection(AgentConnection connection) {
    final next = <AgentConnection>[
      for (final c in connections)
        if (c.roleId == connection.roleId) connection else c,
    ];
    if (!next.any((c) => c.roleId == connection.roleId)) {
      next.add(connection);
    }
    return AgentsState(connections: next);
  }

  Map<String, dynamic> toJson() => {
        'connections': connections.map((c) => c.toJson()).toList(),
      };

  factory AgentsState.fromJson(
    Map<String, dynamic> json, {
    required List<String> availableRoleIds,
  }) {
    final raw = json['connections'] as List? ?? const [];
    final byRole = <String, AgentConnection>{};
    for (final item in raw) {
      try {
        final c = AgentConnection.fromJson(item as Map<String, dynamic>);
        if (c.roleId.isNotEmpty) byRole[c.roleId] = c;
      } catch (_) {
        // Skip corrupt entries.
      }
    }
    return AgentsState(
      connections: [
        for (final id in availableRoleIds)
          byRole[id] ?? AgentConnection.disconnected(id),
      ],
    );
  }

  factory AgentsState.forRoles(List<String> roleIds) {
    return AgentsState(
      connections: [
        for (final id in roleIds) AgentConnection.disconnected(id),
      ],
    );
  }
}
