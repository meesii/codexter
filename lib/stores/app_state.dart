import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../mcp/multi_workspace_server.dart';
import '../models/downstream_mcp_entry.dart';
import '../models/global_config.dart';
import '../models/mcp_log_entry.dart';
import '../models/summary_notice.dart';
import '../models/skill_entry.dart';
import '../models/workspace.dart';
import '../platform/desktop_platform.dart';
import '../services/capability_manager.dart';
import '../services/capability_runtime.dart';
import '../services/doctor_service.dart';
import '../services/notification_service.dart';
import '../services/network_proxy.dart';
import '../services/openai_tunnel_service.dart';
import '../services/secret_store.dart';
import '../services/setup_service.dart';
import '../services/tunnel_error_classifier.dart';
import '../services/tunnel_service.dart';
import '../services/update_service.dart';
import '../utils/app_paths.dart';
import 'config_store.dart';
import 'log_store.dart';

enum AppPage { home, skills, mcpManage, doctor }

/// 全局状态协调层：配置、工作区、MCP 服务、Tunnel、能力集
class AppState extends ChangeNotifier {
  final LogStore logStore = LogStore();
  final CapabilityManager capabilityManager = CapabilityManager();
  final MultiWorkspaceServer mcpServer = MultiWorkspaceServer();
  final TunnelService tunnelService = TunnelService();
  final OpenAiTunnelService openAiTunnelService = OpenAiTunnelService();
  final CapabilityRuntime capabilities = CapabilityRuntime();
  final DoctorService doctorService = DoctorService();
  final NotificationService notificationService = NotificationService();
  final SecretStore secretStore = SecretStore();
  final SetupService setupService = SetupService();
  final AppUpdateService updateService = AppUpdateService();

  GlobalConfig _config = GlobalConfig();
  List<Workspace> _workspaces = [];
  List<SkillEntry> _skills = [];
  List<DownstreamMcpEntry> _mcps = [];
  List<DoctorCheck> _doctorChecks = [];
  bool _doctorRunning = false;
  final Set<String> _doctorRunningTitles = {};
  DateTime? _doctorCheckedAt;
  Future<void>? _doctorTask;
  Future<void>? _serviceStartTask;
  Future<void>? _serviceStopTask;
  Future<void>? _shutdownTask;
  bool _servicesStopping = false;
  bool _shuttingDown = false;
  bool _tunnelStopInProgress = false;

  AppPage _currentPage = AppPage.home;
  String? _selectedWorkspaceUuid;
  String? _lastError;
  bool _initialized = false;
  bool _serverRunning = false;
  bool _tunnelRunning = false;
  bool _busy = false;
  AppUpdateInfo? _availableUpdate;
  Future<UpdateCheckResult>? _updateCheckTask;
  SummaryNotice? _latestSummary;
  int _summaryRevision = 0;
  bool _systemDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;

  GlobalConfig get config => _config;
  List<Workspace> get workspaces => _workspaces;
  List<SkillEntry> get skills => _skills;
  List<DownstreamMcpEntry> get mcps => _mcps;
  List<DoctorCheck> get doctorChecks => _doctorChecks;
  bool get doctorRunning => _doctorRunning;
  String? get doctorRunningTitle =>
      _doctorRunningTitles.isEmpty ? null : _doctorRunningTitles.first;
  AppPage get currentPage => _currentPage;
  String? get selectedWorkspaceUuid => _selectedWorkspaceUuid;
  String? get lastError => _lastError;

  /// 供横幅展示的一行摘要，不含 cloudflared 完整日志。
  String? get lastErrorSummary {
    final error = _lastError;
    if (error == null) return null;
    var line = error.split(RegExp(r'\r?\n')).first.trim();
    const prefix = 'Exception: ';
    if (line.startsWith(prefix)) line = line.substring(prefix.length);
    return line.isEmpty ? error : line;
  }

  bool get lastErrorIsTunnel {
    final text = (lastErrorSummary ?? '').toLowerCase();
    return text.contains('cloudflared') ||
        text.contains('tunnel') ||
        (lastErrorSummary ?? '').contains('隧道');
  }

  bool get initialized => _initialized;
  bool get serverRunning => _serverRunning;
  bool get tunnelRunning => _tunnelRunning;
  bool get busy => _busy;
  AppUpdateInfo? get availableUpdate => _availableUpdate;
  SummaryNotice? get latestSummary => _latestSummary;
  int get summaryRevision => _summaryRevision;
  bool get isFirstRun => !_config.firstRunCompleted;
  bool get darkMode => _config.darkMode ?? _systemDark;

