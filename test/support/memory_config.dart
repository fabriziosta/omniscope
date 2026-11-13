import 'package:omniscope/data/settings/user_config_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory [UserConfigStore] for unit/widget tests (no filesystem writes).
Future<UserConfigStore> memoryConfig({
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final store = UserConfigStore(memoryOnly: true);
  await store.load();
  return store;
}
