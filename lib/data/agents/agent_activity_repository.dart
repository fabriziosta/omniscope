import '../settings/config_list_repository.dart';
import '../settings/config_list_slice.dart';
import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'agent_activity.dart';

class AgentActivityRepository extends ConfigListRepository<AgentActivityEvent> {
  AgentActivityRepository({UserConfigStore? store})
      : super(
          store: store,
          sliceKey: UserConfigKeys.agentActivity,
          listKey: 'events',
          maxStored: 300,
          idOf: (e) => e.id,
          fromJson: (json) {
            final e = AgentActivityEvent.fromJson(json);
            return e.id.isNotEmpty ? e : null;
          },
          toJson: (e) => e.toJson(),
        );

  List<AgentActivityEvent> get events => items;

  List<AgentActivityEvent> forRole(String roleId) => [
        for (final e in items)
          if (e.roleId == roleId) e,
      ];

  List<AgentActivityEvent> forProposal(String proposalId) => [
        for (final e in items)
          if (e.proposalId == proposalId) e,
      ];

  Future<void> add(AgentActivityEvent event) async {
    mutableItems = ConfigListSlice.prependCapped(
      mutableItems,
      event,
      maxStored: maxStored,
    );
    await persistItems();
    notifyListeners();
  }

  /// Prepends many events and persists once (schedule batch coalescing).
  Future<void> addAll(List<AgentActivityEvent> events) async {
    if (events.isEmpty) return;
    var next = mutableItems;
    // Preserve call order in the timeline (first event ends up deepest).
    for (final event in events.reversed) {
      next = ConfigListSlice.prependCapped(
        next,
        event,
        maxStored: maxStored,
      );
    }
    mutableItems = next;
    await persistItems();
    notifyListeners();
  }

  /// Drops timeline rows linked to [proposalId]. Returns how many were removed.
  Future<int> deleteForProposal(String proposalId) async {
    final id = proposalId.trim();
    if (id.isEmpty) return 0;
    final before = mutableItems.length;
    mutableItems = [
      for (final e in mutableItems)
        if (e.proposalId != id) e,
    ];
    final removed = before - mutableItems.length;
    if (removed == 0) return 0;
    await persistItems();
    notifyListeners();
    return removed;
  }
}
