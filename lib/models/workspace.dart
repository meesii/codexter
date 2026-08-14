import 'package:hive/hive.dart';

part 'workspace.g.dart';

@HiveType(typeId: 1)
class Workspace extends HiveObject {
  @HiveField(0)
  String uuid;

  @HiveField(1)
  String name;

  @HiveField(2)
  String projectRoot;

  @HiveField(3)
  bool autoStart;

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  DateTime lastActiveAt;

  @HiveField(6)
  bool enabled;

  /// null 表示跟随全局已启用 Skills；非 null 时仅加载指定名称。
  @HiveField(7)
  List<String>? selectedSkillNames;

  /// null 表示跟随全局已启用 MCP；非 null 时仅加载指定名称。
  @HiveField(8)
  List<String>? selectedMcpNames;

  /// Agents 模式：auto 自动读取项目文件，custom 使用工作区自定义内容，disabled 禁用。
  @HiveField(9)
  String agentsMode;

  /// agentsMode=custom 时发送给 ChatGPT 的项目级指令。
  @HiveField(10)
  String customAgents;

  static const agentsAuto = 'auto';
  static const agentsCustom = 'custom';
  static const agentsDisabled = 'disabled';

  Workspace({
    required this.uuid,
    required this.name,
    required this.projectRoot,
    this.autoStart = true,
    required this.createdAt,
    required this.lastActiveAt,
    this.enabled = true,
    this.selectedSkillNames,
    this.selectedMcpNames,
    this.agentsMode = agentsAuto,
    this.customAgents = '',
  });

  String get mcpPath => '/$uuid/mcp';

  Workspace copyWith({
    String? name,
    String? projectRoot,
    bool? autoStart,
    DateTime? lastActiveAt,
    bool? enabled,
    List<String>? selectedSkillNames,
    List<String>? selectedMcpNames,
    String? agentsMode,
    String? customAgents,
    bool clearSelectedSkillNames = false,
    bool clearSelectedMcpNames = false,
  }) {
    return Workspace(
      uuid: uuid,
      name: name ?? this.name,
      projectRoot: projectRoot ?? this.projectRoot,
      autoStart: autoStart ?? this.autoStart,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      enabled: enabled ?? this.enabled,
      selectedSkillNames: clearSelectedSkillNames
          ? null
          : (selectedSkillNames ?? this.selectedSkillNames),
      selectedMcpNames: clearSelectedMcpNames
          ? null
          : (selectedMcpNames ?? this.selectedMcpNames),
      agentsMode: agentsMode ?? this.agentsMode,
      customAgents: customAgents ?? this.customAgents,
    );
  }
}
