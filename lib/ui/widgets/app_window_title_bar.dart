import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';
import '../../app_info.dart';
import '../theme/app_theme.dart';
import 'app_spacing.dart';

/// 自绘窗口框：隐藏系统标题栏后，在内容上方放一条跟主题走的拖拽栏。
class AppWindowFrame extends StatelessWidget {
  final Widget child;

  const AppWindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        children: [
          const AppWindowTitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 可拖拽、双击最大化的标题栏，右侧为最小化 / 最大化 / 关闭。
class AppWindowTitleBar extends StatefulWidget {
  const AppWindowTitleBar({super.key});

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
          Center(
            child: IgnorePointer(
              child: Text(
                appName,
                style: AppTones.muted(theme, size: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
                  kind: _maximized ? _CaptionKind.restore : _CaptionKind.maximize,
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
    final Color background;
    final Color foreground;
    if (widget.danger && _hovered) {
      background = const Color(0xFFE81123);
      foreground = Colors.white;
    } else if (_hovered) {
      background = theme.colorScheme.muted;
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
            painter: _CaptionIconPainter(kind: widget.kind, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _CaptionIconPainter extends CustomPainter {
  final _CaptionKind kind;
  final Color color;

  _CaptionIconPainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = true;

    switch (kind) {
      case _CaptionKind.minimize:
        canvas.drawLine(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          paint,
        );
      case _CaptionKind.maximize:
        canvas.drawRect(
          Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
          paint,
        );
      case _CaptionKind.restore:
        canvas.drawRect(const Rect.fromLTWH(2.5, 0.5, 7, 7), paint);
        canvas.drawRect(const Rect.fromLTWH(0.5, 2.5, 7, 7), paint);
      case _CaptionKind.close:
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CaptionIconPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}