  Workspace? get selectedWorkspace {
    if (_selectedWorkspaceUuid == null) return null;
    return _workspaces.firstWhereOrNull((item) => item.uuid == _selectedWorkspaceUuid);
  }

  Future<void> init() async {
    if (_initialized) return;

    Hive.init(await AppPaths.configDir);
    Hive.registerAdapter(GlobalConfigAdapter());
    Hive.registerAdapter(WorkspaceAdapter());
    Hive.registerAdapter(SkillEntryAdapter());
    Hive.registerAdapter(DownstreamMcpEntryAdapter());
    await ConfigStore.init();

    _config = await _hydrateSecureSecrets(ConfigStore.getGlobalConfig());
    NetworkProxy.configure(enabled: _config.proxyEnabled, url: _config.proxyUrl);
    await setupService.migrateLegacyCloudflareCredentials(_config.tunnelId);
    mcpServer.setWidgetDomain(_config.widgetOrigin);
    _workspaces = ConfigStore.getWorkspaces();
    _skills = await _loadSkillsFromDirectory();
    _mcps = _composeMcps(ConfigStore.getMcps());

    capabilities.syncSkills(_skills);
    capabilities.addListener(notifyListeners);
    logStore.addListener(notifyListeners);
    openAiTunnelService.addListener(_handleOpenAiTunnelStateChanged);
    await notificationService.initialize(onNotificationTap: _handleNotificationTap);
    if (_config.notificationsEnabled) {
      unawaited(notificationService.requestPermissions(sound: _config.notificationSound));
    }

    _initialized = true;
    notifyListeners();

    unawaited(capabilities.syncMcps(_mcps));
    if (desktopPlatform.supports(DesktopFeature.updateCheck)) {
      unawaited(_checkForUpdatesOnStartup());
    }
    // 已完成首次向导的环境由启动检测页负责启动服务，避免 UI 出现前后台静默失败。
  }

  Future<UpdateCheckResult> checkForUpdates() {
    final running = _updateCheckTask;
    if (running != null) return running;

    late final Future<UpdateCheckResult> task;
    task = updateService
        .check()
        .then((result) {
          _availableUpdate = result.hasUpdate ? result.latest : null;
          notifyListeners();
          return result;
        })
        .whenComplete(() {
          if (identical(_updateCheckTask, task)) {
            _updateCheckTask = null;
          }
        });
    _updateCheckTask = task;
    return task;
  }

  Future<void> _checkForUpdatesOnStartup() async {
    try {
      await checkForUpdates();
    } catch (error) {
      debugPrint('启动检查更新失败: $error');
    }
  }

  void setCurrentPage(AppPage page) {
    _currentPage = page;
    _selectedWorkspaceUuid = null;
    notifyListeners();
  }

  void selectWorkspace(String uuid) {
    _selectedWorkspaceUuid = uuid;
    notifyListeners();
  }

