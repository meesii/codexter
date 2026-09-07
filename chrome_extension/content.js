(() => {
    const app = globalThis.__codexter_content;
    if (!app || globalThis.__codexter_content_started) return;
    globalThis.__codexter_content_started = true;

    const CONVERSATION_CACHE_KEY = 'codexter.conversationRelations';
    const MAX_CONVERSATIONS = 200;
    let conversation_cache_write = Promise.resolve();

    const service = {
        post_config() {
            app.service.post_page('performance.config', {
                history_trim: app.state.history_trim,
                native_virtual: app.state.native_virtual,
            });
        },

        save_compat(message) {
            return app.service.storage_set({
                [app.config.COMPAT_KEY]: {
                    status: message.status,
                    conversation_id: message.conversation_id ?? app.state.conversation_id,
                    map_hits: Number(message.map_hits) || 0,
                    matched: Number(message.matched) || 0,
                    patched: Number(message.patched) || 0,
                    user_count: Number(message.user_count) || 0,
                    checked_at: Date.now(),
                },
            });
        },

        cache_conversation_relation(relation) {
            if (!relation?.conversationId || !relation?.appId) return Promise.resolve(false);

            conversation_cache_write = conversation_cache_write.then(async () => {
                const values = await chrome.storage.local.get(CONVERSATION_CACHE_KEY);
                const items = Array.isArray(values[CONVERSATION_CACHE_KEY])
                    ? [...values[CONVERSATION_CACHE_KEY]]
                    : [];
                const index = items.findIndex((item) => item?.conversationId === relation.conversationId);
                const now = Date.now();

                if (index >= 0) {
                    const existing = items[index];
                    if (existing.appId && existing.appId !== relation.appId) return false;
                    items[index] = {
                        ...existing,
                        ...relation,
                        appId: existing.appId || relation.appId,
                        title: relation.relationSource === 'history' && relation.title
                            ? relation.title
                            : (existing.title || relation.title || null),
                        cachedAt: existing.cachedAt || now,
                        updatedAt: now,
                    };
                } else {
                    items.unshift({
                        ...relation,
                        cachedAt: now,
                        updatedAt: now,
                    });
                    if (items.length > MAX_CONVERSATIONS) items.length = MAX_CONVERSATIONS;
                }

                await chrome.storage.local.set({ [CONVERSATION_CACHE_KEY]: items });
                console.info('[Codexter][会话缓存] 已保存', {
                    conversationId: relation.conversationId,
                    appId: relation.appId,
                    count: items.length,
                });
                return true;
            }).catch((error) => {
                console.warn('[Codexter][会话缓存] 保存失败', error);
                return false;
            });

            return conversation_cache_write;
        },

        page_message(event) {
            if (event.source !== window || event.data?.source !== app.config.PAGE_SOURCE) return;
            const message = event.data;
            const old_conversation = app.state.conversation_id;
            const old_turn = app.state.turn_id;
            let needs_render = false;

            if (message.conversation_id) app.state.conversation_id = message.conversation_id;
            if (message.turn_id) app.state.turn_id = message.turn_id;
            if (old_conversation !== app.state.conversation_id || old_turn !== app.state.turn_id) needs_render = true;

            if (message.type === 'hook.ready') {
                service.post_config();
                app.service.post_page('content.ready');
                void service.inspect_conversation('hook_ready');
            }
            else if (message.type === 'virtual.compat') void service.save_compat(message);
            else if (message.type === 'connectors.cache') {
                void app.service.runtime_msg({
                    source: app.config.CONTENT_SOURCE,
                    type: 'connectors.cache',
                    connectors: Array.isArray(message.connectors) ? message.connectors : [],
                    refreshedAt: message.refreshedAt ?? Date.now(),
                });
                return;
            } else if (message.type === 'conversation.relation' || message.type === 'conversation.metadata') {
                void service.cache_conversation_relation(message).then(() => app.service.runtime_msg({
                    source: app.config.CONTENT_SOURCE,
                    type: message.type,
                    relation: message,
                }));
                return;
            }

            if (message.type === 'chat.state') {
                const next_status = message.status || app.state.chat_status;
                if (next_status !== app.state.chat_status) {
                    app.state.chat_status = next_status;
                    needs_render = true;
                }
            } else if (message.type === 'chat.completed') {
                app.state.chat_status = 'idle';
                needs_render = true;
                setTimeout(app.action.send_next, 180);
            } else if (message.type === 'composer.result') {
                const resolve = app.runtime.pending_sends.get(message.requestId);
                if (resolve) {
                    app.runtime.pending_sends.delete(message.requestId);
                    resolve({ ok: message.ok === true, error: message.error });
                }
            } else if (message.type === 'composer.stop_result') {
                app.state.notice = message.ok ? '已请求停止当前生成' : message.error || '停止失败';
                needs_render = true;
            }

            app.service.forward_page(message);
            if (needs_render) app.panel.render();
        },

        worker_message(message) {
            if (message?.source !== 'codexter-worker') return;
            if (message.type === 'connectors.refresh') {
                app.service.post_page('connectors.refresh', { reason: message.reason || 'bridge_request' });
                return;
            }
            if (message.type === 'conversation.inspect') {
                app.service.post_page('conversation.inspect', {
                    conversationId: message.conversationId ?? app.state.conversation_id,
                    reason: message.reason || 'worker_request',
                });
                return;
            }
            if (message.type === 'bridge.status') {
                app.state.bridge_connected = message.connected === true;
                app.state.bridge_detail = app.state.bridge_connected ? '' : (message.detail || 'Codexter 未连接');
                app.panel.render();
                return;
            }
            if (message.type === 'bridge.message') {
                const type = message.message?.type;
                if (type === 'bridge.ready' || type === 'bridge.pong') {
                    app.state.bridge_connected = true;
                    app.state.bridge_detail = '';
                    app.panel.render();
                }
            }
        },

        storage_change(changes, area_name) {
            if (area_name !== 'local') return;
            const history_change = changes[app.config.HISTORY_KEY];
            const virtual_change = changes[app.config.VIRTUAL_KEY];
            if (history_change) app.state.history_trim = history_change.newValue !== false;
            if (virtual_change) app.state.native_virtual = virtual_change.newValue !== false;
            if (history_change || virtual_change) service.post_config();
        },

        async inspect_conversation(reason) {
            const conversation_id = app.state.conversation_id || app.service.conversation_id();
            if (!conversation_id) return;
            const cached = await app.service.runtime_msg({
                type: 'conversation.lookup',
                conversationId: conversation_id,
            });
            if (cached?.found) {
                app.service.post_page('conversation.known', { conversationId: conversation_id });
                return;
            }
            app.service.post_page('conversation.inspect', {
                conversationId: conversation_id,
                reason,
            });
        },

        watch_url() {
            if (location.href === app.runtime.last_href) return;
            app.runtime.last_href = location.href;
            app.state.conversation_id = app.service.conversation_id();
            app.state.turn_id = null;
            app.state.chat_status = 'idle';
            void app.action.load_local();
            void service.inspect_conversation('navigation');
            app.service.send_bridge('page.navigated');
        },

        async init() {
            window.addEventListener('message', service.page_message);
            chrome.runtime.onMessage.addListener(service.worker_message);
            chrome.storage.onChanged.addListener(service.storage_change);
            app.service.post_page('content.ready');
            void service.inspect_conversation('page_load');
            setInterval(service.watch_url, 1500);
            setInterval(app.service.sample_perf, app.config.PERF_INTERVAL_MS);

            app.panel.ensure();
            app.service.sample_perf();
            const values = await app.service.storage_get([
                app.config.HISTORY_KEY,
                app.config.VIRTUAL_KEY,
            ]);
            app.state.history_trim = values[app.config.HISTORY_KEY] !== false;
            app.state.native_virtual = values[app.config.VIRTUAL_KEY] !== false;
            const defaults = {};
            if (values[app.config.HISTORY_KEY] === undefined) defaults[app.config.HISTORY_KEY] = true;
            if (values[app.config.VIRTUAL_KEY] === undefined) defaults[app.config.VIRTUAL_KEY] = true;
            if (Object.keys(defaults).length > 0) await app.service.storage_set(defaults);

            await Promise.all([app.action.load_panel(), app.action.load_local()]);
            service.post_config();
            app.panel.render();

            const result = await app.service.runtime_msg({ type: 'bridge.connect' });
            app.state.bridge_connected = result?.connected === true;
            app.state.bridge_detail = app.state.bridge_connected ? '' : 'Codexter 未连接';
            app.panel.render();
            if (app.state.bridge_connected) app.service.send_bridge('page.ready');
        },
    };

    void service.init();
})();
