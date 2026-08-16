import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';
import 'app_toast.dart';

/// 展示工作区 MCP 地址，并引导用户在 ChatGPT 中创建自定义 MCP 应用。
class McpConnectionDialog {
  const McpConnectionDialog._();

  static Future<void> show(BuildContext context, String url) {
    return AppDialog.show<void>(
      context: context,
      title: '连接到 ChatGPT',
      description: '复制 MCP URL，然后在 ChatGPT 中创建自定义 MCP 应用。',
      maxWidth: 520,
      content: _McpConnectionContent(url: url),
      actions: (dialogContext) => [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            AppToast.success(dialogContext, 'MCP URL 已复制');
          },
          child: const Text('复制 MCP URL'),
        ),
      ],
    );
  }
}

class _McpConnectionContent extends StatelessWidget {
  final String url;

  const _McpConnectionContent({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('MCP URL', style: AppTones.title(theme, size: 12)),
        const Gap(AppSpacing.sm),
        AppCopyField(value: url, selectable: true, maxLines: 1, compact: true),
        const Gap(AppSpacing.xl),
        Text('添加到 ChatGPT', style: AppTones.title(theme, size: 12)),
        const Gap(AppSpacing.md),
        const _ConnectStep(index: 1, text: '打开 ChatGPT → 设置 → 账号安全与登录 → 开启“开发者模式”'),
        const _ConnectStep(index: 2, text: '在“插件”页面点击“创建”，新建自定义插件'),
        const _ConnectStep(index: 3, text: '将上方 MCP URL 填入端点地址，并选择“无身份验证”模式', showLine: false),
      ],
    );
  }
}

class _ConnectStep extends StatelessWidget {
  final int index;
  final String text;
  final bool showLine;

  const _ConnectStep({required this.index, required this.text, this.showLine = true});

  TextSpan _buildStepTextSpan(ThemeData theme) {
    final baseStyle = AppTones.body(theme, size: 12).copyWith(height: 1.45);
    final boldStyle = baseStyle.copyWith(fontWeight: FontWeight.w600);
    final spans = <InlineSpan>[];
    final matches = RegExp(r'“([^”]+)”').allMatches(text);
    var offset = 0;

    for (final match in matches) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      spans.add(const TextSpan(text: '“'));
      spans.add(TextSpan(text: match.group(1), style: boldStyle));
      spans.add(const TextSpan(text: '”'));
      offset = match.end;
    }

    if (offset < text.length) {
      spans.add(TextSpan(text: text.substring(offset)));
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTones.surfaceSunken(theme),
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.border),
                  ),
                  child: Text(
                    '$index',
                    style: theme.typography.sans.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: theme.colorScheme.border,
                    ),
                  ),
              ],
            ),
          ),
          const Gap(AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showLine ? AppSpacing.md : 0),
              child: Text.rich(_buildStepTextSpan(theme)),
            ),
          ),
        ],
      ),
    );
  }
}
