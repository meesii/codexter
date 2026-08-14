import 'file_tools.dart';
import 'gateway_tools.dart';
import 'process_tools.dart';
import 'registry.dart';
import 'search_tools.dart';
import 'skill_tools.dart';
import 'summary_tools.dart';
import 'tool_context.dart';

/// 工作区工具集装配入口，新增工具组只需在这里追加一行
class ToolBundle {
    const ToolBundle._();

    static ToolRegistry build(ToolContext context) {
        final registry = ToolRegistry();
        FileTools.register(registry, context);
        SearchTools.register(registry, context);
        ProcessTools.register(registry, context);
        SkillTools.register(registry, context);
        GatewayTools.register(registry, context);
        SummaryTools.register(registry, context);
        return registry;
    }
}
