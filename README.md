# Codexter

给网页版 ChatGPT 使用的本地 MCP 插件服务，工具能力对齐本地 Codex。

它将本地项目目录以独立 MCP 地址暴露出来，并提供文件操作、代码搜索、命令执行、Skills、下游 MCP、Cloudflare Tunnel 和调用日志等能力。

## 主要功能

- **多工作区**：每个项目目录对应一个独立 MCP 地址，统一由单个本地服务管理。
- **本地开发工具**：内置 `read`、`apply_patch`、`ls`、`grep`、`glob`、`code_explore`、`exec_command`、`write_stdin` 等工具。
- **Skills 管理**：支持从 Codex 导入 Skills，也可以手动创建、编辑和启停。
- **下游 MCP**：支持导入或添加其他 MCP Server，并通过 `mcp_tools` / `mcp_call` 统一调用。
- **公网访问**：可通过 Cloudflare Tunnel 将本地 MCP 服务暴露到 HTTPS 域名。
- **运行状态与日志**：查看工作区调用记录、工具执行状态和运行中的命令进程。
- **环境检测**：检查 Cloudflared、Tunnel、域名、本地服务、Git 和工作区路径等状态。

## MCP 地址

默认本地监听地址：

```text
http://127.0.0.1:18920/{workspace-uuid}/mcp
```

配置公网域名后：

```text
https://mcp.example.com/{workspace-uuid}/mcp
```

不同工作区通过 UUID 区分，共用同一个服务端口和 Cloudflare Tunnel。

## 开发运行

需要已安装 Flutter。

```bash
flutter pub get
flutter run -d windows
```

构建 Windows 桌面版本：

```bash
flutter build windows
```

## 使用流程

1. 首次启动完成本地服务 / Cloudflare Tunnel 配置。
2. 创建工作区并选择本地项目目录。
3. 按需导入 Skills 或配置下游 MCP。
4. 将工作区显示的 MCP 地址添加到支持 MCP 的客户端中。
5. 在应用内查看调用日志、运行状态和环境检测结果。

## 技术栈

- Flutter / Dart
- shadcn_flutter
- Hive
- Cloudflare Tunnel / cloudflared
