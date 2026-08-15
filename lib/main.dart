import 'dart:async';
import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'app_info.dart';
import 'services/tray_service.dart';
import 'stores/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/pages/first_run_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/app_window_title_bar.dart';
import 'ui/widgets/close_window_dialog.dart';
import 'utils/win_kill_job.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WinKillOnCloseJob.bindCurrentProcess();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1120, 720),
      minimumSize: Size(960, 640),
      title: appName,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      backgroundColor: Color(0x00000000),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
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
class _CodexterAppState extends State<CodexterApp>
    with WindowListener, WidgetsBindingObserver {
  late final TrayService _trayService;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _exiting = false;
  bool _closePromptOpen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    widget.appState.syncSystemTheme();
    _trayService = TrayService(onExitRequested: _exitApp);
    unawaited(_trayService.initialize());
  }

  @override
  void dispose() {
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

    // macOS 的红色关闭按钮只关闭/隐藏当前主窗口，应用继续运行；
    // 真正退出由 ⌘Q 或菜单栏“退出 Codexter”完成。
    if (Platform.isMacOS) {
      await windowManager.hide();
      return;
    }

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
          _navigatorKey.currentState?.overlay?.context ??
          _navigatorKey.currentContext;
      if (navigatorContext == null) return;
      final decision = await CloseWindowDialog.show(navigatorContext);
      if (decision == null) return;
      if (decision.remember) {
        await widget.appState.rememberCloseAction(
          minimizeToTray: decision.minimizeToTray,
        );
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
    _exiting = true;
    await _trayService.dispose();
    await widget.appState.shutdown();
    await windowManager.setPreventClose(false);
    await windowManager.close();
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
            child: AppWindowFrame(
              appState: widget.appState,
              child: ToastLayer(
                child: widget.appState.isFirstRun
                    ? FirstRunPage(appState: widget.appState)
                    : AppShell(appState: widget.appState),
              ),
            ),
          ),
        );
      },
    );
  }
}
