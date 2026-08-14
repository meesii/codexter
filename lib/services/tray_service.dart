import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';
import '../app_info.dart';

/// Windows / macOS 系统托盘。关闭到托盘时服务与 MCP 进程继续运行。
class TrayService with tray.TrayListener {
    final Future<void> Function() onExitRequested;
    bool _initialized = false;

    TrayService({required this.onExitRequested});

    Future<void> initialize() async {
        if (_initialized || (!Platform.isWindows && !Platform.isMacOS)) return;
        final iconPath = await _materializeIcon();
        await tray.trayManager.setIcon(
            iconPath,
            isTemplate: Platform.isMacOS,
            iconSize: 18,
        );
        await tray.trayManager.setToolTip(appName);
        await tray.trayManager.setContextMenu(
            tray.Menu(
                items: [
                    tray.MenuItem(key: 'show_window', label: '显示主窗口'),
                    tray.MenuItem.separator(),
                    tray.MenuItem(key: 'exit_app', label: '退出 $appName'),
                ],
            ),
        );
        tray.trayManager.addListener(this);
        _initialized = true;
    }

    Future<void> dispose() async {
        if (!_initialized) return;
        tray.trayManager.removeListener(this);
        await tray.trayManager.destroy();
        _initialized = false;
    }

    Future<void> showWindow() async {
        await windowManager.setSkipTaskbar(false);
        await windowManager.show();
        if (await windowManager.isMinimized()) await windowManager.restore();
        await windowManager.focus();
    }

    @override
    void onTrayIconMouseDown() {
        unawaited(showWindow());
    }

    @override
    void onTrayIconRightMouseDown() {
        unawaited(tray.trayManager.popUpContextMenu());
    }

    @override
    void onTrayMenuItemClick(tray.MenuItem menuItem) {
        switch (menuItem.key) {
            case 'show_window':
                unawaited(showWindow());
            case 'exit_app':
                unawaited(onExitRequested());
        }
    }

    Future<String> _materializeIcon() async {
        final asset = Platform.isWindows
            ? 'assets/brand/tray_icon.ico'
            : appLogoAsset;
        final filename = Platform.isWindows ? 'codexter-tray.ico' : 'codexter-tray.png';
        final data = await rootBundle.load(asset);
        final directory = await getTemporaryDirectory();
        final file = File(p.join(directory.path, filename));
        await file.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
        );
        return file.path;
    }
}
