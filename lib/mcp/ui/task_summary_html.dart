String buildRoundSummaryHtml() {
    return r'''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<style>
:root {
  color-scheme: light dark;
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  --bg: rgba(255,255,255,.96);
  --panel: rgba(248,248,248,.96);
  --border: rgba(0,0,0,.12);
  --fg: #171717;
  --muted: #737373;
  --accent: #16a34a;
}
:root[data-theme="dark"] {
  --bg: rgba(25,25,25,.97);
  --panel: rgba(18,18,18,.92);
  --border: rgba(255,255,255,.11);
  --fg: #ededed;
  --muted: #a3a3a3;
  --accent: #4ade80;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; width: 100%; background: transparent; color: var(--fg); }
.wrap { width: 100%; padding: 4px 0; }
.card {
  width: 100%;
  padding: 14px 16px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--bg);
}
.head { display: flex; align-items: flex-start; gap: 10px; }
.dot { width: 9px; height: 9px; margin-top: 6px; border-radius: 999px; flex: 0 0 auto; background: var(--accent); }
.main { min-width: 0; flex: 1; }
.label { color: var(--muted); font-size: 11px; line-height: 1.35; margin-bottom: 2px; }
.title { font-size: 14px; line-height: 1.45; font-weight: 650; overflow-wrap: anywhere; }
.summary { margin-top: 9px; font-size: 13px; line-height: 1.6; white-space: pre-wrap; overflow-wrap: anywhere; }
.details { margin: 11px 0 0; padding: 9px 11px 9px 28px; border-radius: 9px; background: var(--panel); }
.details[hidden] { display: none; }
.details li { margin: 3px 0; padding-left: 1px; color: var(--fg); font-size: 12px; line-height: 1.5; overflow-wrap: anywhere; }
.meta { margin-top: 9px; color: var(--muted); font-size: 10px; line-height: 1.4; }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: rgba(25,25,25,.97);
    --panel: rgba(18,18,18,.92);
    --border: rgba(255,255,255,.11);
    --fg: #ededed;
    --muted: #a3a3a3;
    --accent: #4ade80;
  }
}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <div class="head">
      <span id="dot" class="dot"></span>
      <div class="main">
        <div id="label" class="label">本轮处理结束</div>
        <div id="title" class="title">正在整理摘要…</div>
      </div>
    </div>
    <div id="summary" class="summary"></div>
    <ul id="details" class="details" hidden></ul>
    <div id="meta" class="meta"></div>
  </div>
</div>
<script>
(function () {
  "use strict";
  var input = null;
  var output = null;
  var pending = new Map();
  var nextId = 1;

  var dot = document.getElementById("dot");
  var label = document.getElementById("label");
  var title = document.getElementById("title");
  var summary = document.getElementById("summary");
  var details = document.getElementById("details");
  var meta = document.getElementById("meta");

  function oa() {
    try { return window.openai || null; } catch (_error) { return null; }
  }

  function object(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : null;
  }

  function applyTheme(explicit) {
    var theme = explicit;
    if (!theme) {
      try { theme = oa() && oa().theme; } catch (_error) {}
    }
    if (theme === "dark" || theme === "light") document.documentElement.dataset.theme = theme;
  }

  function data() {
    return Object.assign({}, object(input) || {}, object(output) || {});
  }

  function render() {
    var value = data();
    dot.className = "dot";
    label.textContent = "本轮处理结束";
    title.textContent = value.title || "本轮处理结束";
    summary.textContent = value.summary || "";

    details.replaceChildren();
    var list = Array.isArray(value.details) ? value.details : [];
    list.forEach(function (item) {
      var li = document.createElement("li");
      li.textContent = String(item);
      details.append(li);
    });
    details.hidden = list.length === 0;

    var metaParts = [];
    if (value.workspace) metaParts.push(String(value.workspace));
    if (value.endedAt) {
      try { metaParts.push(new Date(value.endedAt).toLocaleString()); }
      catch (_error) { metaParts.push(String(value.endedAt)); }
    }
    meta.textContent = metaParts.join(" · ");
    notifyHeight();
  }

  function readGlobals() {
    var openai = oa();
    if (!openai) return;
    try { input = object(openai.toolInput) || input; } catch (_error1) {}
    try { output = object(openai.toolOutput) || output; } catch (_error2) {}
    applyTheme();
  }

  function notifyHeight() {
    requestAnimationFrame(function () {
      try {
        var openai = oa();
        if (openai && typeof openai.notifyIntrinsicHeight === "function") {
          openai.notifyIntrinsicHeight({ height: Math.ceil(document.documentElement.scrollHeight) });
        }
      } catch (_error) {}
    });
  }

  function request(method, params) {
    if (window.parent === window) return Promise.reject(new Error("host unavailable"));
    var id = nextId++;
    window.parent.postMessage({ jsonrpc: "2.0", id: id, method: method, params: params }, "*");
    return new Promise(function (resolve, reject) {
      pending.set(id, { resolve: resolve, reject: reject });
      setTimeout(function () {
        var item = pending.get(id);
        if (!item) return;
        pending.delete(id);
        reject(new Error("host timeout"));
      }, 30000);
    });
  }

  function notify(method, params) {
    if (window.parent === window) return;
    var message = { jsonrpc: "2.0", method: method };
    if (params !== undefined) message.params = params;
    window.parent.postMessage(message, "*");
  }

  async function initialize() {
    try {
      var result = await request("ui/initialize", {
        protocolVersion: "2026-01-26",
        appInfo: { name: "codexter-round-summary", version: "1.0.0" },
        appCapabilities: {}
      });
      if (result && result.hostContext && result.hostContext.theme) applyTheme(result.hostContext.theme);
      notify("ui/notifications/initialized");
    } catch (_error) {}
    readGlobals();
    render();
  }

  window.addEventListener("message", function (event) {
    if (event.source !== window.parent) return;
    var message = event.data;
    if (!message || message.jsonrpc !== "2.0") return;

    if (message.id !== undefined && pending.has(message.id)) {
      var item = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) item.reject(message.error); else item.resolve(message.result);
      return;
    }

    if (message.method === "ui/notifications/tool-input" || message.method === "ui/notifications/tool-input-partial") {
      var params = object(message.params);
      var nextInput = object(params && params.arguments) || params;
      if (nextInput) input = message.method.endsWith("partial") ? Object.assign({}, input || {}, nextInput) : nextInput;
      render();
      return;
    }

    if (message.method === "ui/notifications/tool-result") {
      var params = object(message.params) || {};
      output = object(params.structuredContent) || output;
      render();
    }
  }, { passive: true });

  window.addEventListener("openai:set_globals", function (event) {
    var globals = event && event.detail && event.detail.globals;
    if (!globals) return;
    if (globals.theme) applyTheme(globals.theme);
    if (object(globals.toolInput)) input = globals.toolInput;
    if (object(globals.toolOutput)) output = globals.toolOutput;
    render();
  }, { passive: true });

  readGlobals();
  render();
  initialize();
})();
</script>
</body>
</html>''';
}
