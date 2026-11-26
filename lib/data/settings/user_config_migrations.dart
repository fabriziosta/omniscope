import '../agents/agent_app_settings.dart';
import '../agents/agent_chat_repository.dart';
import '../agents/agents_repository.dart';
import '../agents/llm_model_catalog.dart';
import '../agents/llm_runtime_settings.dart';
import 'user_config_keys.dart';
import 'user_config_store.dart';

/// One-shot document version upgrades (v1 → v2 legacy agent retirement).
abstract final class UserConfigMigrations {
  static int readVersion(UserConfigStore config) {
    final v = config.getSlice(UserConfigKeys.version);
    if (v is int && v > 0) return v;
    return 0;
  }

  /// Runs v1→v2 migrations when [readVersion] is below [UserConfigKeys.currentVersion].
  ///
  /// Returns whether any migration work ran (persist + version bump).
  static Future<bool> runOnce({
    required UserConfigStore config,
    required AgentsRepository agents,
    required LlmRuntimeSettings llmRuntime,
    required AgentAppSettings agentApp,
    required AgentChatRepository chats,
    LlmModelCatalog? llmModels,
  }) async {
    if (readVersion(config) >= UserConfigKeys.currentVersion) {
      chats.setWriteLegacyRoleIdKeys(false);
      return false;
    }

    if (llmModels != null) {
      await llmRuntime.migrateFromConnections(
        connections: agents.connections,
        catalog: llmModels,
      );
    }
    await agentApp.migrateFromConnections(agents.connections);
    await chats.migrateGlobalAutopilotIfNeeded(agentApp);
    await chats.migrateGlobalMandateIfNeeded();
    await chats.migrateGlobalAgentSettingsIfNeeded(agentApp);
    await chats.stripLegacyRoleIdKeys();
    await agents.clearLegacyConnectionsAfterMigration();

    chats.setWriteLegacyRoleIdKeys(false);

    await config.update((doc) {
      doc[UserConfigKeys.version] = UserConfigKeys.currentVersion;
    });
    return true;
  }
}
