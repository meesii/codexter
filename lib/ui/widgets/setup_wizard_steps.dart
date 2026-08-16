import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_spacing.dart';

/// 向导步骤指示器
class StepIndicator extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;

  const StepIndicator({super.key, required this.labels, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    for (var index = 0; index < labels.length; index++) {
      final done = index < activeIndex;
      final active = index == activeIndex;
      final circleColor = done || active
          ? theme.colorScheme.primary
          : AppTones.surfaceSunken(theme);

      children.add(
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: done || active ? theme.colorScheme.primary : theme.colorScheme.border,
                ),
              ),
              child: Center(
                child: done
                    ? Icon(
                        BootstrapIcons.check,
                        size: 11,
                        color: theme.colorScheme.primaryForeground,
                      )
                    : Text(
                        '${index + 1}',
                        style: theme.typography.sans.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: active
                              ? theme.colorScheme.primaryForeground
                              : theme.colorScheme.mutedForeground,
                        ),
                      ),
              ),
            ),
            const Gap(AppSpacing.sm),
            Text(
              labels[index],
              style: theme.typography.sans.copyWith(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? theme.colorScheme.foreground : theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );

      if (index < labels.length - 1) {
        children.add(
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              color: done ? theme.colorScheme.primary : theme.colorScheme.border,
            ),
          ),
        );
      }
    }

    return Row(children: children);
  }
}

class CloudflaredStep extends StatelessWidget {
  final bool probed;
  final String? binPath;
  final String? version;
  final bool busy;
  final double downloadFraction;
  final String installPath;
  final String releaseAssetName;
  final String managedBinName;
  final VoidCallback onDownload;
  final VoidCallback onRecheck;
  final VoidCallback onOpenRelease;

  const CloudflaredStep({
    super.key,
    required this.probed,
    required this.binPath,
    required this.version,
    required this.busy,
    required this.downloadFraction,
    required this.installPath,
    required this.releaseAssetName,
    required this.managedBinName,
    required this.onDownload,
    required this.onRecheck,
    required this.onOpenRelease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!probed) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(AppSpacing.x2l), child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('第 1 步：安装 cloudflared', style: AppTones.title(theme, size: 14)),
        const Gap(AppSpacing.md),
        if (binPath != null)
          AppNotice(
            tone: AppNoticeTone.success,
            message: 'Cloudflared 已就绪',
            detail: '${version ?? ''}\n$binPath',
          )
        else ...[
          AppNotice(
            tone: AppNoticeTone.warning,
            message: '未检测到 Cloudflared',
            detail: '从 GitHub Releases 下载 $releaseAssetName，重命名为 $managedBinName 后放到下面的位置。',
          ),
          const Gap(AppSpacing.lg),
          Text('放置位置', style: AppTones.label(theme)),
          const Gap(AppSpacing.sm),
          AppCopyField(value: installPath, icon: BootstrapIcons.folder2),
          const Gap(AppSpacing.lg),
          if (downloadFraction > 0) ...[
            Progress(progress: downloadFraction),
            const Gap(AppSpacing.sm),
            AppMonoText('${(downloadFraction * 100).toStringAsFixed(0)}%'),
            const Gap(AppSpacing.md),
          ],
          Row(
            children: [
              Button(
                style: ButtonStyle.primary(size: ButtonSize.normal),
                onPressed: busy ? null : onDownload,
                child: const AppButtonLabel(icon: BootstrapIcons.download, label: '下载 cloudflared'),
              ),
              const Gap(AppSpacing.sm),
              Button(
                style: ButtonStyle.outline(size: ButtonSize.normal),
                onPressed: busy ? null : onRecheck,
                child: const Text('重新检测'),
              ),
              const Spacer(),
              AppLink(label: '手动下载 →', onPressed: onOpenRelease),
            ],
          ),
        ],
      ],
    );
  }
}

class DomainStep extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onOpenDashboard;

  const DomainStep({super.key, required this.controller, required this.onOpenDashboard});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('第 2 步：公网域名', style: AppTones.title(theme, size: 14)),
        const Gap(AppSpacing.md),
        AppField(
          label: '域名',
          controller: controller,
          placeholder: 'mcp.example.com',
          hint: '这个域名会被所有工作区共用，每个工作区通过 UUID 路径区分。',
        ),
        const Gap(AppSpacing.lg),
        AppLink(label: '没有域名？前往 Cloudflare 添加 →', onPressed: onOpenDashboard),
      ],
    );
  }
}

class TunnelStep extends StatelessWidget {
  final TextEditingController controller;

  const TunnelStep({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('第 3 步：创建 Tunnel', style: AppTones.title(theme, size: 14)),
        const Gap(AppSpacing.md),
        AppField(label: 'Tunnel 名称', controller: controller, placeholder: 'codex-mcp'),
        const Gap(AppSpacing.lg),
        const AppNotice(
          message: '点击「下一步」会依次完成：Cloudflare 登录、创建 Tunnel、配置 DNS、写入配置文件。',
          detail: '若浏览器未自动打开，请在弹出的终端提示中手动完成授权。',
        ),
      ],
    );
  }
}

class DoneStep extends StatelessWidget {
  final String domain;
  final VoidCallback onOpenDocs;

  const DoneStep({super.key, required this.domain, required this.onOpenDocs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('配置完成', style: AppTones.title(theme, size: 14)),
        const Gap(AppSpacing.md),
        const AppNotice(
          tone: AppNoticeTone.success,
          message: '公网入口已就绪',
          detail: '进入主页创建工作区，每个工作区会生成独立的连接地址。',
        ),
        const Gap(AppSpacing.lg),
        Text('连接地址模板', style: AppTones.label(theme)),
        const Gap(AppSpacing.sm),
        AppCopyField(
          value: domain.isEmpty ? 'https://<domain>/{uuid}/mcp' : 'https://$domain/{uuid}/mcp',
        ),
        const Gap(AppSpacing.lg),
        AppLink(label: '如何在 ChatGPT 中添加 MCP Server →', onPressed: onOpenDocs),
      ],
    );
  }
}
