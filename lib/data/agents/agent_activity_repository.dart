import 'package:flutter/foundation.dart';

import '../settings/config_list_slice.dart';
import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'agent_activity.dart';

class AgentActivityRepository extends ChangeNotifier {
  AgentActivityRepository({this.store});

  UserConfigStore? store;
  List<AgentActivityEvent> _events = const [];
  bool _ready = false;

  static const maxStored = 300;

  bool get isReady => _ready;
  List<AgentActivityEvent> get events => List.unmodifiable(_events);

  List<AgentActivityEvent> forRole(String roleId) => [
        for (final e in _events)
          if (e.roleId == roleId) e,
      ];

  List<AgentActivityEvent> forProposal(String proposalId) => [
        for (final e in _events)
          if (e.proposalId == proposalId) e,
      ];

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final slice = this.store?.getSlice(UserConfigKeys.agentActivity);
    _events = ConfigListSlice.parseItems(
      slice,
      'events',
      (json) {
        final e = AgentActivityEvent.fromJson(json);
        return e.id.isNotEmpty ? e : null;
      },
    );
    _ready = true;
    notifyListeners();
  }

  Future<void> add(AgentActivityEvent event) async {
    _events = ConfigListSlice.prependCapped(
      _events,
      event,
      maxStored: maxStored,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _events = const [];
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await ConfigListSlice.persist(
      store,
      sliceKey: UserConfigKeys.agentActivity,
      listKey: 'events',
      items: _events,
      toJson: (e) => e.toJson(),
    );
  }
}
