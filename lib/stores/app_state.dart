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
import '../services/capability_runtime.dart';
import '../services/doctor_service.dart';
import '../services/notification_service.dart';
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
  final MultiWorkspaceServer mcpServer = MultiWorkspaceServer();
  final TunnelService tunnelService = TunnelService();
  final CapabilityRuntime capabilities = CapabilityRuntime();
  final DoctorService doctorService = DoctorService();
  final NotificationService notificationService = NotificationService();
  final SetupService setupService = SetupService();
  final AppUpdateService updateService = AppUpdateService();

  GlobalConfig _config = GlobalConfig();
  List<Workspace> _workspaces = [];
  List<SkillEntry> _skills = [];
  List<DownstreamMcpEntry> _mcps = [];
  List<DoctorCheck> _doctorChecks = [];
  bool _doctorRunning = false;
  String? _doctorRunningTitle;

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
  bool _systemDark =
      PlatformDispatcher.instance.platformBrightness == Brightness.dark;

  GlobalConfig get config => _config;
  List<Workspace> get workspaces => _workspaces;
  List<SkillEntry> get skills => _skills;
  List<DownstreamMcpEntry> get mcps => _mcps;
  List<DoctorCheck> get doctorChecks => _doctorChecks;
  bool get doctorRunning => _doctorRunning;
  String? get doctorRunningTitle => _doctorRunningTitle;
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
    return _workspaces.firstWhereOrNull(
      (item) => item.uuid == _selectedWorkspaceUuid,
    );
  }

  Future<void> init() async {
    if (_initialized) return;

    Hive.init(await AppPaths.configDir);
    Hive.registerAdapter(GlobalConfigAdapter());
    Hive.registerAdapter(WorkspaceAdapter());
    Hive.registerAdapter(SkillEntryAdapter());
    Hive.registerAdapter(DownstreamMcpEntryAdapter());
    await ConfigStore.init();

    _config = ConfigStore.getGlobalConfig();
    await setupService.migrateLegacyCloudflareCredentials(_config.tunnelId);
    mcpServer.setWidgetDomain(_config.widgetOrigin);
    _workspaces = ConfigStore.getWorkspaces();
    _skills = ConfigStore.getSkills();
    _mcps = ConfigStore.getMcps();

    capabilities.syncSkills(_skills);
    capabilities.addListener(notifyListeners);
    logStore.addListener(notifyListeners);
    await notificationService.initialize();
    if (_config.notificationsEnabled) {
      unawaited(
        notificationService.requestPermissions(
          sound: _config.notificationSound,
        ),
      );
    }

    _initialized = true;
    notifyListeners();

    unawaited(capabilities.syncMcps(_mcps));
    if (Platform.isWindows) {
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
      unawaited(
        notificationService.showSummary(
          notice,
          sound: _config.notificationSound,
        ),
      );
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
      _config.copyWith(
        closeToTray: minimizeToTray,
        closeActionRemembered: true,
      ),
    );
  }

  Future<void> resetCloseActionPreference() async {
    await saveGlobalConfig(_config.copyWith(closeActionRemembered: false));
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    await saveGlobalConfig(_config.copyWith(notificationsEnabled: enabled));
    if (enabled) {
      await notificationService.requestPermissions(
        sound: _config.notificationSound,
      );
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
    await saveGlobalConfig(
      _config.copyWith(sidebarWidth: width.clamp(200, 340)),
    );
  }

  void syncSystemTheme() {
    final systemDark =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    if (systemDark == _systemDark) return;
    _systemDark = systemDark;
    if (_config.darkMode == null) notifyListeners();
  }

  Future<void> saveGlobalConfig(GlobalConfig config) async {
    _config = config;
    mcpServer.setWidgetDomain(_config.widgetOrigin);
    await ConfigStore.saveGlobalConfig(config);
    notifyListeners();
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
    );
    _workspaces = [..._workspaces, workspace];
    await ConfigStore.saveWorkspace(workspace);
    _registerHandler(workspace);
    notifyListeners();
    return workspace;
  }

  Future<void> updateWorkspace(Workspace workspace) async {
    _workspaces = _workspaces
        .map((item) => item.uuid == workspace.uuid ? workspace : item)
        .toList();
    await ConfigStore.saveWorkspace(workspace);
    _registerHandler(workspace);
    notifyListeners();
  }

  Future<void> deleteWorkspace(String uuid) async {
    _workspaces = _workspaces.where((item) => item.uuid != uuid).toList();
    await ConfigStore.deleteWorkspace(uuid);
    mcpServer.removeWorkspace(uuid);
    logStore.clear(uuid);
    if (_selectedWorkspaceUuid == uuid) _selectedWorkspaceUuid = null;
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

  List<McpLogEntry> recentLogs(String uuid, int count) =>
      logStore.recentOf(uuid, count);

  void clearWorkspaceLogs(String uuid) => logStore.clearEntries(uuid);

  String? latestToolPurpose(String uuid) => logStore.latestToolPurposeOf(uuid);

  McpLogEntry? latestTool(String uuid) => logStore.latestToolOf(uuid);

  McpLogEntry? activeTool(String uuid) => logStore.activeToolOf(uuid);

  WorkspaceLogStats workspaceStats(String uuid) => logStore.statsOf(uuid);

  String workspaceUrl(String uuid) => _config.workspaceUrl(uuid);

  Future<void> saveSkill(SkillEntry skill) async {
    final index = _skills.indexWhere((item) => item.name == skill.name);
    if (index >= 0) {
      _skills = List.of(_skills)..[index] = skill;
    } else {
      _skills = [..._skills, skill];
    }
    _skills.sort((left, right) => left.name.compareTo(right.name));
    await ConfigStore.saveSkill(skill);
    capabilities.syncSkills(_skills);
    notifyListeners();
  }

  Future<void> deleteSkill(String name) async {
    _skills = _skills.where((item) => item.name != name).toList();
    await ConfigStore.deleteSkill(name);
    capabilities.syncSkills(_skills);
    notifyListeners();
  }

  Future<void> toggleSkill(String name, bool enabled) async {
    final skill = _skills.firstWhereOrNull((item) => item.name == name);
    if (skill == null) return;
    await saveSkill(skill.copyWith(enabled: enabled));
  }

  Future<void> saveMcp(DownstreamMcpEntry mcp) async {
    final index = _mcps.indexWhere((item) => item.name == mcp.name);
    if (index >= 0) {
      _mcps = List.of(_mcps)..[index] = mcp;
    } else {
      _mcps = [..._mcps, mcp];
    }
    _mcps.sort((left, right) => left.name.compareTo(right.name));
    await ConfigStore.saveMcp(mcp);
    notifyListeners();
    await capabilities.syncMcps(_mcps);
  }

  Future<void> deleteMcp(String name) async {
    _mcps = _mcps.where((item) => item.name != name).toList();
    await ConfigStore.deleteMcp(name);
    notifyListeners();
    await capabilities.syncMcps(_mcps);
  }

  Future<void> toggleMcp(String name, bool enabled) async {
    final mcp = _mcps.firstWhereOrNull((item) => item.name == name);
    if (mcp == null) return;
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

  /// 启动本地 HttpServer 并按需拉起长驻 Tunnel
  Future<void> startServices() async {
    if (_busy) return;
    _busy = true;
    _lastError = null;
    notifyListeners();

    try {
      await _startServer();
      if (_config.useCloudflared) await _startTunnel();
    } catch (error) {
      _lastError = '$error';
      debugPrint('启动服务失败: $error');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> restartServices() async {
    await stopServices();
    await startServices();
  }

  Future<void> restartTunnel() async {
    if (_busy || !_config.useCloudflared) return;
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
    }
  }

  Future<void> stopServices() async {
    await _stopTunnel();
    await mcpServer.stop();
    _serverRunning = false;
    notifyListeners();
  }

  /// 启动页使用：先尝试启动服务，再逐项执行关键环境检测。
  Future<List<DoctorCheck>> runStartupChecks({
    void Function(String status)? onStatus,
    void Function(String title)? onCheckStart,
    void Function(DoctorCheck check)? onCheckComplete,
  }) async {
    onStatus?.call('正在启动本地服务…');
    await startServices();
    onStatus?.call('正在检查运行环境…');
    return doctorService.runStartup(
      config: _config,
      workspaces: _workspaces,
      serverRunning: _serverRunning,
      tunnelRunning: _tunnelRunning,
      tunnelError: _lastError ?? tunnelService.logTail,
      onCheckStart: onCheckStart,
      onCheckComplete: onCheckComplete,
    );
  }

  /// 环境检测页与启动检测页共用同一套修复逻辑。
  Future<void> repairDoctorCheck(DoctorCheck check) async {
    switch (check.issue) {
      case TunnelIssueCode.cloudflaredMissing:
        await setupService.downloadCloudflared();
        await saveGlobalConfig(
          _config.copyWith(cloudflaredBin: await AppPaths.cloudflaredPath),
        );
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
    final configured = _config.cloudflaredBin;
    if (configured != null &&
        configured.isNotEmpty &&
        await File(configured).exists()) {
      return configured;
    }
    final found = await setupService.findCloudflaredBin();
    if (found == null || found.isEmpty) throw Exception('未找到 cloudflared');
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
      if (_config.useCloudflared) await _startTunnel();
    } catch (error) {
      _lastError = '$error';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _restartTunnelStrict() async {
    if (!_config.useCloudflared) throw Exception('Cloudflare Tunnel 未启用');
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

  Future<void> runDoctor() async {
    if (_doctorRunning) return;
    _doctorRunning = true;
    _doctorRunningTitle = null;
    notifyListeners();

    try {
      _doctorChecks = await doctorService.runAll(
        config: _config,
        workspaces: _workspaces,
        serverRunning: _serverRunning,
        tunnelRunning: _tunnelRunning,
        tunnelError: _lastError ?? tunnelService.logTail,
        onCheckStart: (title) {
          _doctorRunningTitle = title;
          notifyListeners();
        },
        onCheckComplete: (check) {
          final index = _doctorChecks.indexWhere(
            (item) => item.title == check.title,
          );
          if (index >= 0) {
            _doctorChecks = List.of(_doctorChecks)..[index] = check;
          } else {
            _doctorChecks = [..._doctorChecks, check];
          }
          notifyListeners();
        },
      );
    } finally {
      _doctorRunning = false;
      _doctorRunningTitle = null;
      notifyListeners();
    }
  }

  Future<void> shutdown() async {
    await _stopTunnel();
    await mcpServer.stop();
    await capabilities.shutdown();
    _serverRunning = false;
  }

  Future<void> _startServer() async {
    if (_serverRunning) return;

    final port = await AppPaths.findAvailablePort(_config.port);
    if (port != _config.port) {
      await saveGlobalConfig(_config.copyWith(port: port));
    }

    await mcpServer.start(host: _config.host, port: port);
    _serverRunning = true;
    for (final workspace in _workspaces) {
      _registerHandler(workspace);
    }
  }

  Future<void> _startTunnel() async {
    if (_tunnelRunning) return;
    final bin = _config.cloudflaredBin ?? await AppPaths.cloudflaredPath;
    final tunnelId = _config.tunnelId;
    if (tunnelId == null || tunnelId.isEmpty) {
      throw Exception('尚未创建 Cloudflare Tunnel');
    }
    if (!await File(bin).exists()) {
      throw Exception('Cloudflared 不存在：$bin');
    }

    await _writeTunnelConfig(tunnelId);
    await tunnelService.start(
      bin: bin,
      tunnelId: tunnelId,
      configPath: await AppPaths.cloudflaredConfigPath,
      hostname: _config.domain,
    );
    _tunnelRunning = true;
  }

  Future<void> _stopTunnel() async {
    if (!_tunnelRunning) return;
    await tunnelService.stop();
    _tunnelRunning = false;
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
    logStore.dispose();
    super.dispose();
  }
}