  void backToHome() {
    _selectedWorkspaceUuid = null;
    _currentPage = AppPage.home;
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  void _handleNotificationTap(String? workspaceUuid) {
    if (workspaceUuid == null || !_workspaces.any((item) => item.uuid == workspaceUuid)) return;
    _currentPage = AppPage.home;
    _selectedWorkspaceUuid = workspaceUuid;
    notifyListeners();
  }

  void _handleSummary(SummaryNotice notice) {
    final previous = _latestSummary;
    if (previous != null &&
        previous.workspaceUuid == notice.workspaceUuid &&
        previous.title == notice.title &&
        previous.summary == notice.summary &&
        notice.endedAt.difference(previous.endedAt).inSeconds.abs() < 3) {
      return;
    }
    _latestSummary = notice;
    _summaryRevision += 1;
    if (_config.notificationsEnabled) {
      unawaited(notificationService.showSummary(notice, sound: _config.notificationSound));
    }
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    await setThemeMode(!darkMode);
  }

  Future<void> setThemeMode(bool? darkMode) async {
    await saveGlobalConfig(_config.copyWith(darkMode: darkMode));
  }

  Future<void> rememberCloseAction({required bool minimizeToTray}) async {
    await saveGlobalConfig(
      _config.copyWith(closeToTray: minimizeToTray, closeActionRemembered: true),
    );
  }

  Future<void> resetCloseActionPreference() async {
    await saveGlobalConfig(_config.copyWith(closeActionRemembered: false));
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    await saveGlobalConfig(_config.copyWith(notificationsEnabled: enabled));
    if (enabled) {
      await notificationService.requestPermissions(sound: _config.notificationSound);
    }
  }

  Future<void> setNotificationSound(bool enabled) async {
    await saveGlobalConfig(_config.copyWith(notificationSound: enabled));
    if (_config.notificationsEnabled && enabled) {
      await notificationService.requestPermissions(sound: true);
    }
  }

  Future<String?> testNotification() async {
    if (!_config.notificationsEnabled) return '通知功能已关闭';
    return notificationService.showTest(sound: _config.notificationSound);
  }

  Future<void> setSidebarWidth(double width) async {
    await saveGlobalConfig(_config.copyWith(sidebarWidth: width.clamp(200, 340)));
  }

  void syncSystemTheme() {
    final systemDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    if (systemDark == _systemDark) return;
    _systemDark = systemDark;
    if (_config.darkMode == null) notifyListeners();
  }

  Future<GlobalConfig> _hydrateSecureSecrets(GlobalConfig persisted) async {
    final legacyKey = persisted.openAiRuntimeApiKey.trim();
    try {
      var secureKey = await secretStore.readOpenAiRuntimeApiKey();
      if (secureKey.isEmpty && legacyKey.isNotEmpty) {
        await secretStore.writeOpenAiRuntimeApiKey(legacyKey);
        secureKey = legacyKey;
      }
      if (legacyKey.isNotEmpty) {
        await ConfigStore.saveGlobalConfig(persisted.copyWith(openAiRuntimeApiKey: ''));
      }
      return persisted.copyWith(openAiRuntimeApiKey: secureKey);
    } catch (error) {
      // 安全存储暂不可用时保留旧配置，避免迁移失败导致用户现有 Key 丢失。
      debugPrint('读取或迁移 Runtime API Key 失败: $error');
      return persisted;
    }
  }

  Future<void> saveGlobalConfig(GlobalConfig config) async {
    final proxyChanged =
        config.proxyEnabled != _config.proxyEnabled || config.proxyUrl != _config.proxyUrl;
    config = config.copyWith(
      proxyUrl: NetworkProxy.normalizeUrl(config.proxyUrl, enabled: config.proxyEnabled),
    );
    final computerUseChanged = config.computerUseEnabled != _config.computerUseEnabled;
    final previousRuntimeKey = _config.openAiRuntimeApiKey.trim();
    final nextRuntimeKey = config.openAiRuntimeApiKey.trim();
    final runtimeKeyChanged = previousRuntimeKey != nextRuntimeKey;

    if (runtimeKeyChanged) {
      await secretStore.writeOpenAiRuntimeApiKey(nextRuntimeKey);
    }
    try {
      // Runtime API Key 只保留在系统安全存储；Hive 中始终写空值以兼容旧字段结构。
      await ConfigStore.saveGlobalConfig(config.copyWith(openAiRuntimeApiKey: ''));
    } catch (_) {
      if (runtimeKeyChanged) {
        try {
          await secretStore.writeOpenAiRuntimeApiKey(previousRuntimeKey);
        } catch (rollbackError) {
          debugPrint('Runtime API Key 安全存储回滚失败: $rollbackError');
        }
      }
      rethrow;
    }

    _config = config;
    NetworkProxy.configure(enabled: config.proxyEnabled, url: config.proxyUrl);
    mcpServer.setWidgetDomain(_config.widgetOrigin);
    if (computerUseChanged) {
      _mcps = _composeMcps(_mcps.where((item) => !item.isBuiltin).toList());
      await capabilities.syncMcps(_mcps);
    }
    notifyListeners();
    if (proxyChanged) _refreshDoctorIfAvailable();
  }

  Future<void> completeFirstRun(GlobalConfig config) async {
    await saveGlobalConfig(config.copyWith(firstRunCompleted: true));
  }

  Future<Workspace> createWorkspace({
    required String name,
    required String projectRoot,
    bool autoStart = true,
    List<String>? selectedSkillNames,
    List<String>? selectedMcpNames,
    String agentsMode = Workspace.agentsAuto,
    String customAgents = '',
    String? openAiTunnelId,
  }) async {
    final now = DateTime.now();
    final workspace = Workspace(
      uuid: const Uuid().v4(),
      name: name,
      projectRoot: projectRoot,
      autoStart: autoStart,
      createdAt: now,
      lastActiveAt: now,
      selectedSkillNames: selectedSkillNames,
      selectedMcpNames: selectedMcpNames,
      agentsMode: agentsMode,
      customAgents: customAgents,
      openAiTunnelId: openAiTunnelId,
    );
    _validateOpenAiWorkspaceTunnel(workspace);

    final previousWorkspaces = _workspaces;
    _workspaces = [..._workspaces, workspace];
    try {
      await ConfigStore.saveWorkspace(workspace);
      _registerHandler(workspace);
      notifyListeners();
      await _restartOpenAiTunnelsIfRunning();
      return workspace;
    } catch (error) {
      _workspaces = previousWorkspaces;
      await ConfigStore.deleteWorkspace(workspace.uuid);
      mcpServer.removeWorkspace(workspace.uuid);
      notifyListeners();
      await _restoreOpenAiTunnelsAfterWorkspaceRollback();
      rethrow;
    }
  }

  Future<void> updateWorkspace(Workspace workspace) async {
    final index = _workspaces.indexWhere((item) => item.uuid == workspace.uuid);
    if (index < 0) throw StateError('工作区不存在：${workspace.uuid}');
    _validateOpenAiWorkspaceTunnel(workspace, excludeUuid: workspace.uuid);

    final previous = _workspaces[index];
    final previousWorkspaces = _workspaces;
    _workspaces = List.of(_workspaces)..[index] = workspace;
    try {
      await ConfigStore.saveWorkspace(workspace);
      _registerHandler(workspace);
      notifyListeners();
      await _restartOpenAiTunnelsIfRunning();
    } catch (error) {
      _workspaces = previousWorkspaces;
      await ConfigStore.saveWorkspace(previous);
      _registerHandler(previous);
      notifyListeners();
      await _restoreOpenAiTunnelsAfterWorkspaceRollback();
      rethrow;
    }
  }

  Future<void> deleteWorkspace(String uuid) async {
    _workspaces = _workspaces.where((item) => item.uuid != uuid).toList();
    await ConfigStore.deleteWorkspace(uuid);
    mcpServer.removeWorkspace(uuid);
    logStore.clear(uuid);
    if (_selectedWorkspaceUuid == uuid) _selectedWorkspaceUuid = null;
    notifyListeners();
    await _restartOpenAiTunnelsIfRunning();
  }

  void _validateOpenAiWorkspaceTunnel(Workspace workspace, {String? excludeUuid}) {
    if (!_config.useOpenAiTunnel) return;
    final tunnelId = workspace.openAiTunnelId?.trim() ?? '';
    if (workspace.enabled && tunnelId.isEmpty) {
      throw const FormatException('启用的工作区必须配置 OpenAI Tunnel ID');
    }
    if (tunnelId.isNotEmpty && !SetupService.isValidOpenAiTunnelId(tunnelId)) {
      throw const FormatException('OpenAI Tunnel ID 格式无效');
    }
    final duplicate = _workspaces.firstWhereOrNull(
      (item) =>
          item.uuid != excludeUuid &&
          (item.openAiTunnelId ?? '').trim().toLowerCase() == tunnelId.toLowerCase() &&
          tunnelId.isNotEmpty,
    );
    if (duplicate != null) {
      throw StateError('该 Tunnel ID 已被工作区「${duplicate.name}」使用');
    }
  }

  Future<void> _restartOpenAiTunnelsIfRunning() async {
    if (!_config.useOpenAiTunnel || !_serverRunning || _servicesStopping || _shuttingDown) return;
    await _stopTunnel();
    _lastError = null;
    await _startTunnel();
    notifyListeners();
  }

  Future<void> _restoreOpenAiTunnelsAfterWorkspaceRollback() async {
    if (!_config.useOpenAiTunnel || !_serverRunning || _servicesStopping || _shuttingDown) return;
    try {
      await _stopTunnel();
      await _startTunnel();
    } catch (restoreError) {
      debugPrint('工作区保存回滚后恢复 OpenAI Tunnel 失败: $restoreError');
    } finally {
      notifyListeners();
    }
  }

  void _handleOpenAiTunnelStateChanged() {
    if (!_config.useOpenAiTunnel || _servicesStopping || _shuttingDown || _tunnelStopInProgress) {
      return;
    }
    final running = openAiTunnelService.isRunning;
    if (_tunnelRunning == running) return;
    final wasRunning = _tunnelRunning;
    _tunnelRunning = running;
    if (wasRunning && !running) {
      _lastError = 'OpenAI tunnel-client 连接已中断，请重新连接';
      _refreshDoctorIfAvailable();
    }
    notifyListeners();
  }

  Future<void> toggleWorkspace(String uuid, bool enabled) async {
    final workspace = _workspaces.firstWhereOrNull((item) => item.uuid == uuid);
    if (workspace == null) return;
    await updateWorkspace(workspace.copyWith(enabled: enabled));
  }

  bool isWorkspaceLive(String uuid) {
    return _serverRunning && mcpServer.hasWorkspace(uuid);
  }

  int runningProcessCount(String uuid) {
    return mcpServer.handlerOf(uuid)?.processManager.runningCount ?? 0;
  }

  List<McpLogEntry> workspaceLogs(String uuid) => logStore.entriesOf(uuid);

  List<McpLogEntry> recentLogs(String uuid, int count) => logStore.recentOf(uuid, count);

  void clearWorkspaceLogs(String uuid) => logStore.clear(uuid);

  String? latestToolPurpose(String uuid) => logStore.latestToolPurposeOf(uuid);

  McpLogEntry? latestTool(String uuid) => logStore.latestToolOf(uuid);

  McpLogEntry? activeTool(String uuid) => logStore.activeToolOf(uuid);

  WorkspaceLogStats workspaceStats(String uuid) => logStore.statsOf(uuid);

  String workspaceUrl(String uuid) => _config.workspaceUrl(uuid);

  Future<List<SkillEntry>> _loadSkillsFromDirectory() async {
    final persisted = {for (final skill in ConfigStore.getSkills()) skill.name: skill};
    final scanned = await capabilityManager.scanLocalSkills();
    final now = DateTime.now();
    return scanned.map((item) {
      final saved = persisted[item.name];
      return SkillEntry(
        name: item.name,
        description: item.description,
        source: 'local_directory',
        rootPath: item.rootPath,
        enabled: saved?.enabled ?? true,
        createdAt: saved?.createdAt ?? now,
      );
    }).toList();
  }

  Future<void> refreshSkills() async {
    _skills = await _loadSkillsFromDirectory();
    capabilities.syncSkills(_skills);
    notifyListeners();
  }

  Future<void> toggleSkill(String name, bool enabled) async {
    final index = _skills.indexWhere((item) => item.name == name);
    if (index < 0) return;
    final updated = _skills[index].copyWith(enabled: enabled);
    _skills = List.of(_skills)..[index] = updated;
    await ConfigStore.saveSkill(updated);
    capabilities.syncSkills(_skills);
    notifyListeners();
  }

  Future<void> deleteSkill(String name) async {
    final skill = _skills.firstWhereOrNull((item) => item.name == name);
    if (skill == null) return;
    final rootPath = skill.rootPath;
    if (rootPath == null || rootPath.trim().isEmpty) {
      throw StateError('Skill 缺少本地目录：$name');
    }

    await capabilityManager.deleteLocalSkill(rootPath);
    await ConfigStore.deleteSkill(name);
    await refreshSkills();
  }

  Future<void> saveMcp(DownstreamMcpEntry mcp) async {
    if (mcp.isBuiltin || mcp.name == DownstreamMcpEntry.builtinComputerUseName) {
      throw StateError('内置 MCP 不可修改');
    }
    final index = _mcps.indexWhere((item) => item.name == mcp.name);
    if (index >= 0) {
      _mcps = List.of(_mcps)..[index] = mcp;
    } else {
      _mcps = [..._mcps, mcp];
    }
    _sortMcps();
    await ConfigStore.saveMcp(mcp);
    notifyListeners();
    await capabilities.syncMcps(_mcps);
  }

  Future<void> deleteMcp(String name) async {
    if (name == DownstreamMcpEntry.builtinComputerUseName) {
      throw StateError('内置 MCP 不可删除');
    }
    _mcps = _mcps.where((item) => item.name != name).toList();
    await ConfigStore.deleteMcp(name);
    notifyListeners();
    await capabilities.syncMcps(_mcps);
  }

  Future<void> toggleMcp(String name, bool enabled) async {
    final mcp = _mcps.firstWhereOrNull((item) => item.name == name);
    if (mcp == null) return;
    if (mcp.isBuiltinComputerUse) {
      await saveGlobalConfig(_config.copyWith(computerUseEnabled: enabled));
      return;
    }
    await saveMcp(
      DownstreamMcpEntry(
        name: mcp.name,
        transportJson: mcp.transportJson,
        enabled: enabled,
        source: mcp.source,
        startupTimeoutMs: mcp.startupTimeoutMs,
        toolTimeoutMs: mcp.toolTimeoutMs,
      ),
    );
  }

  Future<void> reconnectMcp(String name) async {
    await capabilities.reconnect(name);
  }

  List<DownstreamMcpEntry> _composeMcps(List<DownstreamMcpEntry> persisted) {
    final entries = persisted
        .where((item) => item.name != DownstreamMcpEntry.builtinComputerUseName && !item.isBuiltin)
        .toList();
    if (desktopPlatform.supports(DesktopFeature.builtinComputerUse)) {
      entries.add(DownstreamMcpEntry.builtinComputerUse(enabled: _config.computerUseEnabled));
    }
    _sortMcpList(entries);
    return entries;
  }

  void _sortMcps() => _sortMcpList(_mcps);

  void _sortMcpList(List<DownstreamMcpEntry> entries) {
    entries.sort((left, right) {
      if (left.isBuiltin != right.isBuiltin) return left.isBuiltin ? -1 : 1;
      return left.name.compareTo(right.name);
    });
  }

  /// 启动本地 HttpServer 并按需拉起长驻 Tunnel。
  Future<void> startServices({int tunnelReadyTimeoutSec = 45}) {
    final current = _serviceStartTask;
    if (current != null) return current;
    if (_busy || _servicesStopping || _shuttingDown) return Future<void>.value();
    final task = _startServices(tunnelReadyTimeoutSec: tunnelReadyTimeoutSec).whenComplete(() {
      _serviceStartTask = null;
    });
    _serviceStartTask = task;
    return task;
  }

  Future<void> _startServices({required int tunnelReadyTimeoutSec}) async {
    _busy = true;
    _lastError = null;
    notifyListeners();

    try {
      await _startServer();
      if (!_servicesStopping && !_shuttingDown && _config.tunnelEnabled) {
        await _startTunnel(readyTimeoutSec: tunnelReadyTimeoutSec);
      }
    } catch (error) {
      if (!_servicesStopping && !_shuttingDown) {
        _lastError = '$error';
        debugPrint('启动服务失败: $error');
      }
    } finally {
      _busy = false;
      if (!_shuttingDown) notifyListeners();
    }
  }

  Future<void> restartServices() async {
    await stopServices();
    if (!_shuttingDown) await startServices();
  }

  Future<void> restartTunnel() async {
    if (_busy || _servicesStopping || _shuttingDown || !_config.tunnelEnabled) return;
    _busy = true;
    _lastError = null;
    notifyListeners();

    try {
      await _stopTunnel();
      await _startTunnel();
    } catch (error) {
      _lastError = '$error';
      debugPrint('重启 Tunnel 失败: $error');
    } finally {
      _busy = false;
      notifyListeners();
      _refreshDoctorIfAvailable();
    }
  }

  Future<void> stopServices() {
    final current = _serviceStopTask;
    if (current != null) return current;
    final task = _stopServices().whenComplete(() {
      _serviceStopTask = null;
    });
    _serviceStopTask = task;
    return task;
  }

  Future<void> _stopServices() async {
    _servicesStopping = true;
    try {
      // 先终止可能正在等待就绪的 Tunnel，让启动任务尽快结束；
      // 再等待启动任务收尾，避免它在停止过程中重新拉起服务。
      await _stopTunnel();
      final starting = _serviceStartTask;
      if (starting != null) await starting;
      await mcpServer.stop();
      _serverRunning = false;
    } finally {
      _servicesStopping = false;
      if (!_shuttingDown) notifyListeners();
    }
  }

  /// 环境检测页与启动检测页共用同一套修复逻辑。
  Future<void> repairDoctorCheck(DoctorCheck check) async {
    switch (check.issue) {
      case TunnelIssueCode.cloudflaredMissing:
        await setupService.downloadCloudflared();
        await saveGlobalConfig(_config.copyWith(cloudflaredBin: await AppPaths.cloudflaredPath));
        return;
      case TunnelIssueCode.originCertMissing:
        await _ensureCloudflareLogin();
        return;
      case TunnelIssueCode.tunnelMissing:
        await _provisionTunnelFromConfig();
        return;
      case TunnelIssueCode.tunnelCredentialsMissing:
        final tunnelId = _config.tunnelId;
        if (tunnelId == null || tunnelId.isEmpty) {
          await _provisionTunnelFromConfig();
          return;
        }
        if (!await setupService.ensureTunnelCredentials(tunnelId)) {
          throw Exception(
            '无法恢复 Tunnel $tunnelId 的 credentials 文件。请重新创建 Tunnel，或仍然进入主页面后在「公网服务」中处理。',
          );
        }
        await _writeTunnelConfig(tunnelId);
        await _restartServicesStrict();
        return;
      case TunnelIssueCode.tunnelConfigMissing:
        final tunnelId = _config.tunnelId;
        if (tunnelId == null || tunnelId.isEmpty) {
          await _provisionTunnelFromConfig();
          return;
        }
        await _writeTunnelConfig(tunnelId);
        await _restartServicesStrict();
        return;
      case TunnelIssueCode.localServerStopped:
      case TunnelIssueCode.originUnreachable:
        await _restartServicesStrict();
        return;
      case TunnelIssueCode.tunnelStopped:
      case TunnelIssueCode.cloudflare1033:
      case TunnelIssueCode.timeout:
        await _restartTunnelStrict();
        return;
      case TunnelIssueCode.dnsMissing:
      case TunnelIssueCode.dnsUnauthorized:
      case TunnelIssueCode.cloudflare1016:
      case TunnelIssueCode.publicHttpError:
      case TunnelIssueCode.unknown:
        await repairPublicRoute();
        return;
      case TunnelIssueCode.originTlsError:
      case TunnelIssueCode.originProtocolMismatch:
      case TunnelIssueCode.domainMissing:
        throw Exception(check.hint ?? '该问题需要手动修改配置');
      case TunnelIssueCode.none:
        return;
    }
  }

  /// 修复公网 DNS 路由，并确保 Tunnel 重新使用当前配置运行。
  Future<void> repairPublicRoute() async {
    if (!_config.useCloudflared) throw Exception('Cloudflare Tunnel 未启用');
    final domain = _config.domain.trim();
    if (domain.isEmpty) throw Exception('尚未配置公网域名');
    final tunnelId = _config.tunnelId;
    if (tunnelId == null || tunnelId.isEmpty) throw Exception('尚未创建 Tunnel');

    final bin = await _resolveCloudflaredBin();
    // DNS route 必须依赖账号级 cert.pem。缺失时先登录，而不是直接执行 route dns。
    if (!await File(await AppPaths.originCertPath).exists()) {
      await _ensureCloudflareLogin(bin: bin);
    }
    await setupService.ensureDnsRoute(bin, tunnelId, domain);
    await _restartTunnelStrict();
  }

  Future<String> _resolveCloudflaredBin() async {
    final found = await setupService.findCloudflaredBin(configuredPath: _config.cloudflaredBin);
    if (found == null || found.isEmpty) throw Exception('未找到 cloudflared');
    if (found != _config.cloudflaredBin) {
      await saveGlobalConfig(_config.copyWith(cloudflaredBin: found));
    }
    return found;
  }

  Future<void> _ensureCloudflareLogin({String? bin, bool force = false}) async {
    final executable = bin ?? await _resolveCloudflaredBin();
    final login = await setupService.loginCloudflare(executable, force: force);
    if (!login.success) throw Exception(login.error ?? 'Cloudflare 登录未完成');
  }

  Future<void> _provisionTunnelFromConfig() async {
    final domain = _config.domain.trim();
    if (domain.isEmpty) throw Exception('尚未配置公网域名，无法自动创建 Tunnel');
    final bin = await _resolveCloudflaredBin();
    await _ensureCloudflareLogin(bin: bin);
    final tunnelId = await setupService.createTunnel(bin, _config.tunnelName);
    await setupService.ensureDnsRoute(bin, tunnelId, domain);
    final updated = await setupService.writeTunnelConfig(
      _config.copyWith(cloudflaredBin: bin, useCloudflared: true),
      tunnelId,
    );
    await saveGlobalConfig(updated);
    await _restartServicesStrict();
  }

  Future<void> _restartServicesStrict() async {
    try {
      await _stopTunnel();
      await mcpServer.stop();
      _serverRunning = false;
      _lastError = null;
      await _startServer();
      if (_config.tunnelEnabled) await _startTunnel();
    } catch (error) {
      _lastError = '$error';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _restartTunnelStrict() async {
    if (!_config.tunnelEnabled) throw Exception('Tunnel 未启用');
    try {
      await _stopTunnel();
      _lastError = null;
      await _startTunnel();
    } catch (error) {
      _lastError = '$error';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> runDoctor() {
    final current = _doctorTask;
    if (current != null) return current;
    if (_shuttingDown) return Future<void>.value();
    final task = _runDoctor().whenComplete(() => _doctorTask = null);
    _doctorTask = task;
    return task;
  }

  void _refreshDoctorIfAvailable() {
    if (_shuttingDown || _doctorCheckedAt == null) return;
    unawaited(runDoctor());
  }

  Future<void> _runDoctor() async {
    _doctorRunning = true;
    _doctorRunningTitles.clear();
    _doctorChecks = [];
    _doctorCheckedAt = null;
    notifyListeners();

    try {
      if (_shuttingDown) return;
      _doctorChecks = await doctorService.runAll(
        config: _config,
        workspaces: _workspaces,
        serverRunning: _serverRunning,
        tunnelRunning: tunnelRunning,
        tunnelError:
            _lastError ??
            (_config.useOpenAiTunnel ? openAiTunnelService.logTail : tunnelService.logTail),
        onCheckStart: (title) {
          if (_shuttingDown) return;
          _doctorRunningTitles.add(title);
          notifyListeners();
        },
        onCheckComplete: (check) {
          if (_shuttingDown) return;
          _doctorRunningTitles.remove(check.title);
          _doctorChecks = [..._doctorChecks, check];
          notifyListeners();
        },
      );
      if (!_shuttingDown) _doctorCheckedAt = DateTime.now();
    } catch (error) {
      debugPrint('环境检查未完成: $error');
    } finally {
      _doctorRunning = false;
      _doctorRunningTitles.clear();
      if (!_shuttingDown) notifyListeners();
    }
  }

  Future<void> shutdown() {
    final current = _shutdownTask;
    if (current != null) return current;
    _shuttingDown = true;
    final task = _shutdown();
    _shutdownTask = task;
    return task;
  }

  Future<void> _shutdown() async {
    await Future.wait([stopServices(), capabilities.shutdown()]);
    _serverRunning = false;
  }

  Future<void> _startServer() async {
    if (_serverRunning || _servicesStopping || _shuttingDown) return;

    final port = await AppPaths.findAvailablePort(_config.port);
    if (port != _config.port) {
      await saveGlobalConfig(_config.copyWith(port: port));
    }

    if (_servicesStopping || _shuttingDown) return;
    await mcpServer.start(host: _config.host, port: port);
    if (_servicesStopping || _shuttingDown) {
      await mcpServer.stop();
      return;
    }
    _serverRunning = true;
    for (final workspace in _workspaces) {
      _registerHandler(workspace);
    }
    notifyListeners();
  }

  Future<void> _startTunnel({int readyTimeoutSec = 45}) async {
    if (_tunnelRunning || _servicesStopping || _shuttingDown) return;

    if (_config.useOpenAiTunnel) {
      if (!_workspaces.any((workspace) => workspace.enabled)) return;
      final bin = await setupService.findTunnelClientBin(configuredPath: _config.tunnelClientBin);
      if (bin == null) throw Exception('未找到 tunnel-client');
      final runtimeApiKey = _config.openAiRuntimeApiKey.trim();
      if (runtimeApiKey.isEmpty) throw Exception('尚未配置 OpenAI Runtime API Key');
      await openAiTunnelService.startAll(
        bin: bin,
        runtimeApiKey: runtimeApiKey,
        localServiceUrl: _config.localServiceUrl,
        workspaces: _workspaces,
        readyTimeoutSec: readyTimeoutSec.clamp(5, 45),
      );
      if (_servicesStopping || _shuttingDown) {
        await openAiTunnelService.stopAll();
        return;
      }
      _tunnelRunning = true;
      return;
    }

    final bin = await _resolveCloudflaredBin();
    final tunnelId = _config.tunnelId;
    if (tunnelId == null || tunnelId.isEmpty) {
      throw Exception('尚未创建 Cloudflare Tunnel');
    }
    await _writeTunnelConfig(tunnelId);
    if (_servicesStopping || _shuttingDown) return;
    await tunnelService.start(
      bin: bin,
      tunnelId: tunnelId,
      configPath: await AppPaths.cloudflaredConfigPath,
      hostname: _config.domain,
      readyTimeoutSec: readyTimeoutSec,
    );
    if (_servicesStopping || _shuttingDown) {
      await tunnelService.stop();
      return;
    }
    _tunnelRunning = true;
  }

  Future<void> _stopTunnel() async {
    _tunnelStopInProgress = true;
    try {
      await Future.wait([tunnelService.stop(), openAiTunnelService.stopAll()]);
      _tunnelRunning = false;
    } finally {
      _tunnelStopInProgress = false;
    }
  }

  /// 每次启动都按当前端口重写 yml，避免端口变化后隧道指向旧端口
  Future<void> _writeTunnelConfig(String tunnelId) async {
    final credentialsFile = await AppPaths.credentialsPath(tunnelId);
    final configPath = await AppPaths.cloudflaredConfigPath;

    await File(configPath).writeAsString(
      TunnelConfigYml.build(
        tunnelId: tunnelId,
        credentialsFile: credentialsFile,
        hostname: _config.domain,
        serviceUrl: _config.localServiceUrl,
      ),
    );

    if (!await setupService.ensureTunnelCredentials(tunnelId)) {
      throw Exception('缺少 Tunnel credentials：$credentialsFile');
    }
  }

  void _registerHandler(Workspace workspace) {
    if (!_serverRunning) return;
    if (!workspace.enabled) {
      mcpServer.removeWorkspace(workspace.uuid);
      return;
    }
    final handler = mcpServer.addWorkspace(
      workspace: workspace,
      logStore: logStore,
      capabilities: capabilities,
      onSummary: _handleSummary,
    );
    handler.processManager.addListener(notifyListeners);
  }

  @override
  void dispose() {
    capabilities.removeListener(notifyListeners);
    logStore.removeListener(notifyListeners);
    openAiTunnelService.removeListener(_handleOpenAiTunnelStateChanged);
    logStore.dispose();
    super.dispose();
  }
}
