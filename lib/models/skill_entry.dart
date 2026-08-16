import 'package:hive/hive.dart';

part 'skill_entry.g.dart';

@HiveType(typeId: 2)
class SkillEntry extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String description;

  @HiveField(2)
  String source;

  @HiveField(3)
  String? rootPath;

  @HiveField(4)
  bool enabled;

  @HiveField(5)
  DateTime createdAt;

  SkillEntry({
    required this.name,
    required this.description,
    required this.source,
    this.rootPath,
    this.enabled = true,
    required this.createdAt,
  });

  bool get isCodexImport => source == 'codex_import';

  SkillEntry copyWith({String? name, String? description, bool? enabled}) {
    return SkillEntry(
      name: name ?? this.name,
      description: description ?? this.description,
      source: source,
      rootPath: rootPath,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
    );
  }
}
