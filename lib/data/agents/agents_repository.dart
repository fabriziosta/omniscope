import 'package:flutter/foundation.dart';

import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'agent_role_catalog.dart';
import 'models.dart';

class AgentsRepository extends ChangeNotifier {
  AgentsRepository({
    this.store,
    this._roleCatalog,
  });

  UserConfigStore? store;
  AgentRoleCatalog? _roleCatalog;
  AgentsState _state = const AgentsState(connections: []);
  bool _ready = false;

  AgentsState get state => _state;
  bool get isReady => _ready;
  AgentRoleCatalog? get roleCatalog => _roleCatalog;

  List<AgentRoleDefinition> get availableRoles =>
      _roleCatalog?.roles ?? const [];

  List<AgentConnection> get connections => _state.connections;

  List<String> get _roleIds => _roleCatalog?.roleIds ?? const [];

  AgentConnection forRoleId(String roleId) => _state.forRoleId(roleId);

  /// Load persisted connections scoped to the agents manifest.
  Future<void> load({
    UserConfigStore? store,
    AgentRoleCatalog? roleCatalog,
  }) async {
    if (store != null) this.store = store;
    if (roleCatalog != null) {
      _roleCatalog = roleCatalog;
    }
    final slice = this.store?.getSlice(UserConfigKeys.agents);
    final roleIds = _roleIds;
    if (slice is! Map) {
      _state = AgentsState.forRoles(roleIds);
    } else {
      try {
        _state = AgentsState.fromJson(
          Map<String, dynamic>.from(slice),
          availableRoleIds: roleIds,
        );
      } catch (_) {
        _state = AgentsState.forRoles(roleIds);
      }
    }
    _ready = true;
    notifyListeners();
  }

  /// Align stored slots with the current agents manifest (e.g. after UI reload).
  Future<void> syncAvailableRoles(AgentRoleCatalog catalog) async {
    _roleCatalog = catalog;
    _state = AgentsState(
      connections: [
        for (final id in catalog.roleIds) _state.forRoleId(id),
      ],
    );
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.agents, _state.toJson());
  }

  /// Persist credentials and mark the role connected.
  Future<String?> connect({
    required String roleId,
    required LlmProvider llmProvider,
    required String apiKey,
    required String modelId,
    String? baseUrl,
    bool autopilotEnabled = false,
    String? autopilotExchangeId,
    double? autopilotMaxNotional,
    int autopilotMaxOpenProposals = 3,
    bool scheduleEnabled = false,
    AgentScheduleInterval scheduleInterval = AgentScheduleInterval.hour1,
    List<String> scheduleSymbols = const [],
  }) async {
    if (_roleCatalog != null && _roleCatalog!.byId(roleId) == null) {
      return 'Unknown agent role.';
    }
    final key = apiKey.trim();
    final model = modelId.trim();
    if (roleId.isEmpty) return 'Role is required.';
    if (key.isEmpty) return 'API key is required.';
    if (model.isEmpty) return 'Model is required.';
    if (llmProvider == LlmProvider.custom) {
      final url = baseUrl?.trim() ?? '';
      if (url.isEmpty) return 'Base URL is required for Custom.';
    }

    final symbols = normalizeScheduleSymbols(scheduleSymbols);
    if (scheduleEnabled && symbols.isEmpty) {
      return 'Schedule needs at least one symbol.';
    }

    final existing = _state.forRoleId(roleId);
    final connection = AgentConnection(
      roleId: roleId,
      llmProvider: llmProvider,
      apiKey: key,
      modelId: model,
      baseUrl: llmProvider == LlmProvider.custom ? baseUrl?.trim() : null,
      connected: true,
      autopilotEnabled: autopilotEnabled,
      autopilotExchangeId: autopilotExchangeId?.trim().isEmpty == true
          ? null
          : autopilotExchangeId?.trim(),
      autopilotMaxNotional: autopilotMaxNotional,
      autopilotMaxOpenProposals: autopilotMaxOpenProposals < 1
          ? 1
          : autopilotMaxOpenProposals,
      scheduleEnabled: scheduleEnabled,
      scheduleInterval: scheduleInterval,
      scheduleSymbols: symbols,
      // Keep last-run stamp across Edit so reconnect does not immediately re-fire.
      scheduleLastRunAt: existing.scheduleLastRunAt,
    );
    _state = _state.withConnection(connection);
    await _persist();
    notifyListeners();
    return null;
  }

  /// Record when a scheduled batch started for [roleId].
  Future<void> updateScheduleLastRunAt(String roleId, DateTime at) async {
    final existing = _state.forRoleId(roleId);
    _state = _state.withConnection(
      existing.copyWith(scheduleLastRunAt: at.toUtc()),
    );
    await _persist();
    notifyListeners();
  }

  /// Disconnect and clear the stored API key (turns Autopilot / Schedule off).
  Future<void> disconnect(String roleId) async {
    final existing = _state.forRoleId(roleId);
    _state = _state.withConnection(
      AgentConnection(
        roleId: roleId,
        llmProvider: existing.llmProvider,
        apiKey: '',
        modelId: existing.modelId,
        baseUrl: existing.baseUrl,
        connected: false,
        autopilotEnabled: false,
        autopilotExchangeId: existing.autopilotExchangeId,
        autopilotMaxNotional: existing.autopilotMaxNotional,
        autopilotMaxOpenProposals: existing.autopilotMaxOpenProposals,
        scheduleEnabled: false,
        scheduleInterval: existing.scheduleInterval,
        scheduleSymbols: existing.scheduleSymbols,
        scheduleLastRunAt: existing.scheduleLastRunAt,
      ),
    );
    await _persist();
    notifyListeners();
  }
}
