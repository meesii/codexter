import '../../models/workspace.dart';
import '../../services/capability_runtime.dart';
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
    final DateTime startedAt = DateTime.now();

    ToolContext({
        required this.workspace,
        required this.pathGuard,
        required this.processManager,
        required this.capabilities,
        required this.logStore,
    });

    String get projectRoot => workspace.projectRoot;
}
