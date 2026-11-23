import 'package:flutter/foundation.dart';

import '../settings/config_list_slice.dart';
import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'app_notification.dart';

/// Persisted shell attention inbox (scheduled Runs, Confirm prompts, Autopilot).
///
/// Also surfaces a virtual sticky [AppNotificationKind.configureAgents]
/// reminder when no LLM API key is configured (not stored in the config slice).
class AppNotificationRepository extends ChangeNotifier {
  AppNotificationRepository({this.store});

  UserConfigStore? store;
  List<AppNotification> _items = const [];
  bool _ready = false;
  bool _configureAgentsNeeded = false;

  /// Cap on active + dismissed retained rows.
  static const maxStored = 80;

  /// Soft cap on active items shown in the bell stack.
  static const maxActive = 50;

  bool get isReady => _ready;

  /// Whether the sticky configure-Agents reminder should appear.
  bool get configureAgentsNeeded => _configureAgentsNeeded;

  List<AppNotification> get items => List.unmodifiable(_items);

  List<AppNotification> get active => [
        if (_configureAgentsNeeded) AppNotification.configureAgentsReminder(),
        for (final n in _items)
          if (n.isActive && !n.isSticky) n,
      ];

  /// Active rows the user can dismiss (excludes sticky setup reminder).
  List<AppNotification> get dismissibleActive => [
        for (final n in active)
          if (!n.isSticky) n,
      ];

  int get unreadCount => active.where((n) => !n.read).length;

  AppNotification? byId(String id) {
    if (_configureAgentsNeeded && id == AppNotification.configureAgentsId) {
      return AppNotification.configureAgentsReminder();
    }
    for (final n in _items) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Show or hide the sticky setup reminder (call when LLM keys/runtime change).
  void setConfigureAgentsNeeded(bool needed) {
    if (_configureAgentsNeeded == needed) return;
    _configureAgentsNeeded = needed;
    notifyListeners();
  }

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final slice = this.store?.getSlice(UserConfigKeys.notifications);
    _items = ConfigListSlice.parseItems(
      slice,
      'items',
      (json) {
        final n = AppNotification.fromJson(json);
        // Sticky setup is virtual — drop any legacy persisted copies.
        if (n.id.isEmpty || n.isSticky) return null;
        return n;
      },
    );
    _ready = true;
    notifyListeners();
  }

  /// Enqueue [notification], replacing an active duplicate of the same
  /// role + symbol + kind (+ proposalId when set).
  Future<AppNotification> enqueue(AppNotification notification) async {
    // Sticky setup reminder is virtual — never persist it.
    if (notification.isSticky) {
      setConfigureAgentsNeeded(true);
      return AppNotification.configureAgentsReminder();
    }
    final incoming = notification.copyWith(
      status: AppNotificationStatus.active,
    );
    _items = ConfigListSlice.prependCapped(
      _items,
      incoming,
      maxStored: maxStored,
      exclude: (existing) =>
          existing.isActive && _isDuplicate(existing, incoming),
    );
    _trimExcessActive();
    await _persist();
    notifyListeners();
    return incoming;
  }

  Future<void> markRead(String id) async {
    if (id == AppNotification.configureAgentsId) return;
    final index = _items.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final current = _items[index];
    if (current.isSticky || current.read) return;
    _items = List<AppNotification>.from(_items)
      ..[index] = current.copyWith(read: true);
    await _persist();
    notifyListeners();
  }

  Future<void> dismiss(String id) async {
    if (id == AppNotification.configureAgentsId) return;
    final index = _items.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final current = _items[index];
    if (current.isSticky) return;
    if (current.status == AppNotificationStatus.dismissed) return;
    _items = List<AppNotification>.from(_items)
      ..[index] = current.copyWith(
        status: AppNotificationStatus.dismissed,
        read: true,
      );
    await _persist();
    notifyListeners();
  }

  Future<void> dismissAll() async {
    if (dismissibleActive.isEmpty) return;
    _items = [
      for (final n in _items)
        if (n.isActive && !n.isSticky)
          n.copyWith(
            status: AppNotificationStatus.dismissed,
            read: true,
          )
        else
          n,
    ];
    await _persist();
    notifyListeners();
  }

  Future<void> clearDismissed() async {
    final next = [
      for (final n in _items)
        if (n.isActive) n,
    ];
    if (next.length == _items.length) return;
    _items = next;
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _items = const [];
    await _persist();
    notifyListeners();
  }

  bool _isDuplicate(AppNotification a, AppNotification b) {
    if (a.roleId != b.roleId || a.kind != b.kind) return false;
    if ((a.symbol ?? '') != (b.symbol ?? '')) return false;
    final pa = a.proposalId;
    final pb = b.proposalId;
    if (pa != null || pb != null) return pa == pb;
    return true;
  }

  void _trimExcessActive() {
    final activeIds = [
      for (final n in _items)
        if (n.isActive && !n.isSticky) n.id,
    ];
    if (activeIds.length <= maxActive) return;
    final drop = activeIds.sublist(maxActive).toSet();
    _items = [
      for (final n in _items)
        if (drop.contains(n.id))
          n.copyWith(status: AppNotificationStatus.dismissed, read: true)
        else
          n,
    ];
  }

  Future<void> _persist() async {
    await ConfigListSlice.persist(
      store,
      sliceKey: UserConfigKeys.notifications,
      listKey: 'items',
      items: _items,
      toJson: (n) => n.toJson(),
    );
  }
}
