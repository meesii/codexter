import 'dart:async';
import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'app_info.dart';
import 'platform/desktop_platform.dart';
import 'platform/desktop_window.dart';
import 'services/tray_service.dart';
import 'stores/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/pages/first_run_page.dart';
import 'ui/pages/startup_check_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/close_window_dialog.dart';
import 'utils/win_kill_job.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WinKillOnCloseJob.bindCurrentProcess();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(desktopWindowOptionsFor(desktopPlatform), () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(true);

  final appState = AppState();
  await appState.init();

  runApp(CodexterApp(appState: appState));
}

class CodexterApp extends StatefulWidget {
  final AppState appState;

  const CodexterApp({super.key, required this.appState});

  @override
  State<CodexterApp> createState() => _CodexterAppState();
}

/// 关窗前先停掉 cloudflared 与子进程，避免留下孤儿进程
class _CodexterAppState extends State<CodexterApp> with WindowListener, WidgetsBindingObserver {
  late final TrayService _trayService;
  late final VoidCallback _detachPlatformLifecycle;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _exiting = false;
  bool _closePromptOpen = false;
  bool _startupGateCompleted = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    widget.appState.syncSystemTheme();
    _trayService = TrayService(onExitRequested: _exitApp);
    unawaited(_trayService.initialize());
    _detachPlatformLifecycle = desktopPlatform.attachLifecycle(shutdown: widget.appState.shutdown);
  }

  @override
  void dispose() {
    _detachPlatformLifecycle();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    unawaited(_trayService.dispose());
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    widget.appState.syncSystemTheme();
  }

  @override
  Future<void> onWindowClose() async {
    if (_exiting || _closePromptOpen) return;

    if (await desktopPlatform.handleWindowClose()) return;

    // 当前关闭选择弹窗和“记住选择”仅用于 Windows。
    if (!Platform.isWindows) {
      await _exitApp();
      return;
    }

    final config = widget.appState.config;
    if (config.closeActionRemembered) {
      if (config.closeToTray) {
        await _hideToTray();
      } else {
        await _exitApp();
      }
      return;
    }

    if (!mounted) return;
    _closePromptOpen = true;
    try {
      final navigatorContext =
          _navigatorKey.currentState?.overlay?.context ?? _navigatorKey.currentContext;
      if (navigatorContext == null || !navigatorContext.mounted) return;
      final decision = await CloseWindowDialog.show(navigatorContext);
      if (decision == null) return;
      if (decision.remember) {
        await widget.appState.rememberCloseAction(minimizeToTray: decision.minimizeToTray);
      }
      if (decision.minimizeToTray) {
        await _hideToTray();
      } else {
        await _exitApp();
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  Future<void> _hideToTray() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> _exitApp() async {
    if (_exiting) return;
    if (await desktopPlatform.requestExit()) return;
    _exiting = true;
    try {
      await Future.wait([
        _runExitCleanup('托盘', _trayService.dispose),
        _runExitCleanup('应用服务', widget.appState.shutdown),
      ]);
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } finally {
      _exiting = false;
    }
  }

  Future<void> _runExitCleanup(String label, Future<void> Function() cleanup) async {
    try {
      await cleanup();
    } catch (error, stackTrace) {
      debugPrint('$label清理失败，继续退出：$error\n$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, child) {
        return ShadcnApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: appName,
          theme: widget.appState.darkMode ? AppTheme.dark : AppTheme.light,
          home: AppSwitchTheme(
            child: DesktopWindowFrame(
              appState: widget.appState,
              child: ToastLayer(
                child: widget.appState.isFirstRun
                    ? FirstRunPage(
                        appState: widget.appState,
                        onCompleted: () {
                          if (mounted) {
                            setState(() => _startupGateCompleted = true);
                          }
                        },
                      )
                    : !_startupGateCompleted
                    ? StartupCheckPage(
                        appState: widget.appState,
                        onContinue: () {
                          if (mounted) {
                            setState(() => _startupGateCompleted = true);
                          }
                        },
                      )
                    : AppShell(appState: widget.appState),
              ),
            ),
          ),
        );
      },
    );
  }
}
