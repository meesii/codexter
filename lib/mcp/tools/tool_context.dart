import '../../models/summary_notice.dart';
import '../../models/skill_entry.dart';
import '../../models/workspace.dart';
import '../../services/capability_runtime.dart';
import '../../services/downstream_client.dart';
import '../../services/process_session_manager.dart';
import '../../stores/log_store.dart';
import '../../utils/path_guard.dart';

/// 一个工作区内所有工具共享的运行期依赖
class ToolContext {
  final Workspace workspace;
  final PathGuard pathGuard;
  final ProcessSessionManager processManager;
  final CapabilityRuntime capabilities;
  final LogStore logStore;
  final SummaryHandler? onSummary;
  final DateTime startedAt = DateTime.now();

  ToolContext({
    required this.workspace,
    required this.pathGuard,
    required this.processManager,
    required this.capabilities,
    required this.logStore,
    this.onSummary,
  });

  String get projectRoot => workspace.projectRoot;

  List<SkillEntry> get enabledSkills {
    final skills = capabilities.enabledSkills;
    final selected = workspace.selectedSkillNames;
    if (selected == null) return skills;
    final allowed = selected.toSet();
    return skills.where((skill) => allowed.contains(skill.name)).toList();
  }

  List<DownstreamClient> get downstreamClients {
    final clients = capabilities.clients;
    final selected = workspace.selectedMcpNames;
    if (selected == null) return clients;
    final allowed = selected.toSet();
    return clients.where((client) => allowed.contains(client.name)).toList();
  }

  DownstreamClient? downstreamClientOf(String name) {
    final selected = workspace.selectedMcpNames;
    if (selected != null && !selected.contains(name)) return null;
    return capabilities.clientOf(name);
  }
}
