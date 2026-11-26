import 'package:flutter/foundation.dart';

import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'agent_role_catalog.dart';
import 'models.dart';

/// Role catalog holder + legacy connection slice (migration / wipe only).
///
/// Product credentials live in [EnvSecretsRepository] / [LlmRuntimeSettings];
/// Autopilot / Schedule / role enable live in [AgentAppSettings].
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

  /// Wipe the legacy per-role connections slice.
  Future<void> clearAllConnections() async {
    _state = AgentsState.forRoles(_roleIds);
    await _persist();
    notifyListeners();
  }

  /// After v1→v2 promotion, drop legacy connection payloads from config.
  Future<void> clearLegacyConnectionsAfterMigration() async {
    _state = const AgentsState(connections: []);
    await _persist();
    notifyListeners();
  }
}
