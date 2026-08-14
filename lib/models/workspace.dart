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

    Workspace({
        required this.uuid,
        required this.name,
        required this.projectRoot,
        this.autoStart = true,
        required this.createdAt,
        required this.lastActiveAt,
        this.enabled = true,
    });

    String get mcpPath => '/$uuid/mcp';

    Workspace copyWith({
        String? name,
        String? projectRoot,
        bool? autoStart,
        DateTime? lastActiveAt,
        bool? enabled,
    }) {
        return Workspace(
            uuid: uuid,
            name: name ?? this.name,
            projectRoot: projectRoot ?? this.projectRoot,
            autoStart: autoStart ?? this.autoStart,
            createdAt: createdAt,
            lastActiveAt: lastActiveAt ?? this.lastActiveAt,
            enabled: enabled ?? this.enabled,
        );
    }
}
