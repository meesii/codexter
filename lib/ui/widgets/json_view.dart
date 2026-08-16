import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../utils/fmt.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_spacing.dart';
import 'app_toast.dart';

/// 带极简语法高亮的 JSON 展示块
class JsonView extends StatelessWidget {
  final String label;
  final Object? data;
  final double maxHeight;
  final bool scrollable;
  final int? previewLines;
  final bool showCopy;
  final VoidCallback? onOpen;

  const JsonView({
    super.key,
    required this.label,
    required this.data,
    this.maxHeight = 320,
    this.scrollable = true,
    this.previewLines,
    this.showCopy = false,
    this.onOpen,
  });

  static final _tokenRegex = RegExp(
    r'("(?:[^"\\]|\\.)*"\s*:)|("(?:[^"\\]|\\.)*")|(\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|(\btrue\b|\bfalse\b|\bnull\b)',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = Fmt.json(data);
    final preview = _preview(source);
    final truncated = preview.length < source.length;
    final text = SelectableText.rich(
      _highlight(theme, preview),
      style: AppTones.mono(theme, size: 11),
      contextMenuBuilder: buildAppTextContextMenu,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.typography.sans.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.foreground,
              ),
            ),
            const Spacer(),
            if (truncated && onOpen != null) ...[
              AppIconButton(
                icon: BootstrapIcons.chevronRight,
                tooltip: '查看完整$label',
                onPressed: onOpen,
              ),
              const Gap(AppSpacing.sm),
            ],
            if (showCopy)
              AppIconButton(
                icon: BootstrapIcons.clipboard,
                tooltip: '复制$label',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: source));
                  AppToast.success(context, '已复制$label');
                },
              ),
          ],
        ),
        const Gap(AppSpacing.xs),
        Container(
          width: double.infinity,
          constraints: scrollable ? BoxConstraints(maxHeight: maxHeight) : null,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppTones.surfaceSunken(theme),
            borderRadius: BorderRadius.circular(theme.radiusMd),
            border: Border.all(color: AppTones.borderSubtle(theme)),
          ),
          child: scrollable ? SingleChildScrollView(child: text) : text,
        ),
      ],
    );
  }

  String _preview(String source) {
    final limit = previewLines;
    if (limit == null || limit <= 0) return source;
    final lines = source.split('\n');
    if (lines.length <= limit) return source;
    return '${lines.take(limit).join('\n')}\n…';
  }

  TextSpan _highlight(ThemeData theme, String source) {
    final keyColor = AppTones.info;
    final stringColor = AppTones.success;
    final numberColor = AppTones.warning;
    final literalColor = theme.colorScheme.destructive;
    final baseColor = theme.colorScheme.foreground;

    final spans = <TextSpan>[];
    var cursor = 0;

    for (final match in _tokenRegex.allMatches(source)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: source.substring(cursor, match.start),
            style: TextStyle(color: baseColor.withValues(alpha: 0.75)),
          ),
        );
      }
      final color = match.group(1) != null
          ? keyColor
          : match.group(2) != null
          ? stringColor
          : match.group(3) != null
          ? numberColor
          : literalColor;
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(color: color),
        ),
      );
      cursor = match.end;
    }

    if (cursor < source.length) {
      spans.add(
        TextSpan(
          text: source.substring(cursor),
          style: TextStyle(color: baseColor.withValues(alpha: 0.75)),
        ),
      );
    }
    return TextSpan(children: spans);
  }
}

/// 终端风格的等宽输出块
class ConsoleView extends StatelessWidget {
  final String text;
  final double maxHeight;

  const ConsoleView({super.key, required this.text, this.maxHeight = 260});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0C),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(color: AppTones.borderSubtle(theme)),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: SelectableText(
          text.isEmpty ? '(暂无输出)' : text,
          style: AppTones.mono(theme, size: 11, color: const Color(0xFFD4D4D8)),
          contextMenuBuilder: buildAppTextContextMenu,
        ),
      ),
    );
  }
}

/// 分段切换控件（实时日志 / 运行终端）
class AppSegmented extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  const AppSegmented({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTones.surfaceSunken(theme),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (index) {
          final active = index == activeIndex;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? theme.colorScheme.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(theme.radiusSm),
                  border: Border.all(color: active ? theme.colorScheme.border : Colors.transparent),
                ),
                child: Text(
                  labels[index],
                  style: theme.typography.sans.copyWith(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active
                        ? theme.colorScheme.foreground
                        : theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 顶部筛选输入框
class AppFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final double width;

  const AppFilterField({
    super.key,
    required this.controller,
    this.placeholder = '筛选',
    this.width = 200,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppInputFocusTheme(
        child: TextField(
          controller: controller,
          placeholder: Text(placeholder),
          features: const [InputFeature.leading(Icon(BootstrapIcons.search, size: 12))],
        ),
      ),
    );
  }
}

/// 一行 key / value 的信息条
class AppInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const AppInfoRow({super.key, required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 108, child: Text(label, style: AppTones.muted(theme, size: 11))),
          Expanded(
            child: mono
                ? AppMonoText(value, size: 11, maxLines: 3)
                : Text(value, style: AppTones.body(theme, size: 12)),
          ),
        ],
      ),
    );
  }
}
