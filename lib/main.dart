import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'app_info.dart';
import 'stores/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/pages/first_run_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/app_window_title_bar.dart';
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
    @override
    void initState() {
        super.initState();
        windowManager.addListener(this);
        WidgetsBinding.instance.addObserver(this);
        widget.appState.syncSystemTheme();
    }

    @override
    void dispose() {
        WidgetsBinding.instance.removeObserver(this);
        windowManager.removeListener(this);
        super.dispose();
    }

    @override
    void didChangePlatformBrightness() {
        widget.appState.syncSystemTheme();
    }

    @override
    Future<void> onWindowClose() async {
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
                    debugShowCheckedModeBanner: false,
                    title: appName,
                    theme: widget.appState.darkMode ? AppTheme.dark : AppTheme.light,
                    home: AppSwitchTheme(
                        child: AppWindowFrame(
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
