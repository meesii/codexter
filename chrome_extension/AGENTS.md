# CRITICAL — 语言规则

- **所有回复必须使用简体中文**，包括解释、方案分析、commit message、PR 描述。代码/命令/技术术语保持英文原文。
- 此规则无例外——长对话后半段、多轮修改过程中，禁止切换为英文回复。

## 环境

Windows + PowerShell，禁止 bash 专用语法（`&&` 链接、`rm -rf`、`export`）。
缩进统一 **4 空格**，禁止 2 空格或 tab。

## 1. 代码架构

- **文件规模**：单文件 500 行以内，超过时拆分为子模块
- **去重**：编写前检索上下文，复用已有逻辑；重复代码必须提取
- **结构聚合（最高优先级）**：
    - 严禁零散顶层 function / const，同一职责域**必须**收入同一对象
    - 新增代码先检查是否有同职责对象可归入，有则追加，禁止另起
    - 发现已有散落函数时，**必须主动重构**为对象聚合
    - 允许的顶层对象：`state`（响应式）、`api`（请求）、`action`（操作）、`fmt`（格式化）、`service`（业务）、`config`（配置）等

    ```js
    /* ✅ 正确 */
    const api = {
        params() { ... },
        async load() { ... },
        reload() { api.load(); },
    };

    /* ❌ 错误 */
    function build_params() { ... }
    async function load_data() { ... }
    ```

## 2. 命名与文件

- **变量/函数**：`snake_case`，最多 3 个单词（如 `load_list`、`fmt_profit`、`force_sell_all`），超过 3 个单词的命名必须缩短或拆分逻辑
- **文件名**：`kebab-case`（如 `ocean-token.js`、`balance-service.ts`、`friend-detail-sheet.tsx`）
- **类/接口/组件**：`PascalCase`（如 `FreqtradeClient`、`BalanceResponse`、`FriendDetailSheet`）
- **常量**：`snake_case` 全大写（如 `MAX_FEE_THRESHOLD`、`POLL_INTERVAL_MS`）
- **禁止单字母命名**：变量、函数、参数一律不得使用单字母（如 `g`、`m`、`c`、`f`）。回调参数也必须有语义（`.map((msg) => ...)` 而非 `.map((m) => ...)`）。唯一例外：`i` / `j` 用于 for 循环索引
- 常用缩写：`advertiser` → `adv`，`promotion` → `promo`，`config`、`info`、`param`、`req`（request）、`res`（response）、`fmt`
- 用最简单常见的英语单词命名，禁止生僻词和长单词。优先用：`list` / `item` / `row` / `data` / `state` / `query` / `load` / `save` / `edit` / `del` / `fmt` / `action` / `modal` / `info` / `config` / `param` / `key` / `val` / `map` / `set` / `get` / `add` / `remove`

## 3. 注释（最高优先级，零容忍）

> **⚠️ 此规则为硬性约束，违反即为交付失败。每次写代码前必须重读此节。**

- **JSDoc 严禁写成单行**。无论内容多短，必须展开为至少三行：`/**` 独占一行、内容行以 `*` 开头、`*/` 独占一行。
- **严禁对聚合对象使用 `@type {Object}`**。这会覆盖 tsserver 的类型推断，导致内部属性/方法无法"转到定义"。聚合对象的 JSDoc 只写描述文字，不加 `@type`。
- 聚合对象**可以不加** JSDoc；如需注释，只写一句描述放在声明处，禁止加 `@type`，内部方法禁止逐个注释
- 禁止文件头部注释（署名、日期、描述等），文件第一行直接写代码
- 禁止多余的 `//` 装饰性/分区注释（如 `// --- xxx ---`）

    ```js
    /* ✅ 唯一正确写法——只写描述，不加 @type */
    /**
     * 各维度的 data_key
     */
    const data_key_map = { ... };

    /* ❌ 严重错误——@type {Object} 会破坏 IDE 类型推断 */
    /**
     * @type {Object} 各维度的 data_key
     */
    const data_key_map = { ... };

    /* ❌ 同样错误——单行 JSDoc 绝对禁止 */
    /** @type {Object} 各维度的 data_key */
    const data_key_map = { ... };
    ```

**自检时若发现任何 `@type {Object}` 标注在聚合对象上，必须删除 @type 只保留描述。若发现单行 JSDoc，必须拆为三行。**

## 4. 上下文管理

- 非主线操作（批量搜索、文件探索、独立小修改）优先启动 sub-agent
- 大范围搜索（超 3 个文件）必须用 sub-agent
- 主上下文只保留：核心决策、关键代码变更、连续推理逻辑

## 5. 完成自检（必须执行）

代码写完后，**必须逐条核对以下清单**再交付，不得跳过：

1. **注释格式**：是否存在单行 JSDoc（`/**` 与 `*/` 同一行）？有则拆为三行。是否有多余 `//` 注释？有则删除。是否对对象加了 `@type {Object}`？有则删除只保留描述
2. **命名规范**：变量/函数是否 `snake_case` 且不超过 3 个单词？是否用了生僻或复杂英语单词？文件名是否 `kebab-case`？类/接口/组件是否 `PascalCase`？
3. **结构聚合**：是否有新增的零散顶层 function/const 未归入对象？
4. **功能完整**：用户要求的每一项功能是否都已实现？逐条对照用户原始需求
5. **代码保护**：是否误删/误改了已有代码或不相关逻辑？

发现违规时**当场修复**，不得留给用户。自检过程无需在回复中展示，只需确保交付代码合规。
