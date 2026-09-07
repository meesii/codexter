(() => {
    if (globalThis.__codexter_content) return;

    const config = {
        PAGE_SOURCE: 'codexter-page',
        CONTENT_SOURCE: 'codexter-content',
        PANEL_KEY: 'codexter.panel.state',
        HISTORY_KEY: 'codexter.trimHistoricalConversation',
        VIRTUAL_KEY: 'codexter.nativeTurnVirtualization',
        COMPAT_KEY: 'codexter.nativeVirtualizationCompatibility',
        DELTA_INTERVAL_MS: 50,
        PERF_INTERVAL_MS: 2000,
    };

    const state = {
        bridge_connected: false,
        bridge_detail: '',
        chat_status: 'idle',
        conversation_id: null,
        turn_id: null,
        queue: [],
        sending_queue: false,
        notice: '',
        expanded: false,
        panel_pos: null,
        history_trim: true,
        native_virtual: true,
        memory_bytes: null,
        dom_nodes: 0,
    };

    const runtime = {
        pending_sends: new Map(),
        last_href: location.href,
        delta_event: null,
        delta_text: '',
        delta_timer: null,
    };

    const service = {
        conversation_id() {
            return location.pathname.match(/\/c\/([0-9a-f-]{20,})/i)?.[1] ?? null;
        },

        short_id(val) {
            if (!val) return '新会话';
            return val.length > 18 ? `${val.slice(0, 8)}…${val.slice(-6)}` : val;
        },

        storage_keys() {
            const id = state.conversation_id || 'new-chat';
            return {
                queue: `codexter.queue.${id}`,
            };
        },

        context_ok() {
            try {
                return Boolean(chrome?.runtime?.id);
            } catch {
                return false;
            }
        },

        async storage_get(keys) {
            if (!service.context_ok()) return {};
            try {
                return await chrome.storage.local.get(keys);
            } catch {
                return {};
            }
        },

        async storage_set(data) {
            if (!service.context_ok()) return false;
            try {
                await chrome.storage.local.set(data);
                return true;
            } catch {
                return false;
            }
        },

        async runtime_msg(data) {
            if (!service.context_ok()) return null;
            try {
                return await chrome.runtime.sendMessage(data);
            } catch {
                return null;
            }
        },

        post_page(type, data = {}) {
            window.postMessage({ source: config.CONTENT_SOURCE, type, ...data }, '*');
        },

        send_bridge(type, data = {}) {
            void service.runtime_msg({
                source: config.CONTENT_SOURCE,
                type,
                conversationId: state.conversation_id,
                turnId: state.turn_id,
                ...data,
            });
        },

        sample_perf() {
            const memory = performance.memory;
            state.memory_bytes = Number.isFinite(memory?.usedJSHeapSize) ? memory.usedJSHeapSize : null;
            state.dom_nodes = document.getElementsByTagName('*').length;
            app.panel?.render_summary();
        },

        flush_delta() {
            if (runtime.delta_timer) {
                clearTimeout(runtime.delta_timer);
                runtime.delta_timer = null;
            }
            if (!runtime.delta_event || !runtime.delta_text) return;
            service.send_bridge('page.event', {
                event: { ...runtime.delta_event, text: runtime.delta_text },
            });
            runtime.delta_event = null;
            runtime.delta_text = '';
        },

        forward_page(message) {
            if (message.type === 'chat.delta' && typeof message.text === 'string') {
                runtime.delta_event = message;
                runtime.delta_text += message.text;
                if (!runtime.delta_timer) {
                    runtime.delta_timer = setTimeout(service.flush_delta, config.DELTA_INTERVAL_MS);
                }
                return;
            }
            service.flush_delta();
            service.send_bridge('page.event', { event: message });
        },
    };

    const action = {
        async load_panel() {
            const values = await service.storage_get(config.PANEL_KEY);
            const saved = values[config.PANEL_KEY];
            if (saved && typeof saved === 'object') {
                state.expanded = saved.expanded === true;
                if (Number.isFinite(saved.x) && Number.isFinite(saved.y)) {
                    state.panel_pos = { x: saved.x, y: saved.y };
                }
            }
            app.panel?.apply_pos();
            app.panel?.render();
        },

        async save_panel() {
            await service.storage_set({
                [config.PANEL_KEY]: {
                    expanded: state.expanded,
                    x: state.panel_pos?.x ?? null,
                    y: state.panel_pos?.y ?? null,
                },
            });
        },

        async load_local() {
            const keys = service.storage_keys();
            const values = await service.storage_get(keys.queue);
            state.queue = Array.isArray(values[keys.queue]) ? values[keys.queue] : [];
            app.panel?.render();
        },

        async save_queue() {
            const keys = service.storage_keys();
            await service.storage_set({ [keys.queue]: state.queue });
        },

        request_send(text) {
            return new Promise((resolve) => {
                const req_id = crypto.randomUUID();
                const timer = setTimeout(() => {
                    runtime.pending_sends.delete(req_id);
                    resolve({ ok: false, error: '发送请求超时' });
                }, 3500);
                runtime.pending_sends.set(req_id, (result) => {
                    clearTimeout(timer);
                    resolve(result);
                });
                service.post_page('composer.send', { requestId: req_id, text });
            });
        },

        async send_now(text) {
            const value = String(text ?? '').trim();
            if (!value) return { ok: false, error: '请输入消息' };
            if (state.chat_status === 'generating' || state.chat_status === 'sending') {
                return { ok: false, error: '当前对话还没有结束' };
            }
            const result = await action.request_send(value);
            state.notice = result.ok ? '已发送' : result.error || '发送失败';
            app.panel?.render();
            return result;
        },

        async enqueue(text) {
            const value = String(text ?? '').trim();
            if (!value) return;
            state.queue.push({ id: crypto.randomUUID(), text: value, createdAt: Date.now() });
            await action.save_queue();
            app.panel?.render();
            if (state.chat_status === 'idle') setTimeout(action.send_next, 80);
        },

        async send_next() {
            if (state.sending_queue || state.chat_status !== 'idle' || state.queue.length === 0) return;
            state.sending_queue = true;
            const item = state.queue[0];
            const result = await action.send_now(item.text);
            if (result.ok) {
                state.queue.shift();
                await action.save_queue();
            }
            state.sending_queue = false;
            app.panel?.render();
        },

    };

    const app = {
        config,
        state,
        runtime,
        service,
        action,
        panel: null,
    };

    state.conversation_id = service.conversation_id();
    globalThis.__codexter_content = app;
})();
