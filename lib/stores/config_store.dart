import 'package:hive/hive.dart';
import '../models/global_config.dart';
import '../models/workspace.dart';
import '../models/skill_entry.dart';
import '../models/downstream_mcp_entry.dart';

const globalConfigBoxName = 'global_config';
const workspaceBoxName = 'workspaces';
const skillBoxName = 'skills';
const mcpBoxName = 'downstream_mcps';

class ConfigStore {
  static Future<void> init() async {
    await Hive.openBox<GlobalConfig>(globalConfigBoxName);
    await Hive.openBox<Workspace>(workspaceBoxName);
    await Hive.openBox<SkillEntry>(skillBoxName);
    await Hive.openBox<DownstreamMcpEntry>(mcpBoxName);
  }

  static GlobalConfig getGlobalConfig() {
    final box = Hive.box<GlobalConfig>(globalConfigBoxName);
    return box.get('config') ?? GlobalConfig();
  }

  static Future<void> saveGlobalConfig(GlobalConfig config) async {
    final box = Hive.box<GlobalConfig>(globalConfigBoxName);
    await box.put('config', config);
  }

  static List<Workspace> getWorkspaces() {
    final box = Hive.box<Workspace>(workspaceBoxName);
    final workspaces = box.values.toList();
    workspaces.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return workspaces;
  }

  static Future<void> saveWorkspace(Workspace workspace) async {
    final box = Hive.box<Workspace>(workspaceBoxName);
    await box.put(workspace.uuid, workspace);
  }

  static Future<void> deleteWorkspace(String uuid) async {
    final box = Hive.box<Workspace>(workspaceBoxName);
    await box.delete(uuid);
  }

  static List<SkillEntry> getSkills() {
    final box = Hive.box<SkillEntry>(skillBoxName);
    final skills = box.values.toList();
    skills.sort((left, right) => left.name.compareTo(right.name));
    return skills;
  }

  static Future<void> saveSkill(SkillEntry skill) async {
    final box = Hive.box<SkillEntry>(skillBoxName);
    await box.put(skill.name, skill);
  }

  static Future<void> deleteSkill(String name) async {
    final box = Hive.box<SkillEntry>(skillBoxName);
    await box.delete(name);
  }

  static List<DownstreamMcpEntry> getMcps() {
    final box = Hive.box<DownstreamMcpEntry>(mcpBoxName);
    final mcps = box.values.toList();
    mcps.sort((left, right) => left.name.compareTo(right.name));
    return mcps;
  }

  static Future<void> saveMcp(DownstreamMcpEntry mcp) async {
    final box = Hive.box<DownstreamMcpEntry>(mcpBoxName);
    await box.put(mcp.name, mcp);
  }

  static Future<void> deleteMcp(String name) async {
    final box = Hive.box<DownstreamMcpEntry>(mcpBoxName);
    await box.delete(name);
  }
}
