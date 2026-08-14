/// Build the shared self-contained MCP Apps HTML card.
///
/// The component deliberately has no external assets so its CSP can stay empty.
/// Tool/group identity arrives dynamically through tool result metadata, allowing
/// every ordinary tool to reuse one cached UI resource.
String buildMcpToolCardHtml() {
  return '''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<style>
:root {
  color-scheme: light dark;
  --bg: rgba(255, 255, 255, 0.92);
  --bg-hover: rgba(248, 248, 248, 0.98);
  --panel: rgba(246, 246, 246, 0.92);
  --border: rgba(0, 0, 0, 0.12);
  --border-strong: rgba(0, 0, 0, 0.18);
  --fg: #171717;
  --muted: #737373;
  --muted-2: #a3a3a3;
  --success: #16a34a;
  --warn: #d97706;
  --danger: #dc2626;
  --accent: rgba(0, 0, 0, 0.06);
  --radius: 10px;
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
:root[data-theme="dark"] {
  --bg: rgba(25, 25, 25, 0.96);
  --bg-hover: rgba(30, 30, 30, 0.98);
  --panel: rgba(15, 15, 15, 0.72);
  --border: rgba(255, 255, 255, 0.10);
  --border-strong: rgba(255, 255, 255, 0.16);
  --fg: #ededed;
  --muted: #a3a3a3;
  --muted-2: #737373;
  --success: #4ade80;
  --warn: #fbbf24;
  --danger: #fb7185;
  --accent: rgba(255, 255, 255, 0.06);
}
* { box-sizing: border-box; }
html, body {
  margin: 0 !important;
  padding: 0 !important;
  width: 100%;
  height: auto;
  min-height: 0;
  background: transparent !important;
  color: var(--fg);
}
button { font: inherit; }
.frame {
  width: 100%;
  margin: 0;
  padding: 4px 0;
}
html.is-mobile .frame {
  padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px));
}
.card {
  width: 100%;
  overflow: hidden;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  transition: border-color 140ms ease, background 140ms ease;
}
.card:hover { border-color: var(--border-strong); }
.strip {
  min-height: 46px;
  display: flex;
  align-items: center;
  gap: 9px;
  width: 100%;
  border: 0;
  padding: 9px 11px;
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
}
.strip:hover { background: var(--bg-hover); }
.status { width: 7px; height: 7px; border-radius: 999px; flex: 0 0 auto; background: var(--muted-2); }
.status.running { background: var(--warn); box-shadow: 0 0 0 3px color-mix(in srgb, var(--warn) 14%, transparent); }
.status.ok { background: var(--success); }
.status.fail { background: var(--danger); }
.spinner {
  width: 12px; height: 12px; border-radius: 50%; flex: 0 0 auto;
  border: 1.5px solid var(--border-strong); border-top-color: var(--warn);
  animation: spin .8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
.tool {
  flex: 0 0 auto;
  max-width: 150px;
  padding: 2px 6px;
  border: 1px solid var(--border);
  border-radius: 6px;
  color: var(--muted);
  font: 600 10px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.purpose {
  min-width: 0;
  flex: 1 1 auto;
  font-size: 12px;
  line-height: 1.45;
  color: var(--fg);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.outcome {
  flex: 0 1 auto;
  max-width: 180px;
  color: var(--muted);
  font-size: 11px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.chevron { flex: 0 0 auto; width: 14px; color: var(--muted); transition: transform 140ms ease; }
.card.expanded .chevron { transform: rotate(90deg); }
.details { display: none; border-top: 1px solid var(--border); padding: 12px; background: var(--panel); }
.card.expanded .details { display: block; }
.header-row { display: flex; align-items: flex-start; gap: 10px; margin-bottom: 11px; }
.header-main { min-width: 0; flex: 1; }
.group { color: var(--muted); font-size: 10px; margin-bottom: 3px; }
.detail-purpose { font-size: 12px; line-height: 1.55; overflow-wrap: anywhere; }
.actions { display: flex; flex-wrap: wrap; gap: 6px; justify-content: flex-end; }
.action {
  border: 1px solid var(--border);
  background: var(--bg);
  color: var(--fg);
  border-radius: 7px;
  padding: 5px 8px;
  font-size: 10px;
  cursor: pointer;
}
.action:hover { background: var(--bg-hover); border-color: var(--border-strong); }
.action:disabled { cursor: default; opacity: .48; }
.sections { display: grid; grid-template-columns: 1fr; gap: 9px; }
.section { min-width: 0; }
.section-title { font-size: 10px; font-weight: 600; color: var(--muted); margin: 0 0 5px; }
.kv { display: grid; grid-template-columns: minmax(82px, 120px) 1fr; gap: 4px 9px; font-size: 11px; line-height: 1.5; }
.k { color: var(--muted); overflow-wrap: anywhere; }
.v { min-width: 0; color: var(--fg); font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; overflow-wrap: anywhere; white-space: pre-wrap; }
pre {
  margin: 0;
  max-height: 320px;
  overflow: auto;
  padding: 9px 10px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: color-mix(in srgb, var(--bg) 70%, transparent);
  color: var(--fg);
  font: 10.5px/1.52 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.note { margin-top: 6px; color: var(--muted); font-size: 10px; }
.error { color: var(--danger); }
@media (min-width: 640px) {
  .sections.two { grid-template-columns: minmax(220px, .72fr) minmax(280px, 1.28fr); }
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: rgba(25, 25, 25, 0.96);
    --bg-hover: rgba(30, 30, 30, 0.98);
    --panel: rgba(15, 15, 15, 0.72);
    --border: rgba(255, 255, 255, 0.10);
    --border-strong: rgba(255, 255, 255, 0.16);
    --fg: #ededed;
    --muted: #a3a3a3;
    --muted-2: #737373;
    --success: #4ade80;
    --warn: #fbbf24;
    --danger: #fb7185;
    --accent: rgba(255, 255, 255, 0.06);
  }
}
/* ChatGPT-aligned v5: system typography and inspector-style arguments. */
:root {
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 14px;
  line-height: 1.5;
}
.strip { min-height: 48px; gap: 9px; padding: 10px 12px; }
.tool { max-width: 160px; padding: 2px 7px; font-size: 11px; line-height: 1.45; }
.purpose { font-size: 14px; line-height: 1.45; }
.outcome { max-width: 200px; font-size: 12px; line-height: 1.4; }
.details { padding: 14px 16px 16px; }
.header-row { gap: 12px; margin-bottom: 14px; }
.group { font-size: 12px; line-height: 1.4; margin-bottom: 3px; }
.detail-purpose { font-size: 14px; line-height: 1.5; }
.action { padding: 6px 9px; font-size: 12px; line-height: 1.35; }
.sections { gap: 14px; align-items: start; }
.section-title { margin-bottom: 8px; font-size: 12px; line-height: 1.4; }
.param-list { display: flex; flex-direction: column; gap: 10px; }
.param-item { min-width: 0; }
.param-key { margin-bottom: 4px; color: var(--muted); font-size: 12px; line-height: 1.35; font-weight: 500; overflow-wrap: anywhere; }
.param-value {
  min-width: 0;
  padding: 8px 10px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: color-mix(in srgb, var(--bg) 72%, transparent);
  color: var(--fg);
  font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  overflow-wrap: anywhere;
  white-space: pre-wrap;
}
.param-value.scrollable {
  max-height: 156px;
  overflow: auto;
  overscroll-behavior: contain;
}
.param-line + .param-line { margin-top: 3px; }
.param-empty { color: var(--muted); font-size: 13px; }
pre { font-size: 12px; line-height: 1.55; }
.note { font-size: 12px; line-height: 1.45; }
@media (min-width: 720px) {
  .sections.two { grid-template-columns: minmax(250px, .78fr) minmax(320px, 1.22fr); }
}
</style>
</head>
<body>
<div class="frame">
<div id="card" class="card">
  <button id="strip" class="strip" type="button" aria-expanded="false">
    <span id="status" class="status running"></span>
    <span id="spinner" class="spinner" aria-hidden="true"></span>
    <span id="tool" class="tool">tool</span>
    <span id="purpose" class="purpose">正在执行工具…</span>
    <span id="outcome" class="outcome"></span>
    <svg class="chevron" viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M6 3.5 10.5 8 6 12.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
  </button>
  <div id="details" class="details">
    <div class="header-row">
      <div class="header-main">
        <div id="group" class="group"></div>
        <div id="detailPurpose" class="detail-purpose"></div>
      </div>
      <div class="actions">
        <button id="fullscreen" class="action" type="button" hidden>全屏</button>
      </div>
    </div>
    <div id="sections" class="sections two">
      <section class="section">
        <h3 class="section-title">调用参数</h3>
        <div id="input" class="param-list"></div>
      </section>
      <section class="section">
        <h3 class="section-title">执行结果</h3>
        <pre id="output">等待结果…</pre>
        <div id="outputNote" class="note" hidden></div>
      </section>
    </div>
  </div>
</div>
</div>
<script>
(function () {
  "use strict";
  var DEFAULT_GROUP_LABEL = "工具调用";
  var MAX_RESULT_CHARS = 24000;
  var card = document.getElementById("card");
  var strip = document.getElementById("strip");
  var statusEl = document.getElementById("status");
  var spinnerEl = document.getElementById("spinner");
  var toolEl = document.getElementById("tool");
  var purposeEl = document.getElementById("purpose");
  var outcomeEl = document.getElementById("outcome");
  var groupEl = document.getElementById("group");
  var detailPurposeEl = document.getElementById("detailPurpose");
  var inputEl = document.getElementById("input");
  var outputEl = document.getElementById("output");
  var outputNoteEl = document.getElementById("outputNote");
  var fullscreenButton = document.getElementById("fullscreen");

  var latestInput = null;
  var latestEnvelope = null;
  var latestStructured = null;
  var latestUiMeta = null;
  var hostContext = null;
  var expanded = false;
  var pendingRequests = new Map();
  var nextRequestId = 1;
  var globalsSyncTimer = null;
  var globalsSyncAttempts = 0;

  function openai() {
    try { return window.openai || null; } catch (_error) { return null; }
  }

  function isMobileHost() {
    try {
      var oa = openai();
      if (oa) {
        var ua = oa.userAgent;
        if (typeof ua === "string" && /Mobile|Android|iPhone|iPad|iPod/i.test(ua)) return true;
        if (ua && typeof ua === "object") {
          var device = ua.device || ua.deviceType || ua.platform || ua.type;
          if (typeof device === "string" && /mobile|phone|tablet|ios|android/i.test(device)) return true;
          if (ua.mobile === true || ua.isMobile === true) return true;
        }
        var safe = oa.safeArea;
        var insets = safe && (safe.insets || safe);
        if (insets) {
          var left = Number(insets.left || insets.insetLeft || 0);
          var right = Number(insets.right || insets.insetRight || 0);
          if (left > 0 || right > 0) return true;
        }
      }
    } catch (_error1) {}
    try {
      return window.matchMedia("(max-width: 480px) and (pointer: coarse)").matches;
    } catch (_error2) {
      return false;
    }
  }

  function applyViewportClass() {
    document.documentElement.classList.toggle("is-mobile", isMobileHost());
  }

  function clip(value, max) {
    var text = String(value == null ? "" : value).replace(/\\s+/g, " ").trim();
    if (text.length <= max) return text;
    return text.slice(0, Math.max(0, max - 1)) + "…";
  }

  function safeObject(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : null;
  }

  function findUiMeta(value, depth) {
    if (depth == null) depth = 0;
    if (depth > 5 || !value || typeof value !== "object") return null;
    if (value.codexMcpUi && typeof value.codexMcpUi === "object") return value.codexMcpUi;
    if (value._meta && typeof value._meta === "object" && value._meta.codexMcpUi) return value._meta.codexMcpUi;
    var keys = ["mcp_tool_result", "call_tool_result", "result", "params", "payload"];
    for (var i = 0; i < keys.length; i += 1) {
      var next = value[keys[i]];
      var found = findUiMeta(next, depth + 1);
      if (found) return found;
    }
    return null;
  }

  function findStructured(value, depth) {
    if (depth == null) depth = 0;
    if (depth > 5 || !value || typeof value !== "object") return null;
    if (value.structuredContent && typeof value.structuredContent === "object") return value.structuredContent;
    var keys = ["mcp_tool_result", "call_tool_result", "result", "params", "payload"];
    for (var i = 0; i < keys.length; i += 1) {
      var found = findStructured(value[keys[i]], depth + 1);
      if (found) return found;
    }
    return null;
  }

  function findContentText(value, depth) {
    if (depth == null) depth = 0;
    if (depth > 5 || !value || typeof value !== "object") return "";
    if (Array.isArray(value.content)) {
      var parts = [];
      value.content.forEach(function (item) {
        if (item && typeof item === "object" && typeof item.text === "string") parts.push(item.text);
      });
      if (parts.length) return parts.join("\\n");
    }
    var keys = ["mcp_tool_result", "call_tool_result", "result", "params", "payload"];
    for (var i = 0; i < keys.length; i += 1) {
      var text = findContentText(value[keys[i]], depth + 1);
      if (text) return text;
    }
    return "";
  }

  function readInitialGlobals() {
    var oa = openai();
    if (!oa) return;
    try { latestInput = safeObject(oa.toolInput) || latestInput; } catch (_error1) {}
    try { latestStructured = safeObject(oa.toolOutput) || latestStructured; } catch (_error2) {}
    try {
      latestEnvelope = safeObject(oa.toolResponseMetadata) || latestEnvelope;
      latestUiMeta = findUiMeta(latestEnvelope) || latestUiMeta;
      latestStructured = latestStructured || findStructured(latestEnvelope);
    } catch (_error3) {}
    try {
      var state = safeObject(oa.widgetState);
      if (state && typeof state.expanded === "boolean") expanded = state.expanded;
    } catch (_error4) {}
    applyTheme();
    applyViewportClass();
  }


  function stopGlobalsSync() {
    if (globalsSyncTimer != null) clearTimeout(globalsSyncTimer);
    globalsSyncTimer = null;
  }

  function scheduleGlobalsSync() {
    if (isComplete() || globalsSyncTimer != null) return;
    var delay = globalsSyncAttempts < 8 ? 250 : 1000;
    globalsSyncTimer = setTimeout(function () {
      globalsSyncTimer = null;
      globalsSyncAttempts += 1;
      readInitialGlobals();
      render();
      if (isComplete()) stopGlobalsSync();
      else scheduleGlobalsSync();
    }, delay);
  }
  function applyTheme(explicit) {
    var theme = explicit;
    if (!theme) {
      try { theme = openai() && openai().theme; } catch (_error) {}
    }
    if (theme === "dark" || theme === "light") document.documentElement.dataset.theme = theme;
  }

  function notifyHeight() {
    requestAnimationFrame(function () {
      try {
        var oa = openai();
        if (oa && typeof oa.notifyIntrinsicHeight === "function") {
          oa.notifyIntrinsicHeight({ height: Math.ceil(document.documentElement.scrollHeight) });
        }
      } catch (_error) {}
    });
  }

  function persistState() {
    try {
      var oa = openai();
      if (oa && typeof oa.setWidgetState === "function") oa.setWidgetState({ expanded: expanded });
    } catch (_error) {}
  }

  function groupLabel() {
    if (latestUiMeta && typeof latestUiMeta.groupLabel === "string" && latestUiMeta.groupLabel.trim()) {
      return latestUiMeta.groupLabel.trim();
    }
    return DEFAULT_GROUP_LABEL;
  }

  function toolName() {
    return latestUiMeta && latestUiMeta.tool ? String(latestUiMeta.tool) : "tool";
  }

  function purpose() {
    if (latestInput && typeof latestInput.purpose === "string" && latestInput.purpose.trim()) return latestInput.purpose.trim();
    if (latestUiMeta && typeof latestUiMeta.purpose === "string" && latestUiMeta.purpose.trim()) return latestUiMeta.purpose.trim();
    return "正在执行工具";
  }

  function isError() {
    if (latestUiMeta && latestUiMeta.ok === false) return true;
    if (latestStructured && latestStructured.error != null) return true;
    if (latestEnvelope && latestEnvelope.isError === true) return true;
    return false;
  }

  function isComplete() {
    return !!latestUiMeta || !!latestStructured || !!latestEnvelope;
  }

  function summary() {
    var data = latestStructured || {};
    if (isError()) {
      var err = data.error || findContentText(latestEnvelope) || "调用失败";
      return clip(err, 90);
    }
    if (typeof data.exitCode === "number") return "退出码 " + data.exitCode;
    if (typeof data.matchCount === "number") return data.matchCount + " 处匹配";
    if (typeof data.lineCount === "number") return data.lineCount + " 行";
    if (typeof data.bytes === "number") return data.bytes + " 字节";
    if (typeof data.count === "number") return data.count + " 项";
    if (typeof data.toolCount === "number") return data.toolCount + " 个工具";
    if (data.running === true) return "运行中";
    if (typeof data.state === "string") return clip(data.state, 60);
    if (typeof data.text === "string" && data.text.trim()) return clip(data.text, 90);
    var text = findContentText(latestEnvelope);
    if (text) return clip(text, 90);
    return isComplete() ? "完成" : "";
  }

  function displayValue(value) {
    if (value == null) return "";
    if (typeof value === "string") return value;
    if (typeof value === "number" || typeof value === "boolean") return String(value);
    try { return JSON.stringify(value, null, 2); } catch (_error) { return String(value); }
  }

  function renderInput() {
    inputEl.replaceChildren();
    var input = safeObject(latestInput) || {};
    var keys = Object.keys(input).filter(function (key) { return key !== "purpose"; });
    if (!keys.length) {
      var empty = document.createElement("div");
      empty.className = "param-empty";
      empty.textContent = "无调用参数";
      inputEl.append(empty);
      return;
    }
    keys.forEach(function (key) {
      var item = document.createElement("div");
      item.className = "param-item";
      var label = document.createElement("div");
      label.className = "param-key";
      label.textContent = key;
      var value = document.createElement("div");
      value.className = "param-value";
      var raw = input[key];
      var renderedValue = displayValue(raw);
      var shouldScroll =
        (typeof raw === "string" && (raw.indexOf("\\n") !== -1 || raw.length > 320)) ||
        (Array.isArray(raw) && raw.length > 6) ||
        (raw && typeof raw === "object" && renderedValue.length > 320);
      if (shouldScroll) value.classList.add("scrollable");
      if (Array.isArray(raw) && raw.every(function (entry) {
        return entry == null || typeof entry === "string" || typeof entry === "number" || typeof entry === "boolean";
      })) {
        if (!raw.length) {
          value.textContent = "[]";
        } else {
          raw.forEach(function (entry) {
            var line = document.createElement("div");
            line.className = "param-line";
            line.textContent = displayValue(entry);
            value.append(line);
          });
        }
      } else {
        value.textContent = displayValue(raw);
      }
      item.append(label, value);
      inputEl.append(item);
    });
  }

  function resultForDisplay() {
    if (latestStructured) return latestStructured;
    var text = findContentText(latestEnvelope);
    if (text) return { text: text };
    if (latestEnvelope) return latestEnvelope;
    return null;
  }

  function renderOutput() {
    var result = resultForDisplay();
    outputNoteEl.hidden = true;
    if (!result) {
      outputEl.textContent = "等待结果…";
      return;
    }
    var rendered;
    if (typeof result === "string") rendered = result;
    else {
      try { rendered = JSON.stringify(result, null, 2); } catch (_error) { rendered = String(result); }
    }
    if (rendered.length > MAX_RESULT_CHARS) {
      outputEl.textContent = rendered.slice(0, MAX_RESULT_CHARS) + "\\n…";
      outputNoteEl.textContent = "结果较长，组件内已截断；完整结果仍保留在工具调用记录中。";
      outputNoteEl.hidden = false;
    } else {
      outputEl.textContent = rendered;
    }
    outputEl.classList.toggle("error", isError());
  }

  function render() {
    var complete = isComplete();
    var failed = complete && isError();
    card.classList.toggle("expanded", expanded);
    strip.setAttribute("aria-expanded", expanded ? "true" : "false");
    statusEl.className = "status " + (complete ? (failed ? "fail" : "ok") : "running");
    spinnerEl.hidden = complete;
    toolEl.textContent = toolName();
    purposeEl.textContent = purpose();
    outcomeEl.textContent = summary();
    groupEl.textContent = groupLabel() + " · " + toolName();
    detailPurposeEl.textContent = purpose();
    fullscreenButton.hidden = !(openai() && typeof openai().requestDisplayMode === "function");
    renderInput();
    renderOutput();
    notifyHeight();
  }

  function bridgeRequest(method, params) {
    if (window.parent === window) return Promise.reject(new Error("MCP Apps host unavailable"));
    var id = nextRequestId++;
    window.parent.postMessage({ jsonrpc: "2.0", id: id, method: method, params: params }, "*");
    return new Promise(function (resolve, reject) {
      pendingRequests.set(id, { resolve: resolve, reject: reject });
      setTimeout(function () {
        var pending = pendingRequests.get(id);
        if (!pending) return;
        pendingRequests.delete(id);
        reject(new Error("Host request timed out"));
      }, 30000);
    });
  }

  function bridgeNotify(method, params) {
    if (window.parent === window) return;
    var message = { jsonrpc: "2.0", method: method };
    if (params !== undefined) message.params = params;
    window.parent.postMessage(message, "*");
  }

  async function initializeBridge() {
    try {
      var result = await bridgeRequest("ui/initialize", {
        protocolVersion: "2026-01-26",
        appInfo: {
          name: "codex-mcp-tool-card",
          version: "1.0.0"
        },
        appCapabilities: {}
      });
      hostContext = safeObject(result && result.hostContext) || hostContext;
      if (hostContext && hostContext.theme) applyTheme(hostContext.theme);
      bridgeNotify("ui/notifications/initialized");
    } catch (_error) {
      // ChatGPT compatibility globals still keep the card usable if a host
      // does not expose the complete MCP Apps initialization handshake.
    }
    render();
  }

  strip.addEventListener("click", function () {
    expanded = !expanded;
    persistState();
    render();
  });
  fullscreenButton.addEventListener("click", async function (event) {
    event.stopPropagation();
    try {
      var oa = openai();
      if (oa && typeof oa.requestDisplayMode === "function") await oa.requestDisplayMode({ mode: "fullscreen" });
    } catch (_error) {}
  });

  window.addEventListener("message", function (event) {
    if (event.source !== window.parent) return;
    var message = event.data;
    if (!message || message.jsonrpc !== "2.0") return;
    if (message.id !== undefined && pendingRequests.has(message.id)) {
      var pending = pendingRequests.get(message.id);
      pendingRequests.delete(message.id);
      if (message.error) pending.reject(message.error);
      else pending.resolve(message.result);
      return;
    }
    if (message.method === "ui/notifications/tool-input" || message.method === "ui/notifications/tool-input-partial") {
      var inputParams = safeObject(message.params);
      var nextInput = safeObject(inputParams && inputParams.arguments) || inputParams;
      if (nextInput) {
        latestInput = message.method === "ui/notifications/tool-input-partial"
          ? Object.assign({}, latestInput || {}, nextInput)
          : nextInput;
      }
      render();
      return;
    }
    if (message.method === "ui/notifications/tool-result") {
      latestEnvelope = safeObject(message.params) || latestEnvelope;
      latestStructured = findStructured(message.params) || safeObject(message.params && message.params.structuredContent) || latestStructured;
      latestUiMeta = findUiMeta(message.params) || latestUiMeta;
      render();
    }
  }, { passive: true });

  window.addEventListener("openai:set_globals", function (event) {
    var globals = event && event.detail && event.detail.globals;
    if (!globals) return;
    if (globals.theme) applyTheme(globals.theme);
    applyViewportClass();
    if (safeObject(globals.toolInput)) latestInput = globals.toolInput;
    if (safeObject(globals.toolOutput)) latestStructured = globals.toolOutput;
    if (safeObject(globals.toolResponseMetadata)) {
      latestEnvelope = globals.toolResponseMetadata;
      latestUiMeta = findUiMeta(globals.toolResponseMetadata) || latestUiMeta;
      latestStructured = latestStructured || findStructured(globals.toolResponseMetadata);
    }
    if (isComplete()) stopGlobalsSync();
    else scheduleGlobalsSync();
    render();
  }, { passive: true });

  window.addEventListener("resize", applyViewportClass, { passive: true });
  applyViewportClass();
  readInitialGlobals();
  render();
  initializeBridge();
  scheduleGlobalsSync();
})();
</script>
</body>
</html>''';
}
