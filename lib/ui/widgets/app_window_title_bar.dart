import 'dart:async';
import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';
import '../../app_info.dart';
import '../../stores/app_state.dart';
import '../../utils/app_paths.dart';
import '../theme/app_theme.dart';
import 'app_about_dialog.dart';
import 'app_spacing.dart';
import 'app_toast.dart';
import 'app_update_dialog.dart';

/// 自绘窗口框：隐藏系统标题栏后，在内容上方放一条跟主题走的拖拽栏。
class AppWindowFrame extends StatelessWidget {
  final AppState appState;
  final Widget child;

  const AppWindowFrame({
    super.key,
    required this.appState,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        children: [
          AppWindowTitleBar(appState: appState),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 可拖拽、双击最大化的标题栏，右侧为最小化 / 最大化 / 关闭。
class AppWindowTitleBar extends StatefulWidget {
  final AppState appState;

  const AppWindowTitleBar({super.key, required this.appState});

  @override
  State<AppWindowTitleBar> createState() => _AppWindowTitleBarState();
}

class _AppWindowTitleBarState extends State<AppWindowTitleBar>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _maximized = false);
  }

  @override
  void onWindowRestore() {
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    });
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: AppSpacing.windowTitleBarHeight,
      decoration: BoxDecoration(
        color: AppTones.surfaceSunken(theme),
        border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMaximize,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _WindowMenuBar(appState: widget.appState),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CaptionButton(
                  kind: _CaptionKind.minimize,
                  onPressed: windowManager.minimize,
                ),
                _CaptionButton(
                  kind: _maximized
                      ? _CaptionKind.restore
                      : _CaptionKind.maximize,
                  onPressed: _toggleMaximize,
                ),
                _CaptionButton(
                  kind: _CaptionKind.close,
                  danger: true,
                  onPressed: windowManager.close,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowMenuBar extends StatelessWidget {
  final AppState appState;

  const _WindowMenuBar({required this.appState});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowMenuButton(
            label: '文件',
            items: (anchorContext) => [
              MenuButton(
                child: const Text('打开配置目录'),
                onPressed: (_) =>
                    unawaited(_openConfigDirectory(anchorContext)),
              ),
              const MenuDivider(),
              MenuButton(
                child: const Text('关闭窗口'),
                onPressed: (_) => unawaited(windowManager.close()),
              ),
            ],
          ),
          _WindowMenuButton(
            label: '视图',
            items: (_) => [
              MenuCheckbox(
                value: appState.darkMode,
                child: const Text('深色模式'),
                onChanged: (_, value) =>
                    unawaited(appState.setThemeMode(value)),
              ),
            ],
          ),
          _WindowMenuButton(
            label: '帮助',
            items: (anchorContext) => [
              MenuButton(
                child: const Text('检查更新'),
                onPressed: (_) {
                  Future<void>.microtask(() {
                    if (!anchorContext.mounted) return;
                    AppUpdateDialog.checkAndShow(anchorContext, appState);
                  });
                },
              ),
              const MenuDivider(),
              MenuButton(
                child: Text('关于 $appName'),
                onPressed: (_) {
                  Future<void>.microtask(() {
                    if (anchorContext.mounted) {
                      AppAboutDialog.show(anchorContext, appState);
                    }
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _openConfigDirectory(BuildContext context) async {
    final path = await AppPaths.configDir;
    try {
      final result = Platform.isWindows
          ? await Process.run('explorer.exe', [path])
          : Platform.isMacOS
          ? await Process.run('open', [path])
          : await Process.run('xdg-open', [path]);
      if (result.exitCode != 0 && context.mounted) {
        AppToast.error(context, '打开配置目录失败');
      }
    } catch (_) {
      if (context.mounted) AppToast.error(context, '打开配置目录失败');
    }
  }
}

typedef _MenuItemsBuilder = List<MenuItem> Function(BuildContext context);

class _WindowMenuButton extends StatefulWidget {
  final String label;
  final _MenuItemsBuilder items;

  const _WindowMenuButton({required this.label, required this.items});

  @override
  State<_WindowMenuButton> createState() => _WindowMenuButtonState();
}

class _WindowMenuButtonState extends State<_WindowMenuButton> {
  bool _hovered = false;
  bool _menuOpen = false;

  Future<void> _showMenu() async {
    if (_menuOpen) return;
    setState(() => _menuOpen = true);
    final result = showDropdown<void>(
      context: context,
      alignment: Alignment.topLeft,
      anchorAlignment: Alignment.bottomLeft,
      offset: const Offset(0, 2),
      builder: (_) => SizedBox(
        width: 192,
        child: DropdownMenu(
          surfaceOpacity: 0.98,
          surfaceBlur: 12,
          children: widget.items(context),
        ),
      ),
    );
    try {
      await result.future;
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlighted = _hovered || _menuOpen;
    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showMenu,
        child: SizedBox(
          height: AppSpacing.windowTitleBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: highlighted
                    ? theme.colorScheme.foreground.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.label,
                style: theme.typography.sans.copyWith(
                  fontSize: 12,
                  height: 1.2,
                  color: highlighted
                      ? theme.colorScheme.foreground
                      : theme.colorScheme.mutedForeground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _CaptionKind { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  final _CaptionKind kind;
  final VoidCallback onPressed;
  final bool danger;

  const _CaptionButton({
    required this.kind,
    required this.onPressed,
    this.danger = false,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final Color background;
    final Color foreground;
    if (widget.danger && _hovered) {
      background = const Color(0xFFE81123);
      foreground = Colors.white;
    } else if (_hovered) {
      background = theme.colorScheme.foreground.withValues(alpha: 0.08);
      foreground = theme.colorScheme.foreground;
    } else {
      background = Colors.transparent;
      foreground = theme.colorScheme.mutedForeground;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: AppSpacing.windowTitleBarHeight,
          color: background,
          alignment: Alignment.center,
          child: CustomPaint(
            size: const Size(10, 10),
            painter: _CaptionIconPainter(
              kind: widget.kind,
              color: foreground,
              devicePixelRatio: devicePixelRatio,
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionIconPainter extends CustomPainter {
  final _CaptionKind kind;
  final Color color;
  final double devicePixelRatio;

  _CaptionIconPainter({
    required this.kind,
    required this.color,
    required this.devicePixelRatio,
  });

  double _snap(double value) {
    final physical = value * devicePixelRatio;
    return (physical.floorToDouble() + 0.5) / devicePixelRatio;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / devicePixelRatio
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;

    final left = _snap(0.5);
    final top = _snap(0.5);
    final right = _snap(size.width - 0.5);
    final bottom = _snap(size.height - 0.5);
    final middleY = _snap(size.height / 2);

    switch (kind) {
      case _CaptionKind.minimize:
        canvas.drawLine(Offset(left, middleY), Offset(right, middleY), paint);
      case _CaptionKind.maximize:
        canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
      case _CaptionKind.restore:
        final offset = 2 / devicePixelRatio;
        canvas.drawRect(
          Rect.fromLTRB(left + offset, top, right, bottom - offset),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTRB(left, top + offset, right - offset, bottom),
          paint,
        );
      case _CaptionKind.close:
        canvas.drawLine(Offset(left, top), Offset(right, bottom), paint);
        canvas.drawLine(Offset(right, top), Offset(left, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CaptionIconPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.color != color ||
        oldDelegate.devicePixelRatio != devicePixelRatio;
  }
}
