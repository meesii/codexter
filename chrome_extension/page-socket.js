(() => {
    const app = globalThis.__codexter_page;
    if (!app || app.socket) return;

    const socket = {
        matched_conversations: new Set(),
        relation_cache: new Map(),

        log_frame(direction, data, url) {
            if (globalThis.__CODEXTER_WSS_RAW !== true) return;
            const prefix = `[Codexter][WSS][RAW][${direction}]`;
            if (data instanceof Blob) {
                data.text()
                    .then((text) => console.log(prefix, url ?? '', text))
                    .catch((error) => console.warn(`${prefix}[Blob读取失败]`, error));
                return;
            }
            console.log(prefix, url ?? '', data);
        },

        find_id(value, pattern) {
            if (typeof value !== 'string') return null;
            return value.match(pattern)?.[0] ?? null;
        },

        app_id(value) {
            return socket.find_id(value, /asdk_app_[0-9a-f]+/i);
        },

        link_id(value) {
            return socket.find_id(value, /link_[0-9a-f]+/i);
        },

        record_relation(info) {
            const item = {
                conversationId: info.conversationId ?? app.state.conversation_id ?? null,
                turnId: info.turnId ?? app.state.turn_id ?? null,
                appId: info.appId ?? null,
                linkId: info.linkId ?? null,
                appName: info.appName ?? null,
                title: info.title ?? null,
                gizmoId: info.gizmoId ?? null,
                relationSource: info.relationSource ?? 'wss',
            };
            if (!item.conversationId || !item.appId) return false;
            if (socket.matched_conversations.has(item.conversationId)) return false;

            socket.matched_conversations.add(item.conversationId);
            socket.relation_cache.set(item.conversationId, item);
            console.log('[Codexter][会话关联] 已匹配', item);
            app.service.emit('conversation.relation', item);
            return true;
        },

        replay_relations() {
            for (const item of socket.relation_cache.values()) {
                app.service.emit('conversation.relation', item);
            }
        },

        inspect_message(message, data) {
            if (!message || typeof message !== 'object') return;
            const metadata = message.metadata ?? {};
            const hints = Array.isArray(metadata.system_hints) ? metadata.system_hints.join(' ') : '';
            const resource = metadata.invoked_resource ?? {};
            const resource_uri = typeof resource.resource_uri === 'string' ? resource.resource_uri : '';
            const content_text = typeof message.content?.text === 'string' ? message.content.text : '';
            const searchable = `${hints} ${resource_uri} ${content_text}`;
            const app_id = socket.app_id(searchable);
            const link_id = socket.link_id(searchable);

            if (message.author?.role === 'user' && app_id) {
                const text = Array.isArray(message.content?.parts) ? message.content.parts.join(' ').trim() : '';
                socket.record_relation({
                    conversationId: data.conversation_id ?? message.conversation_id,
                    turnId: data.turn_id ?? data.turn_exchange_id,
                    appId: app_id,
                    title: text || null,
                    relationSource: 'wss:system_hints',
                });
            }

            if (resource_uri) {
                socket.record_relation({
                    conversationId: data.conversation_id ?? message.conversation_id,
                    turnId: data.turn_id ?? data.turn_exchange_id,
                    appId: app_id,
                    linkId: link_id,
                    appName: resource.app_name ?? null,
                    relationSource: 'wss:invoked_resource',
                });
            } else if (message.recipient === 'api_tool.call_tool' && (app_id || link_id)) {
                socket.record_relation({
                    conversationId: data.conversation_id ?? message.conversation_id,
                    turnId: data.turn_id ?? data.turn_exchange_id,
                    appId: app_id,
                    linkId: link_id,
                    relationSource: 'wss:tool_call',
                });
            }
        },

        handle_patch(patch) {
            if (!patch || typeof patch !== 'object') return;
            app.service.update_ids(patch);

            if (typeof patch.p === 'string') app.state.last_patch = patch.p;
            const path = patch.p ?? app.state.last_patch;

            if (patch.o === 'append' && path === '/message/content/parts/0' && typeof patch.v === 'string') {
                app.service.emit('chat.delta', { text: patch.v });
            }
            if (!patch.o && !patch.p && path === '/message/content/parts/0' && typeof patch.v === 'string') {
                app.service.emit('chat.delta', { text: patch.v });
            }
            if (path === '/message/status' && patch.v === 'finished_successfully') {
                app.service.emit('chat.finished', { reason: 'finished_successfully' });
            }
            if (path === '/message/end_turn' && patch.v === true) {
                app.service.emit('chat.finished', { reason: 'end_turn' });
            }
            if (patch.o === 'patch' && Array.isArray(patch.v)) {
                for (const child of patch.v) socket.handle_patch(child);
            }
        },

        handle_inner(data) {
            if (!data || typeof data !== 'object') return;
            app.service.update_ids(data);

            if (data.type === 'message_stream_complete' || data.type === 'done') {
                app.service.complete(data.type);
            }
            if (data.event_type === 'conversation-turn-complete' || data.type === 'conversation-turn-complete') {
                app.service.complete('conversation-turn-complete');
            }

            const message = data?.v?.message ?? data.message ?? data.input_message;
            if (message && typeof message === 'object') {
                app.service.update_ids(message);
                socket.inspect_message(message, data);
                if (message.author?.role === 'assistant' && message.channel === 'final') {
                    app.service.set_status('generating', 'assistant_final');
                }
                if (message.status === 'finished_successfully' || message.end_turn === true) {
                    app.service.emit('chat.finished', {
                        reason: message.end_turn ? 'end_turn' : 'finished_successfully',
                    });
                }
            }
            socket.handle_patch(data);
        },

        parse_item(encoded) {
            if (typeof encoded !== 'string') return;
            for (const line of encoded.split(/\r?\n/)) {
                if (!line.startsWith('data:')) continue;
                const raw = line.slice(5).trim();
                if (!raw) continue;
                if (raw === '[DONE]') {
                    app.service.complete('[DONE]');
                    continue;
                }
                try {
                    const parsed = JSON.parse(raw);
                    if (Array.isArray(parsed)) parsed.forEach(socket.handle_inner);
                    else socket.handle_inner(parsed);
                } catch {}
            }
        },

        walk(data, seen = new WeakSet()) {
            if (!data || typeof data !== 'object' || seen.has(data)) return;
            seen.add(data);
            app.service.update_ids(data);

            if (typeof data.topic === 'string' && data.topic.startsWith('conversation-turn-')) {
                app.state.turn_id = data.topic.slice('conversation-turn-'.length);
                app.service.set_status('generating', 'turn_topic');
            }
            if (typeof data.encoded_item === 'string') socket.parse_item(data.encoded_item);
            if (data.type === 'done') app.service.complete('ws_done');
            if (data.event_type === 'conversation-turn-complete' || data.type === 'conversation-turn-complete') {
                app.service.complete('conversation-turn-complete');
            }

            if (Array.isArray(data)) {
                data.forEach((child) => socket.walk(child, seen));
                return;
            }
            for (const child of Object.values(data)) {
                if (child && typeof child === 'object') socket.walk(child, seen);
            }
        },

        process_data(data) {
            if (typeof data === 'string') {
                try {
                    socket.walk(JSON.parse(data));
                } catch {}
                return;
            }
            if (data instanceof Blob) data.text().then(socket.process_data).catch(() => {});
        },

        install_data() {
            const descriptor = Object.getOwnPropertyDescriptor(MessageEvent.prototype, 'data');
            if (!descriptor?.configurable || typeof descriptor.get !== 'function') return;
            const native_get = descriptor.get;
            const handled = new WeakSet();

            Object.defineProperty(MessageEvent.prototype, 'data', {
                ...descriptor,
                get() {
                    const value = native_get.call(this);
                    try {
                        const target = this.target;
                        if (target instanceof WebSocket && target.url?.includes('ws.chatgpt.com') && !handled.has(this)) {
                            handled.add(this);
                            socket.log_frame('IN', value, target.url);
                            queueMicrotask(() => socket.process_data(value));
                        }
                    } catch {}
                    return value;
                },
            });
        },

        install_send() {
            const native_send = WebSocket.prototype.send;
            WebSocket.prototype.send = function codexter_ws_send(data) {
                try {
                    if (this.url?.includes('ws.chatgpt.com')) {
                        socket.log_frame('OUT', data, this.url);
                        app.service.emit('chat.ws_out', { size: typeof data === 'string' ? data.length : null });
                    }
                } catch {}
                return native_send.call(this, data);
            };
        },

        install() {
            console.info('[Codexter][WSS] 精简日志已启用：每个会话只记录一次关联');
            console.info('[Codexter][WSS] 如需原始帧，在控制台执行：window.__CODEXTER_WSS_RAW = true');
            socket.install_data();
            socket.install_send();
        },
    };

    app.socket = socket;
})();
