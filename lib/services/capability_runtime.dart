import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/downstream_mcp_entry.dart';
import '../models/skill_entry.dart';
import 'downstream_client.dart';

/// 全局共享的能力集：Skills + 下游 MCP 连接池 + ChatGPT 可读写的设置
class CapabilityRuntime extends ChangeNotifier {
  final Map<String, DownstreamClient> _clients = {};
  final Map<String, dynamic> _settings = {'verbosity': 'normal', 'autoSummary': true};

  List<SkillEntry> _skills = const [];

  List<SkillEntry> get skills => _skills;

  List<SkillEntry> get enabledSkills => _skills.where((skill) => skill.enabled).toList();

  List<DownstreamClient> get clients {
    final list = _clients.values.toList();
    list.sort((left, right) => left.name.compareTo(right.name));
    return list;
  }

  Map<String, dynamic> get settings => Map.unmodifiable(_settings);

  DownstreamClient? clientOf(String name) => _clients[name];

  void syncSkills(List<SkillEntry> skills) {
    _skills = List.unmodifiable(skills);
    notifyListeners();
  }

  /// 按最新配置增删连接：禁用/删除的断开，新启用的建连
  Future<void> syncMcps(List<DownstreamMcpEntry> entries) async {
    final enabledEntries = entries.where((entry) => entry.enabled).toList();
    final enabledNames = enabledEntries.map((entry) => entry.name).toSet();

    final staleNames = _clients.keys.where((name) => !enabledNames.contains(name)).toList();
    for (final name in staleNames) {
      final client = _clients.remove(name);
      await client?.close();
    }

    for (final entry in enabledEntries) {
      final existing = _clients[entry.name];
      if (existing != null && existing.entry.transportJson == entry.transportJson) {
        continue;
      }
      await existing?.close();
      _clients[entry.name] = DownstreamClient(entry);
    }

    notifyListeners();
    await _connectPending();
  }

  Future<void> reconnect(String name) async {
    final client = _clients[name];
    if (client == null) return;
    await client.close();
    final fresh = DownstreamClient(client.entry);
    _clients[name] = fresh;
    notifyListeners();
    await _connectOne(fresh);
  }

  Future<void> reconnectAll() async {
    final entries = _clients.values.map((client) => client.entry).toList();
    for (final client in _clients.values) {
      await client.close();
    }
    _clients.clear();
    for (final entry in entries) {
      _clients[entry.name] = DownstreamClient(entry);
    }
    notifyListeners();
    await _connectPending();
  }

  void updateSettings(Map<String, dynamic> patch) {
    _settings.addAll(patch);
    notifyListeners();
  }

  Future<void> shutdown() async {
    for (final client in _clients.values) {
      await client.close();
    }
    _clients.clear();
  }

  Future<void> _connectPending() async {
    final pending = _clients.values
        .where((client) => client.state == DownstreamState.idle)
        .toList();
    await Future.wait(pending.map(_connectOne));
  }

  Future<void> _connectOne(DownstreamClient client) async {
    try {
      await client.connect();
    } catch (error) {
      debugPrint('下游 MCP ${client.name} 连接失败: $error');
    }
    notifyListeners();
  }
}
