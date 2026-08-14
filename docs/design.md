# Codexter — 桌面端 APP 设计文档 (v2)

## 一、项目概述

将 `codex-mcp`（Node.js CLI 工具）重构为 **Flutter 桌面端 GUI 应用**。

原 `codex-mcp` 核心能力：启动本地 MCP Server → 通过 Cloudflare Tunnel 暴露公网 → ChatGPT 通过公网地址调用本地工具（读/写文件、执行命令、搜索代码等）。

### 1.1 与原版核心差异

| 维度            | 原 codex-mcp                     | Flutter 版                                                                          |
| --------------- | -------------------------------- | ----------------------------------------------------------------------------------- |
| 界面            | CLI 终端交互                     | shadcn_flutter 桌面 GUI                                                             |
| 工作区          | 单一 projectRoot                 | **多工作区**，各自独立 MCP Handler                                                  |
| 公网入口        | `https://domain/mcp`             | `https://domain/{uuid}/mcp`（UUID 路径防隐私泄露）                                  |
| 授权            | OAuth + 密码                     | **完全移除**                                                                        |
| 日志            | 终端 print + JSONL 文件          | **实时日志流**（类似 ChatGPT Codex 界面，非传统表格）                               |
| 进程            | 进程 ID 句柄，日志在 JSONL       | **运行中终端可视化**，用户可手动关闭                                                |
| Skills/下游 MCP | 自动从 Codex 继承                | **全局管理页**，可导入/手动创建/临时关闭                                            |
| Tunnel          | 生命周期绑定单工作区             | **独立长驻**，增删工作区不断开                                                      |
| MCP 协议参考    | `@modelcontextprotocol/sdk` v2.0 | 参考 [ChatGPT MCP 官方文档](https://learn.chatgpt.com/docs/mcp-server) 纯 Dart 实现 |

### 1.2 MCP 协议要点（参考官方文档）

根据 [ChatGPT 插件官方文档](https://developers.openai.com/plugins/build/mcp-server)，ChatGPT 连接 MCP Server 的核心流程：
[Metadata 字段](https://developers.openai.com/plugins/reference#_meta-fields-on-tool-descriptor)

UI文档：[Shadcn_Flutter 官方文档](https://sunarya-thito.github.io/shadcn_flutter)

```
1. 用户在 ChatGPT → Settings → Apps → Developer Mode → 添加 MCP Server URL
2. ChatGPT 发送 initialize 请求 (JSON-RPC 2.0 over HTTP POST)
3. 服务端返回 server info + capabilities
4. ChatGPT 发送 tools/list 请求
5. 服务端返回所有已注册工具的 schema
6. ChatGPT 按需发送 tools/call 请求
7. 服务端执行工具并返回结果
```

JSON-RPC 2.0 消息格式：

```json
// 请求
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
        "name": "read",
        "arguments": { "path": "src/main.ts" }
    }
}

// 响应（modern MCP clients 使用 structuredContent）
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "content": [{ "type": "text", "text": "..." }],
        "structuredContent": { ... }
    }
}
```

---

## 二、技术选型

### 2.1 运行环境

```
Flutter 3.44.x (stable) + Dart 3.12
当前环境: Flutter 3.44.9 已安装
目标平台: Windows (主要), macOS
```

### 2.2 UI 框架: shadcn_flutter

- **主题系统**：`ShadApp` + `ColorScheme` + `ColorMode`（light/dark）
- **基础组件**：Button、Input、Card、Dialog、Sheet、Select、Tabs、Table、Badge、Tooltip 等
- **高级组件**：Popover、Command、Accordion、Resizable、Sidebar 等
- **设计语言**：圆角卡片、精致边框、中性色调、Tailwind 风格间距

```dart
ShadApp(
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark,
    theme: ShadThemeData(
        colorScheme: const ShadNeutralColorScheme.dark(),
        brightness: Brightness.dark,
    ),
    home: const FirstRunPage(),
)
```

### 2.3 核心依赖清单

| 包名                    | 用途                          |
| ----------------------- | ----------------------------- |
| `shadcn_flutter`        | UI 组件库                     |
| `dart:io` (内置)        | 本地 HTTP Server + 子进程管理 |
| `path_provider`         | 获取配置/日志目录             |
| `hive` / `hive_flutter` | 本地持久化                    |
| `uuid`                  | 生成工作区 UUID               |
| `google_fonts`          | 字体                          |
| `collection`            | 列表工具                      |

---

## 三、整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                  Flutter GUI (shadcn_flutter)                │
│                                                              │
│  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────┐  │
│  │ 首次配置 │ │ 工作区   │ │ 日志/终端 │ │ Skills/MCP     │  │
│  │ 向导页   │ │ 管理主页 │ │ 详情页    │ │ 全局管理页     │  │
│  └────┬────┘ └────┬─────┘ └────┬─────┘ └──────┬─────────┘  │
│       │           │            │              │             │
│  ┌────┴───────────┴────────────┴──────────────┴──────────┐  │
│  │             AppState (ChangeNotifier)                 │  │
│  └────┬───────────┬────────────┬──────────────┬────────┘  │
│       │           │            │              │            │
│  ┌────┴────┐ ┌────┴─────┐ ┌────┴──────┐ ┌────┴────────┐  │
│  │Workspace│ │LogStore  │ │ProcessMgr │ │CapabilityMgr│  │
│  │Manager  │ │(实时流)  │ │(终端管理) │ │(Skills/MCP)│  │
│  └────┬────┘ └─────┬────┘ └─────┬─────┘ └─────┬──────┘  │
│       │            │            │              │          │
│  ┌────┴────────────┴────────────┴──────────────┴───────┐  │
│  │              MCP Core (纯 Dart)                      │  │
│  │  ┌─────────────────────────────────────────────┐     │  │
│  │  │ HttpServer (单端口多路径路由)                 │     │  │
│  │  │ /{uuid}/mcp → Workspace Handler             │     │  │
│  │  └─────────────────────────────────────────────┘     │  │
│  │  ┌─────────────────────────────────────────────┐     │  │
│  │  │ Tool Registry (49 个工具)                    │     │  │
│  │  └─────────────────────────────────────────────┘     │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Tunnel Manager (cloudflared 长驻)            │  │
│  │  APP 启动时创建，增删工作区时不重启                    │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 四、多工作区设计（核心需求 2）

### 4.1 UUID 路径方案

每个工作区使用 UUID 作为 URL 路径前缀：

```
域名: mcp.example.com (全局共用)

工作区 A:
  UUID:  a1b2c3d4-e5f6-7890-abcd-ef1234567890
  路径:  C:\Projects\my-project
  公网:  https://mcp.example.com/a1b2c3d4-e5f6-7890-abcd-ef1234567890/mcp

工作区 B:
  UUID:  b2c3d4e5-f6a7-8901-bcde-f12345678901
  路径:  C:\Projects\demo-app
  公网:  https://mcp.example.com/b2c3d4e5-f6a7-8901-bcde-f12345678901/mcp
```

UUID 的好处：

- **隐私防护**：不可猜测的 URL 路径本身就是访问凭证（security through obscurity + unguessable path）
- **无冲突**：多个工作区不会路径冲突
- **移除授权后仍安全**：不知道 UUID 就无法访问对应工作区

### 4.2 多工作区 HTTP 路由

```dart
class MultiWorkspaceServer {
    final HttpServer _server;
    final Map<String, WorkspaceHandler> _handlers = {};

    Future<void> listen(String host, int port) async {
        _server = await HttpServer.bind(host, port);
        await for (final request in _server) {
            final uuid = _extract_uuid(request.uri.path);
            final handler = _handlers[uuid];
            if (handler != null) {
                await handler.handle(request);
            } else {
                _send_not_found(request);
            }
        }
    }

    // /a1b2c3d4-.../mcp → a1b2c3d4-...
    String? _extract_uuid(String path) {
        final match = RegExp(
            r'^/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/mcp$'
        ).firstMatch(path);
        return match?.group(1);
    }

    // 增删工作区只改 Map，不影响 HttpServer 和 Tunnel
    void add_workspace(String uuid, WorkspaceHandler handler) {
        _handlers[uuid] = handler;
    }

    void remove_workspace(String uuid) {
        _handlers.remove(uuid);
    }
}
```

### 4.3 Tunnel 长驻设计（需求 3）

**关键原则**：cloudflared 进程的生命周期与工作区完全解耦。

```
APP 启动流程:
  1. 加载全局配置
  2. 启动 HttpServer (监听 localhost:3920)
  3. 启动 cloudflared sidecar (长驻，连接 domain → localhost:3920)
  4. 读取工作区列表，为每个工作区注册 handler
  5. GUI 就绪

新建工作区:
  → 仅 _handlers[uuid] = handler
  → Tunnel 和 HttpServer 不受影响

删除工作区:
  → 仅 _handlers.remove(uuid)
  → Tunnel 和 HttpServer 不受影响

APP 关闭:
  → 逐个停止工作区 handler
  → 停止 cloudflared sidecar
  → 关闭 HttpServer
```

cloudflared.yml 配置只需一条 ingress rule（路径全透传）：

```yaml
tunnel: <tunnel-id>
credentials-file: <credentials-path>
protocol: http2
edge-ip-version: 4

ingress:
    - hostname: mcp.example.com
      service: http://127.0.0.1:3920
    - service: http_status:404
```

---

## 五、页面设计

### 5.1 首次打开 — 基础配置向导（需求 2）

APP 首次打开（检测到没有全局配置）时显示配置向导：

```
┌──────────────────────────────────────────────────────┐
│           欢迎使用 Codexter                            │
│                                                      │
│  第 1 步：公网域名配置                                 │
│                                                      │
│  你的域名:                                            │
│  [mcp.example.com                              ]     │
│                                                      │
│  这个域名将用于所有工作区的 ChatGPT 连接。              │
│  每个工作区会获得一个独立的 UUID 路径。                 │
│                                                      │
│  ──────────────────────────────────────────────      │
│                                                      │
│  第 2 步：Cloudflare Tunnel                           │
│                                                      │
│  ☑ 使用 Cloudflare Tunnel（推荐）                      │
│                                                      │
│  [登录 Cloudflare]                                   │
│  状态: 等待登录...                                    │
│                                                      │
│  Tunnel 名称: [codex-mcp                       ]     │
│  [创建 Tunnel]                                       │
│  状态: ✓ Tunnel 已创建 (ID: a1b2c3d4-...)            │
│                                                      │
│  [配置 DNS 路由]                                     │
│  状态: ✓ DNS 已配置                                   │
│                                                      │
│  ──────────────────────────────────────────────      │
│                                                      │
│  第 3 步：验证                                        │
│                                                      │
│  [验证连通性]                                        │
│  状态: ✓ 公网地址可用                                  │
│                                                      │
│  连接地址模板:                                        │
│  https://mcp.example.com/{uuid}/mcp                  │
│                                                      │
│              [上一步]  [完成配置，进入主页]            │
└──────────────────────────────────────────────────────┘
```

配置完成后进入主页，此时没有工作区，显示空状态引导创建。

### 5.2 主页 — 工作区实时状态（需求 4）

主页展示所有工作区的实时卡片状态（类似 ChatGPT Codex 那边的卡片风格，不是传统表格）：

```
┌──────────────┬──────────────────────────────────────────────┐
│              │  工作区                                      │
│  Sidebar     │                                              │
│              │  ┌────────────────────────────────────────┐  │
│  工作区      │  │ ● My Project                     [⋮] │  │
│              │  │ C:\Projects\my-project                 │  │
│  ──────────  │  │                                        │  │
│  ● My Proj   │  │ 最近活动:                               │  │
│    运行中    │  │ ▸ 14:23  read  src/main.ts     12ms ✅ │  │
│  ○ Flutter   │  │ ▸ 14:22  bash  npm run build 340ms ✅ │  │
│    已停止    │  │ ▸ 14:21  git_status          45ms ✅ │  │
│              │  │                                        │  │
│  + 新建      │  │ 进程: 2 个运行中  |  工具调用: 128 次  │  │
│              │  │ 连接: https://mcp.example.com/a1b2...  │  │
│  ──────────  │  └────────────────────────────────────────┘  │
│  Skills      │                                              │
│  MCP 管理    │  ┌────────────────────────────────────────┐  │
│  Setup       │  │ ○ Flutter App                   [⋮]  │  │
│  Doctor      │  │ C:\Projects\demo-app                   │  │
│              │  │ 已停止 · 点击启动                       │  │
│              │  └────────────────────────────────────────┘  │
│              │                                              │
└──────────────┴──────────────────────────────────────────────┘
```

每个工作区卡片实时展示：

- 运行状态（运行中/已停止）指示灯
- 最近 3-5 条工具调用日志（滚动更新）
- 运行中的进程数量
- 工具调用总次数
- 公网连接地址（可复制）

点击卡片进入工作区详情页。

### 5.3 工作区详情页 — 完整日志 + 终端（需求 4 + 5）

```
┌──────────────┬──────────────────────────────────────────────┐
│  ← 返回      │  My Project                          [停止] │  │
│              │  C:\Projects\my-project                       │
│  巀作区      │  连接: https://mcp.example.com/a1b2.../mcp    │
│              │  [复制地址]  [在 ChatGPT 中打开]              │
│  ● My Proj   │                                               │
│              │  ┌─ [实时日志] ── [运行终端] ──────────────┐  │
│  Skills      │  │                                          │  │
│  MCP         │  │  14:23:01  read         12ms  ✅        │  │
│  Setup       │  │  src/main.ts                             │  │
│  Doctor      │  │                                          │  │
│              │  │  14:23:03  bash         340ms ✅         │  │
│              │  │  npm run build                           │  │
│              │  │  ▾ 点击展开查看完整请求/响应              │  │
│              │  │    ┌─ 请求 ─────────────────────────┐    │  │
│              │  │    │ POST /a1b2.../mcp              │    │  │
│              │  │    │ {                              │    │  │
│              │  │    │   "jsonrpc": "2.0",            │    │  │
│              │  │    │   "method": "tools/call",      │    │  │
│              │  │    │   "params": {                  │    │  │
│              │  │    │     "name": "bash",            │    │  │
│              │  │    │     "arguments": {             │    │  │
│              │  │    │       "command": "npm run ..." │    │  │
│              │  │    │     }                          │    │  │
│              │  │    │   }                            │    │  │
│              │  │    │ }                              │    │  │
│              │  │    └────────────────────────────────┘    │  │
│              │  │    ┌─ 响应 ─────────────────────────┐    │  │
│              │  │    │ { "result": { ... } }          │    │  │
│              │  │    └────────────────────────────────┘    │  │
│              │  │                                          │  │
│              │  │  14:23:05  write         8ms  ✅        │  │
│              │  │  src/output.js                           │  │
│              │  └──────────────────────────────────────────┘  │
└──────────────┴──────────────────────────────────────────────┘
```

#### 实时日志 Tab（需求 4）

- **不是传统表格**，而是类似 ChatGPT Codex 对话流的时间线
- 每条日志默认显示一行摘要：`时间 工具名 耗时 状态图标 摘要标题`
- 点击展开显示完整的 ChatGPT 请求 JSON 和 MCP 响应 JSON
- JSON viewer 带语法高亮、折叠/展开
- 新日志自动追加到底部（可锁定滚动）
- 支持按工具名、状态筛选
- 日志使用 LogStore 内存环形缓冲（每工作区 1000 条），不写文件

#### 运行终端 Tab（需求 5）

展示该工作区当前通过 `exec_command` / `bash` 工具启动的、仍在运行的进程：

```
┌─ 运行中的终端 ──────────────────────────────────────┐
│                                                    │
│  ┌─ #3  npm run dev  (运行中 5m 32s)  [关闭] ┐    │
│  │ > my-project@1.0.0 dev                    │    │
│  │ > vite                                    │    │
│  │                                           │    │
│  │   VITE v5.4.0  ready in 342 ms           │    │
│  │                                           │    │
│  │   ➜  Local:   http://localhost:5173/     │    │
│  │   ➜  Network: use --host to expose       │    │  │
│  └────────────────────────────────────────────┘    │
│                                                    │
│  ┌─ #4  python server.py  (运行中 12s)  [关闭] ┐  │
│  │ * Serving Flask app 'server'                │   │
│  │ * Running on http://127.0.0.1:5000          │   │
│  └─────────────────────────────────────────────┘   │
│                                                    │
│  没有更多运行中的进程                                │
└────────────────────────────────────────────────────┘
```

- 每个进程一个终端卡片，实时显示 stdout/stderr 输出
- 显示进程信息：PID、命令、运行时长
- **用户可手动关闭**（发送 SIGTERM → SIGKILL）
- 防止 AI 忘记关闭进程
- 已退出的进程保留一段时间（5 分钟 TTL），然后自动清理
- 对应原版 `ProcessSessionManager`（rolling buffer + 信号管理）

---

## 六、Skills / 下游 MCP 全局管理（需求 6）

### 6.1 设计理念

原版自动从 `~/.codex` 和 `~/.agents` 目录导入 Skills 和下游 MCP 配置。

Flutter 版改为**用户主动管理**：

- 默认为空
- 可从 Codex 导入
- 可手动创建
- 可临时关闭（不删除配置，只是不启用）
- 所有工作区共享同一套全局 Skills 和下游 MCP

### 6.2 Skills 管理页

```
┌─ Skills 管理 ──────────────────────────────────────┐
│                                                    │
│  [+ 手动创建]  [从 Codex 导入]  [刷新]             │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │ ☑ imagegen                       [编辑] [删除]│ │
│  │   生成或编辑光栅图像                            │ │
│  │   来源: codex 导入                              │ │
│  │   路径: ~/.codex/skills/imagegen/SKILL.md      │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │ ☑ openai-docs                    [编辑] [删除]│ │
│  │   Codex 模型/定价文档                          │ │
│  │   来源: codex 导入                              │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │ ☐ my-custom-skill                [编辑] [删除]│ │
│  │   我的自定义 Skill（已临时关闭）                 │ │
│  │   来源: 手动创建                                │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  共 3 个 Skills，2 个启用                           │
└────────────────────────────────────────────────────┘
```

#### Skill 数据模型

```dart
class SkillEntry {
    final String name;
    final String description;
    final SkillSource source;     // codex_import / manual
    final String? root_path;      // skill 目录路径
    final bool enabled;           // 是否启用
    final DateTime created_at;
}
```

#### 从 Codex 导入

对应原版 `SkillRegistry.discoverDefault()`，扫描 `~/.codex/skills/` 和 `~/.agents/skills/`：

```dart
class CapabilityManager {
    /// 扫描 Codex skill 目录，返回可导入的 skill 列表
    Future<List<SkillInfo>> scan_codex_skills() async {
        final roots = [
            join(home_dir, '.codex', 'skills'),
            join(home_dir, '.agents', 'skills'),
        ];
        // 遍历每个 root，查找含 SKILL.md 的子目录
        // 解析 YAML front matter 获取 name + description
    }

    /// 导入选中的 skill
    Future<void> import_skill(SkillInfo info) async {
        // 记录到 Hive，标记 source = codex_import
        // 不复制文件，直接引用原始路径
    }
}
```

#### 手动创建

用户在 GUI 中填写 name + description + SKILL.md 内容，保存到 APP 数据目录。

### 6.3 下游 MCP 管理

```
┌─ 下游 MCP 管理 ────────────────────────────────────┐
│                                                    │
│  [+ 添加]  [从 Codex 导入]  [刷新]                 │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │ ☑ codegraph            [编辑] [删除]          │ │
│  │   stdio: codegraph-server                     │ │
│  │   状态: ● 已连接                               │ │
│  │   来源: codex 导入                              │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │ ☑ github-mcp           [编辑] [删除]          │ │
│  │   url: https://api.github.com/mcp             │ │
│  │   状态: ● 已连接                               │ │
│  │   来源: 手动添加                                │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │ ☐ my-local-mcp         [编辑] [删除]          │ │
│  │   stdio: node server.js（已临时关闭）           │ │
│  │   来源: 手动添加                                │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  共 3 个 MCP，2 个启用                               │
└────────────────────────────────────────────────────┘
```

#### 下游 MCP 数据模型（对应原版 `user-mcp.ts`）

```dart
class DownstreamMcpEntry {
    final String name;
    final McpTransport transport;   // stdio 或 streamable_http
    final bool enabled;
    final McpSource source;         // codex_import / manual
    final int? startup_timeout_ms;
    final int? tool_timeout_ms;
}

class McpTransport {
    // stdio 模式
    final String? command;
    final List<String> args;
    final Map<String, String> env;
    final String? cwd;

    // url 模式
    final String? url;
    final Map<String, String> headers;
}
```

#### 从 Codex 导入

对应原版 `codex-import.ts`，执行 `codex mcp list --json` 解析结果：

```dart
class CapabilityManager {
    Future<List<CodexMcpInfo>> scan_codex_mcp() async {
        final result = await Process.run('codex', ['mcp', 'list', '--json']);
        final list = jsonDecode(result.stdout) as List;
        // 过滤 enabled == true 的
        // 解析 transport (stdio / streamable_http)
        // 解析 env_vars, http_headers, bearer_token_env_var
    }
}
```

#### MCP 运行状态

每个启用的下游 MCP 会建立实际连接（stdio 子进程或 HTTP），状态实时显示在管理页。对应原版 `DownstreamMcpHub`。

---

## 七、MCP Server 核心实现

### 7.1 MCP 方法处理

| MCP Method                  | 处理逻辑                                |
| --------------------------- | --------------------------------------- |
| `initialize`                | 返回 server info + capabilities (tools) |
| `notifications/initialized` | 标记会话已就绪（空响应）                |
| `tools/list`                | 返回所有启用工具的 schema               |
| `tools/call`                | 分发到 ToolRegistry 执行                |
| `resources/list`            | 返回 UI card resource                   |
| `resources/read`            | 返回 UI card 内容                       |

### 7.2 工具注册表

全部 49 个工具从原版移植（`CORE_TOOL_NAMES` 41 个 + `GATEWAY_TOOL_NAMES` 8 个）：

| 分类    | 工具                                                                                                                           | 说明              |
| ------- | ------------------------------------------------------------------------------------------------------------------------------ | ----------------- |
| 文件    | `read`, `read_many`, `write`, `edit`, `apply_patch`                                                                            | 文件读写编辑      |
| 命令    | `bash`, `exec_command`, `write_stdin`, `process_kill`, `process_list`, `process_status`, `process_output`                      | 命令执行+进程管理 |
| 搜索    | `grep`, `glob`, `ls`, `code_explore`                                                                                           | 代码搜索          |
| Git     | `git_status`, `git_diff`, `git_log`, `git_show`, `git_branches`                                                                | Git 操作          |
| 工作区  | `workspace_projects`, `workspace_search`, `workspace_context`, `context_pack`                                                  | 项目探索          |
| Goal    | `goal_start`, `goal_status`, `goal_update`, `goal_verify`, `goal_finish`, `goal_cancel`                                        | 目标管理          |
| UI      | `summary`, `settings_get`, `settings_update`                                                                                   | ChatGPT 交互      |
| Skills  | `skills_list`, `skill_read`                                                                                                    | 技能读取          |
| Agents  | `agents_for_path`                                                                                                              | AGENTS.md 规则    |
| Runtime | `runtime_status`, `server_info`, `capabilities_reload`                                                                         | 运行状态          |
| 网关    | `mcp_servers`, `mcp_reconnect`, `mcp_tools`, `mcp_call`, `mcp_resources`, `mcp_resource_read`, `mcp_prompts`, `mcp_prompt_get` | 下游 MCP          |

### 7.3 Server Instructions 构建

对应原版 `mcp-server.ts` 的 `buildServerInstructions()`，为 ChatGPT 提供工具使用指南。内容包括：

- 环境信息（project_root, shell）
- 完整工具说明映射
- 工具使用顺序建议
- Skills 列表
- 下游 MCP 列表

---

## 八、配置持久化

### 8.1 全局配置

```dart
@HiveType(typeId: 0)
class GlobalConfig extends HiveObject {
    @HiveField(0) String domain = '';
    @HiveField(1) String host = '127.0.0.1';
    @HiveField(2) int port = 3920;
    @HiveField(3) bool use_cloudflared = true;
    @HiveField(4) String? tunnel_id;
    @HiveField(5) String tunnel_name = 'codex-mcp';
    @HiveField(6) String? cloudflared_bin;
    @HiveField(7) bool first_run_completed = false;  // 首次配置是否完成
}
```

### 8.2 工作区配置

```dart
@HiveType(typeId: 1)
class Workspace extends HiveObject {
    @HiveField(0) String uuid;           // UUID v4
    @HiveField(1) String name;
    @HiveField(2) String project_root;
    @HiveField(3) bool auto_start;
    @HiveField(4) DateTime created_at;
    @HiveField(5) DateTime last_active_at;
}
```

### 8.3 Skills 配置

```dart
@HiveType(typeId: 2)
class SkillEntry extends HiveObject {
    @HiveField(0) String name;
    @HiveField(1) String description;
    @HiveField(2) String source;         // codex_import / manual
    @HiveField(3) String? root_path;
    @HiveField(4) bool enabled;
    @HiveField(5) DateTime created_at;
}
```

### 8.4 下游 MCP 配置

```dart
@HiveType(typeId: 3)
class DownstreamMcpEntry extends HiveObject {
    @HiveField(0) String name;
    @HiveField(1) String transport_json;  // JSON 序列化的 transport 配置
    @HiveField(2) bool enabled;
    @HiveField(3) String source;
    @HiveField(4) int? startup_timeout_ms;
    @HiveField(5) int? tool_timeout_ms;
}
```

---

## 九、移除授权模块（需求 1）

原 `codex-mcp` 的 `src/auth/` 目录下 7 个文件全部移除：

| 文件                 | 功能            | 处理 |
| -------------------- | --------------- | ---- |
| `password-store.ts`  | argon2 密码哈希 | 移除 |
| `oauth-state.ts`     | OAuth PKCE      | 移除 |
| `private-key-jwt.ts` | 私钥 JWT        | 移除 |
| `provider.ts`        | OAuth Provider  | 移除 |
| `server.ts`          | OAuth 路由      | 移除 |
| `endpoints.ts`       | OAuth 端点      | 移除 |
| `storage.ts`         | 凭据存储        | 移除 |

HTTP Server 直接处理 `/{uuid}/mcp` 请求，无任何认证中间件。安全性依赖 UUID 路径的不可猜测性。

---

## 十、项目目录结构

```
codexter/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   │
│   ├── models/
│   │   ├── workspace.dart
│   │   ├── global_config.dart
│   │   ├── skill_entry.dart
│   │   ├── downstream_mcp_entry.dart
│   │   └── mcp_log_entry.dart
│   │
│   ├── stores/
│   │   ├── app_state.dart             # 全局状态 (ChangeNotifier)
│   │   ├── config_store.dart          # Hive 配置
│   │   ├── workspace_store.dart       # 工作区管理
│   │   ├── log_store.dart             # 实时日志 (Stream)
│   │   └── process_store.dart         # 进程终端管理
│   │
│   ├── services/
│   │   ├── setup_service.dart         # 首次配置向导
│   │   ├── tunnel_service.dart        # Cloudflare Tunnel 长驻管理
│   │   ├── doctor_service.dart        # 环境检查
│   │   └── capability_manager.dart    # Skills + 下游 MCP 管理
│   │
│   ├── mcp/
│   │   ├── mcp_server.dart            # MCP 协议核心
│   │   ├── multi_workspace_server.dart # 多工作区 HTTP 路由
│   │   ├── json_rpc.dart              # JSON-RPC 2.0
│   │   ├── instructions.dart          # Server instructions
│   │   └── tools/
│   │       ├── registry.dart
│   │       ├── read_tool.dart
│   │       ├── write_tool.dart
│   │       ├── bash_tool.dart
│   │       ├── git_tools.dart
│   │       ├── workspace_tools.dart
│   │       └── ...
│   │
│   ├── ui/
│   │   ├── pages/
│   │   │   ├── first_run_page.dart     # 首次配置向导
│   │   │   ├── home_page.dart          # 工作区列表主页
│   │   │   ├── workspace_detail_page.dart # 工作区详情
│   │   │   ├── setup_page.dart         # 公网配置
│   │   │   ├── doctor_page.dart        # 环境检查
│   │   │   ├── skills_page.dart        # Skills 全局管理
│   │   │   └── mcp_manage_page.dart    # 下游 MCP 全局管理
│   │   ├── widgets/
│   │   │   ├── sidebar.dart
│   │   │   ├── workspace_card.dart     # 工作区实时状态卡片
│   │   │   ├── workspace_form.dart     # 新建工作区
│   │   │   ├── log_timeline.dart       # 日志时间线
│   │   │   ├── log_entry_expanded.dart # 日志展开详情
│   │   │   ├── json_viewer.dart        # JSON 高亮
│   │   │   ├── terminal_card.dart      # 运行中终端卡片
│   │   │   ├── skill_tile.dart
│   │   │   ├── mcp_tile.dart
│   │   │   └── tunnel_status_badge.dart
│   │   └── theme/
│   │       └── app_theme.dart
│   │
│   └── utils/
│       ├── path_guard.dart
│       ├── fs_utils.dart
│       └── fmt.dart
│
├── windows/
├── macos/
├── linux/
├── test/
├── docs/
│   └── design.md
├── pubspec.yaml
└── analysis_options.yaml
```

---

## 十一、实现路线图

### Phase 1：项目骨架 + 首次配置向导（1-2 天）

- `flutter create` 初始化桌面项目
- 添加 `shadcn_flutter`、`hive`、`uuid` 依赖
- shadcn dark 主题
- 首次配置向导页面（域名 → Tunnel → 验证）
- Hive 配置持久化
- 侧边栏 + 页面路由骨架

### Phase 2：Tunnel + HttpServer 基础设施（1 天）

- `MultiWorkspaceServer`（单端口多路径路由）
- `TunnelService`（cloudflared 长驻，APP 生命周期绑定）
- cloudflared.yml 读写
- Tunnel 连通性验证
- Doctor 环境检查

### Phase 3：工作区管理（1 天）

- Workspace 数据模型 + Hive
- 工作区 CRUD（增删不影响 Tunnel）
- 新建工作区对话框
- 工作区实时状态卡片（主页）
- MCP Handler 注册/注销

### Phase 4：MCP Server + 工具（2-3 天）

- JSON-RPC 2.0 解析/分发
- MCP initialize / tools/list / tools/call
- 移植核心工具（read, write, edit, bash, grep, glob, ls）
- 移植 Git 工具集
- 移植 workspace 工具集
- Server instructions 构建

### Phase 5：实时日志 + 终端（1-2 天）

- LogStore 环形缓冲 + Stream
- 在 MCP handler 埋点记录请求/响应
- 日志时间线 UI（卡片式，非表格）
- 日志展开详情 + JSON viewer
- ProcessStore（进程管理 + RollingBuffer）
- 运行终端 Tab + 手动关闭

### Phase 6：Skills + 下游 MCP 全局管理（1 天）

- CapabilityManager（扫描/导入/CRUD）
- Skills 管理页（从 Codex 导入 + 手动创建 + 启用/关闭）
- 下游 MCP 管理页（从 Codex 导入 + 手动添加 + 启用/关闭）
- DownstreamMcpHub Dart 实现（连接 stdio/HTTP 下游 MCP）

### Phase 7：完善和打包（1 天）

- 剩余工具移植（webfetch, process, goals, skills, agents）
- cloudflared 自动下载（对应 `managed-tools/install.ts`）
- 打包 Windows exe / macOS app
- 集成测试

---

## 十二、关键设计决策

### 12.1 UUID 路径代替授权（需求 1 + 2）

移除授权后，使用 UUID v4 作为 URL 路径前缀。UUID v4 有 122 位随机性，暴力猜测概率可忽略。结合 HTTPS 加密，即使域名被知道，不知道 UUID 也无法访问任何工作区。

### 12.2 Tunnel 与工作区解耦（需求 3）

```
Tunnel 生命周期:  APP 启动 ────────────────────── APP 关闭
                            │
工作区 A:               注册────────────注销
工作区 B:                    注册────────注销
工作区 C:                       注册─────注销
```

cloudflared 进程只在 APP 启动和关闭时管理，增删工作区只修改 `_handlers` Map。

### 12.3 日志用时间线不用表格（需求 4）

传统表格不适合展示 MCP 工具调用日志——请求/响应 JSON 体积差异巨大，表格列宽无法适配。采用类似 ChatGPT Codex 对话流的时间线：

- 折叠态：一行摘要
- 展开态：请求/响应 JSON 完整展示
- 实时追加，自动滚动

### 12.4 进程终端可视化（需求 5）

原版 `ProcessSessionManager` 的进程数据只在 JSONL 日志和 `process_output` 工具调用中可见。Flutter 版将运行中的进程直接展示为终端卡片：

- RollingBuffer（原版已有）→ GUI 实时渲染
- 用户可手动 SIGTERM/SIGKILL（对应原版 `process_kill`）
- 防止 AI 忘记关闭服务器/守护进程

### 12.5 Skills/MCP 全局管理而非自动继承（需求 6）

原版自动从 Codex 继承所有 Skills 和下游 MCP。Flutter 版改为用户主动管理：

- 避免导入不需要的配置
- 可临时关闭而非删除
- 可手动创建自定义 Skill/MCP
- 所有工作区共享同一套配置

---

## 十三、附录：原版文件映射

| 原版文件                            | Flutter 版                         | 说明                 |
| ----------------------------------- | ---------------------------------- | -------------------- |
| `src/cli.ts`                        | `app.dart` + 侧边栏                | 命令路由 → 页面路由  |
| `src/server/http-server.ts`         | `mcp/multi_workspace_server.dart`  | HTTP Server (多路径) |
| `src/server/mcp-server.ts`          | `mcp/mcp_server.dart`              | MCP 协议             |
| `src/tools/register.ts`             | `mcp/tools/registry.dart`          | 工具注册             |
| `src/tools/*.ts`                    | `mcp/tools/*.dart`                 | 各工具               |
| `src/config/user-config.ts`         | `stores/config_store.dart`         | 全局配置             |
| `src/config/user-mcp.ts`            | `models/downstream_mcp_entry.dart` | MCP 配置模型         |
| `src/config/codex-import.ts`        | `services/capability_manager.dart` | Codex 导入           |
| `src/tunnel/setup.ts`               | `services/setup_service.dart`      | 首次配置             |
| `src/tunnel/sidecar.ts`             | `services/tunnel_service.dart`     | Tunnel 进程          |
| `src/tunnel/verify.ts`              | `services/tunnel_service.dart`     | 验证                 |
| `src/tunnel/yml.ts`                 | `services/tunnel_service.dart`     | yml 读写             |
| `src/doctor/index.ts`               | `services/doctor_service.dart`     | 环境检查             |
| `src/auth/*`                        | **移除**                           | 授权全部移除         |
| `src/lib/tool/log.ts`               | `stores/log_store.dart`            | 工具日志             |
| `src/lib/process/sessions.ts`       | `stores/process_store.dart`        | 进程管理             |
| `src/lib/process/rolling-buffer.ts` | `stores/process_store.dart`        | 输出缓冲             |
| `src/skills/registry.ts`            | `services/capability_manager.dart` | Skills 注册          |
| `src/downstream/hub.ts`             | `services/capability_manager.dart` | 下游 MCP Hub         |
| `src/capabilities/runtime.ts`       | `services/capability_manager.dart` | 能力热更新           |
| `src/managed-tools/install.ts`      | `services/tunnel_service.dart`     | cloudflared 下载     |
| `src/lib/util/terminal.ts`          | GUI 组件                           | 终端输出 → GUI       |
| `src/ui/tool-summary.ts`            | `utils/fmt.dart`                   | 摘要格式化           |
| `src/workspace/*.ts`                | `mcp/tools/workspace_tools.dart`   | 工作区工具           |
