(() => {
    const app = globalThis.__codexter_content;
    if (!app || app.panel) return;

    const panel = {
        host: null,
        shadow: null,

        visible() {
            if (!panel.shadow) return null;
            return panel.shadow.getElementById(app.state.expanded ? 'panel' : 'collapsed-bar');
        },

        clamp_size(pos_x, pos_y, width, height) {
            const margin = 8;
            return {
                x: Math.min(Math.max(margin, pos_x), Math.max(margin, window.innerWidth - width - margin)),
                y: Math.min(Math.max(margin, pos_y), Math.max(margin, window.innerHeight - height - margin)),
            };
        },

        clamp_pos(pos_x, pos_y) {
            const rect = panel.visible()?.getBoundingClientRect();
            const width = rect?.width > 0 ? rect.width : (app.state.expanded ? 360 : 280);
            const height = rect?.height > 0 ? rect.height : (app.state.expanded ? 420 : 44);
            return panel.clamp_size(pos_x, pos_y, width, height);
        },

        expand_dir(rect) {
            return rect.top + rect.height / 2 <= window.innerHeight / 2 ? 'down' : 'up';
        },

        horizontal(rect) {
            return rect.left + rect.width / 2 <= window.innerWidth / 2 ? 'left' : 'right';
        },

        place(anchor_rect, surface, direction, horizontal) {
            const rect = surface.getBoundingClientRect();
            const pos_x = horizontal === 'right' ? anchor_rect.right - rect.width : anchor_rect.left;
            const pos_y = direction === 'up' ? anchor_rect.bottom - rect.height : anchor_rect.top;
            app.state.panel_pos = panel.clamp_size(pos_x, pos_y, rect.width, rect.height);
            panel.apply_pos();
        },

        apply_pos() {
            if (!panel.host) return;
            if (!app.state.panel_pos) {
                panel.host.style.left = '';
                panel.host.style.top = '';
                panel.host.style.right = '18px';
                panel.host.style.bottom = '18px';
                return;
            }
            const point = panel.clamp_pos(app.state.panel_pos.x, app.state.panel_pos.y);
            app.state.panel_pos = point;
            panel.host.style.right = '';
            panel.host.style.bottom = '';
            panel.host.style.left = `${point.x}px`;
            panel.host.style.top = `${point.y}px`;
        },

        begin_drag(event) {
            if (event.button !== 0 || event.target.closest('button, input, textarea')) return;
            event.preventDefault();
            const rect = panel.host.getBoundingClientRect();
            const start_x = event.clientX;
            const start_y = event.clientY;
            const origin_x = rect.left;
            const origin_y = rect.top;
            let moved = false;

            const on_move = (move_event) => {
                const delta_x = move_event.clientX - start_x;
                const delta_y = move_event.clientY - start_y;
                if (Math.abs(delta_x) + Math.abs(delta_y) > 4) moved = true;
                app.state.panel_pos = panel.clamp_pos(origin_x + delta_x, origin_y + delta_y);
                panel.apply_pos();
            };
            const on_up = async () => {
                window.removeEventListener('pointermove', on_move, true);
                window.removeEventListener('pointerup', on_up, true);
                if (moved) await app.action.save_panel();
            };

            window.addEventListener('pointermove', on_move, true);
            window.addEventListener('pointerup', on_up, true);
        },

        async set_expanded(expanded) {
            if (app.state.expanded === expanded || !panel.shadow) return;
            const outgoing = panel.visible();
            if (!outgoing) return;
            const anchor_rect = outgoing.getBoundingClientRect();
            const direction = panel.expand_dir(anchor_rect);
            const horizontal = panel.horizontal(anchor_rect);

            app.state.expanded = expanded;
            panel.render(true);
            const target = panel.shadow.getElementById(expanded ? 'panel' : 'collapsed-bar');
            panel.place(anchor_rect, target, direction, horizontal);
            await app.action.save_panel();
        },

        async reconnect() {
            app.state.bridge_detail = '正在连接…';
            panel.render();
            const result = await app.service.runtime_msg({ type: 'bridge.connect' });
            app.state.bridge_connected = result?.connected === true;
            app.state.bridge_detail = app.state.bridge_connected ? '' : '连接失败';
            panel.render();
            if (app.state.bridge_connected) app.service.send_bridge('page.ready');
        },

        template() {
            return `
                <style>
                    * { box-sizing:border-box; }
                    :host { all:initial; }
                    [hidden] { display:none !important; }
                    .root { width:max-content; font-family:ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; color:#e7e9ee; pointer-events:auto; }
                    .root, .root *:not(input):not(textarea) { user-select:none; -webkit-user-select:none; }
                    svg, img, a { -webkit-user-drag:none; }
                    .collapsed { width:max-content; max-width:calc(100vw - 16px); height:44px; display:flex; align-items:center; gap:9px; padding:0 13px; border:1px solid rgba(255,255,255,.12); background:rgba(24,26,31,.96); box-shadow:0 10px 30px rgba(0,0,0,.24); border-radius:12px; cursor:grab; }
                    .collapsed:active, .drag-handle:active { cursor:grabbing; }
                    .collapsed-main { min-width:0; flex:none; display:flex; align-items:center; gap:9px; overflow:hidden; }
                    .metric { min-width:0; height:18px; display:inline-flex; align-items:center; gap:3px; white-space:nowrap; font-size:10px; line-height:1; color:#8f96a3; font-variant-numeric:tabular-nums; }
                    .metric svg { width:12px; height:12px; display:block; flex:0 0 12px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
                    .metric > span { display:block; line-height:12px; }
                    .metric-value { color:#c8cdd6; font-weight:600; }
                    .metric.queue-metric { color:#79a8ff; }
                    .metric.memory { color:#e5b567; }
                    .metric.dom { color:#a58af4; }
                    .metric .metric-value { color:#cfd4dc; }
                    .metric.queue-metric .metric-value { min-width:2ch; }
                    .metric.memory .metric-value { min-width:46px; }
                    .metric.dom .metric-value { min-width:32px; }
                    .dot { width:7px; height:7px; border-radius:50%; background:#6f7580; flex:none; }
                    .dot.on { background:#55c989; }
                    .panel { width:360px; border:1px solid rgba(255,255,255,.12); background:rgba(22,24,29,.97); box-shadow:0 16px 44px rgba(0,0,0,.3); border-radius:14px; overflow:hidden; backdrop-filter:blur(18px); }
                    .header { min-height:48px; display:flex; align-items:center; gap:9px; padding:0 11px; border-bottom:1px solid rgba(255,255,255,.08); }
                    .drag-handle { min-width:0; flex:1; cursor:grab; }
                    .header-row { display:flex; align-items:center; gap:7px; }
                    .title { font-size:13px; font-weight:700; color:#f0f2f6; }
                    .sub { margin-top:2px; font-size:10px; color:#858c99; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
                    .pill { display:inline-flex; align-items:center; height:20px; padding:0 7px; border-radius:999px; background:rgba(255,255,255,.06); font-size:10px; color:#aeb4bf; }
                    .body { padding:11px; }
                    .status-row { display:flex; align-items:center; gap:8px; min-height:25px; margin-bottom:9px; }
                    .status-text { flex:1; min-width:0; font-size:10px; color:#9ca3af; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
                    button { border:0; border-radius:8px; height:30px; padding:0 10px; background:rgba(255,255,255,.09); color:#e8ebf1; cursor:pointer; font:inherit; font-size:11px; white-space:nowrap; }
                    button:hover { background:rgba(255,255,255,.15); }
                    button.primary { background:#e7e9ee; color:#17191e; font-weight:650; }
                    button:disabled { opacity:.42; cursor:default; }
                    .icon-btn { width:29px; min-width:29px; height:29px; padding:0; display:inline-flex; align-items:center; justify-content:center; }
                    .icon-btn svg { width:15px; height:15px; display:block; fill:none; stroke:currentColor; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; pointer-events:none; }
                    textarea { width:100%; min-height:64px; max-height:124px; resize:vertical; padding:9px 10px; border:1px solid rgba(255,255,255,.11); outline:none; background:rgba(255,255,255,.055); color:#edf0f5; border-radius:9px; font:inherit; font-size:12px; line-height:1.45; user-select:text; -webkit-user-select:text; }
                    .actions { display:flex; gap:7px; margin-top:8px; }
                    .grow { flex:1; }
                    .queue { display:flex; flex-direction:column; gap:5px; max-height:96px; margin-top:8px; overflow-y:auto; overflow-x:hidden; scrollbar-width:thin; }
                    .queue-row { display:flex; align-items:center; gap:7px; padding:6px 7px; border-radius:8px; background:rgba(255,255,255,.045); font-size:11px; }
                    .queue-text { flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; color:#cbd0d9; }
                    .empty { padding:8px 0 3px; color:#757d8a; font-size:10px; text-align:center; }
                    .notice { min-height:14px; margin-top:6px; font-size:10px; color:#89919f; }
                </style>
                <div class="root">
                    <div class="collapsed" id="collapsed-bar" hidden>
                        <span class="dot" id="collapsed-dot"></span>
                        <div class="collapsed-main">
                            <span class="metric queue-metric"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="5" width="4" height="4" rx="1"/><path d="M11 7h9"/><rect x="4" y="15" width="4" height="4" rx="1"/><path d="M11 17h9"/></svg><span>队列</span><span class="metric-value" id="queue-value">0</span></span>
                            <span class="metric memory"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="7" y="7" width="10" height="10" rx="2"/><path d="M9 2v3"/><path d="M15 2v3"/><path d="M9 19v3"/><path d="M15 19v3"/><path d="M2 9h3"/><path d="M2 15h3"/><path d="M19 9h3"/><path d="M19 15h3"/></svg><span>JS</span><span class="metric-value" id="memory-value">--</span></span>
                            <span class="metric dom"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="9" y="14" width="6" height="6" rx="1"/><path d="M7 10v2h10v-2"/><path d="M12 12v2"/></svg><span>DOM</span><span class="metric-value" id="dom-value">--</span></span>
                        </div>
                        <button class="icon-btn" id="expand" title="展开" aria-label="展开面板"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 15 6-6 6 6"/></svg></button>
                    </div>
                    <section class="panel" id="panel" hidden>
                        <div class="header">
                            <div class="drag-handle" id="drag-handle">
                                <div class="header-row"><span class="dot" id="bridge-dot"></span><span class="title">Codexter</span><span class="pill" id="chat-status">idle</span></div>
                                <div class="sub" id="conversation"></div>
                            </div>
                            <button class="icon-btn" id="collapse" title="收起" aria-label="收起面板"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg></button>
                        </div>
                        <div class="body">
                            <div class="status-row"><span class="status-text" id="bridge-text">Codexter 未连接</span><button id="reconnect">重连</button></div>
                            <textarea id="message-input" placeholder="提前输入要发送给 ChatGPT 的内容"></textarea>
                            <div class="actions"><button class="primary grow" id="send-now">立即发送</button><button class="grow" id="enqueue">加入队列</button></div>
                            <div class="queue" id="queue"></div><div class="notice" id="notice"></div>
                        </div>
                    </section>
                </div>`;
        },

        bind_events() {
            const shadow = panel.shadow;
            shadow.getElementById('collapsed-bar').addEventListener('pointerdown', panel.begin_drag);
            shadow.getElementById('drag-handle').addEventListener('pointerdown', panel.begin_drag);
            shadow.getElementById('expand').addEventListener('click', () => void panel.set_expanded(true));
            shadow.getElementById('collapse').addEventListener('click', () => void panel.set_expanded(false));
            shadow.getElementById('reconnect').addEventListener('click', () => void panel.reconnect());
            shadow.getElementById('send-now').addEventListener('click', async () => {
                const input = shadow.getElementById('message-input');
                const result = await app.action.send_now(input.value);
                if (result.ok) input.value = '';
            });
            shadow.getElementById('enqueue').addEventListener('click', async () => {
                const input = shadow.getElementById('message-input');
                const text = input.value.trim();
                if (!text) return;
                input.value = '';
                await app.action.enqueue(text);
            });
            window.addEventListener('resize', () => {
                if (!app.state.panel_pos) return;
                app.state.panel_pos = panel.clamp_pos(app.state.panel_pos.x, app.state.panel_pos.y);
                panel.apply_pos();
                void app.action.save_panel();
            });
        },

        ensure() {
            if (panel.shadow) return;
            panel.host = document.createElement('div');
            panel.host.id = 'codexter-browser-panel-host';
            panel.host.style.cssText = 'position:fixed;right:18px;bottom:18px;z-index:2147483646;pointer-events:none;';
            (document.documentElement || document).appendChild(panel.host);
            panel.shadow = panel.host.attachShadow({ mode: 'open' });
            panel.shadow.innerHTML = panel.template();
            panel.bind_events();
            panel.apply_pos();
        },

        render_queue() {
            const container = panel.shadow.getElementById('queue');
            container.replaceChildren();
            if (app.state.queue.length === 0) {
                const empty = document.createElement('div');
                empty.className = 'empty';
                empty.textContent = '消息队列为空';
                container.appendChild(empty);
                return;
            }
            for (const item of app.state.queue) {
                const row = document.createElement('div');
                row.className = 'queue-row';
                const text = document.createElement('div');
                text.className = 'queue-text';
                text.textContent = item.text;
                const remove = document.createElement('button');
                remove.className = 'icon-btn';
                remove.textContent = '×';
                remove.addEventListener('click', async () => {
                    app.state.queue = app.state.queue.filter((entry) => entry.id !== item.id);
                    await app.action.save_queue();
                    panel.render();
                });
                row.append(text, remove);
                container.appendChild(row);
            }
        },

        format_memory(bytes) {
            if (!Number.isFinite(bytes) || bytes <= 0) return '--';
            return `${Math.round(bytes / 1048576)} MB`;
        },

        format_count(count) {
            if (!Number.isFinite(count) || count <= 0) return '--';
            if (count < 1000) return String(Math.round(count));
            if (count < 1000000) return `${(count / 1000).toFixed(1)}K`;
            return `${(count / 1000000).toFixed(1)}M`;
        },

        render_summary() {
            if (!panel.shadow) return;
            panel.shadow.getElementById('queue-value').textContent = String(app.state.queue.length);
            panel.shadow.getElementById('memory-value').textContent = panel.format_memory(app.state.memory_bytes);
            panel.shadow.getElementById('dom-value').textContent = panel.format_count(app.state.dom_nodes);
        },

        render(skip_pos = false) {
            panel.ensure();
            const content = panel.shadow.getElementById('panel');
            const bar = panel.shadow.getElementById('collapsed-bar');
            content.hidden = !app.state.expanded;
            bar.hidden = app.state.expanded;
            if (!skip_pos) panel.apply_pos();

            panel.shadow.getElementById('conversation').textContent = `会话 ${app.service.short_id(app.state.conversation_id)}`;
            panel.shadow.getElementById('chat-status').textContent = app.state.chat_status;
            panel.shadow.getElementById('bridge-dot').classList.toggle('on', app.state.bridge_connected);
            panel.shadow.getElementById('collapsed-dot').classList.toggle('on', app.state.bridge_connected);
            panel.shadow.getElementById('bridge-text').textContent = app.state.bridge_connected
                ? 'Codexter 已连接'
                : (app.state.bridge_detail || 'Codexter 未连接');
            panel.shadow.getElementById('reconnect').hidden = app.state.bridge_connected;

            panel.render_summary();
            panel.shadow.getElementById('notice').textContent = app.state.notice;
            panel.shadow.getElementById('send-now').disabled = app.state.chat_status === 'generating' || app.state.chat_status === 'sending';
            panel.render_queue();
        },
    };

    app.panel = panel;
})();
