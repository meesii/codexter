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
}
:root[data-theme="dark"] {
  --bg: rgba(25,25,25,.97);
  --panel: rgba(18,18,18,.92);
  --border: rgba(255,255,255,.11);
  --fg: #ededed;
  --muted: #a3a3a3;
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
.head { display: flex; align-items: center; gap: 10px; }
.logo { width: 26px; height: 26px; flex: 0 0 auto; object-fit: contain; }
.main { min-width: 0; flex: 1; }
.title { font-size: 14px; line-height: 1.45; font-weight: 650; overflow-wrap: anywhere; }
.summary { margin-top: 9px; font-size: 13px; line-height: 1.6; white-space: normal; overflow-wrap: anywhere; }
.meta { margin-top: 9px; color: var(--muted); font-size: 10px; line-height: 1.4; }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: rgba(25,25,25,.97);
    --panel: rgba(18,18,18,.92);
    --border: rgba(255,255,255,.11);
    --fg: #ededed;
    --muted: #a3a3a3;
  }
}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <div class="head">
      <img class="logo" alt="CodexMCP" src="data:image/png;base64,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" />
      <div class="main">
        <div id="title" class="title"></div>
      </div>
    </div>
    <div id="summary" class="summary"></div>
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

  var title = document.getElementById("title");
  var summary = document.getElementById("summary");
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
    title.textContent = value.title || "";
    summary.textContent = value.summary || "";

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
