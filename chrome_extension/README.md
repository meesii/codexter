# Codexter Chrome Extension

这是 Codexter 的 ChatGPT 浏览器扩展，负责页面桥接、消息发送、状态监听、消息队列面板，以及长对话性能优化。

GitHub: https://github.com/meesii/codexter

## 功能

- **Codexter Bridge**：`service-worker.js` 连接 `ws://127.0.0.1:17616/browser`，将当前标签页事件转发给 Flutter 客户端。
- **页面状态监听**：监听 ChatGPT WebSocket 流，识别 `conversation_id`、`turn_id`、增量内容和一轮对话完成状态。
- **页面操作**：支持向 ChatGPT 输入框发送消息、停止当前生成，以及会话结束后继续发送本地队列。
- **桥接面板**：ChatGPT 页面右下角提供 Codexter 状态、立即发送和消息队列。
- **精简历史过程**：保留用户问题和最终回复，删除 thoughts、reasoning recap、commentary、工具调用、tool result 和 MCP UI 等历史过程节点。
- **增强原生虚拟化**：放开 ChatGPT 自己的历史 turn 虚拟化，减少无意义的历史 DOM 常驻。
- **兼容性检测**：长会话自动检测当前 ChatGPT React turn 结构是否仍兼容虚拟化 Hook。

## 本地加载

1. 启动 Codexter，确保 Browser Bridge 服务已经监听本地端口。
2. 打开 `chrome://extensions/` 并开启开发者模式。
3. 点击“加载已解压的扩展程序”，选择 `chrome_extension`。
4. 刷新已打开的 ChatGPT 页面。
5. 页面右下角显示“Codexter 已连接”后即可使用桥接功能。

历史精简属于历史数据加载阶段修改，切换后需要刷新当前会话才能完整生效。
