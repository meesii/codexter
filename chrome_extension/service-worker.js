const config = {
    BRIDGE_URL: 'ws://127.0.0.1:17616/browser',
    BRIDGE_PROTOCOL: 'codexter-poc-v1',
    PING_INTERVAL_MS: 20000,
    CONNECT_TIMEOUT_MS: 2500,
    SESSION_CACHE_KEY: 'codexter.browserBridgeCache',
    CONVERSATION_CACHE_KEY: 'codexter.conversationRelations',
    MAX_CONVERSATIONS: 200,
};

const state = {
    socket: null,
    tabs: new Set(),
    ping_timer: null,
    connector_cache: [],
    connector_refreshed_at: null,
    pending_connector_request_id: null,
    conversation_cache: [],
    cache_ready: null,
};

const service = {
    broadcast(message) {
        for (const tab_id of [...state.tabs]) {
            chrome.tabs.sendMessage(tab_id, message).catch(() => state.tabs.delete(tab_id));
        }
    },

    send_socket(message) {
        if (state.socket?.readyState !== WebSocket.OPEN) return false;
        state.socket.send(JSON.stringify(message));
        return true;
    },

    connector_result(request_id = null) {
        return {
            type: 'connectors.result',
            requestId: request_id,
            connectors: state.connector_cache,
            refreshedAt: state.connector_refreshed_at,
        };
    },

    conversation_result(request_id = null) {
        return {
            type: 'conversations.result',
            requestId: request_id,
            conversations: state.conversation_cache,
        };
    },

    snapshot_result() {
        return {
            connected: state.socket?.readyState === WebSocket.OPEN,
            connectors: state.connector_cache,
            connectorRefreshedAt: state.connector_refreshed_at,
            conversations: state.conversation_cache,
        };
    },

    connector_for(app_id) {
        return state.connector_cache.find((item) => item.appId === app_id) ?? null;
    },

    enrich_relation(relation) {
        const connector = service.connector_for(relation.appId);
        return {
            conversationId: relation.conversationId,
            appId: relation.appId,
            linkId: relation.linkId ?? null,
            appName: relation.appName ?? connector?.name ?? null,
            title: relation.title ?? null,
            gizmoId: relation.gizmoId ?? null,
            workspaceUuid: connector?.workspaceUuid ?? relation.workspaceUuid ?? null,
            baseUrl: connector?.baseUrl ?? relation.baseUrl ?? null,
            relationSource: relation.relationSource ?? 'unknown',
            matchedAt: relation.matchedAt ?? Date.now(),
        };
    },

    async persist_cache() {
        try {
            await Promise.all([
                chrome.storage.session.set({
                    [config.SESSION_CACHE_KEY]: {
                        connectors: state.connector_cache,
                        connectorRefreshedAt: state.connector_refreshed_at,
                        conversations: state.conversation_cache,
                    },
                }),
                chrome.storage.local.set({
                    [config.CONVERSATION_CACHE_KEY]: state.conversation_cache,
                }),
            ]);
        } catch {}
    },

    async restore_cache() {
        try {
            const [session_values, local_values] = await Promise.all([
                chrome.storage.session.get(config.SESSION_CACHE_KEY),
                chrome.storage.local.get(config.CONVERSATION_CACHE_KEY),
            ]);
            const saved = session_values?.[config.SESSION_CACHE_KEY];
            if (saved && typeof saved === 'object') {
                state.connector_cache = Array.isArray(saved.connectors) ? saved.connectors : [];
                state.connector_refreshed_at = saved.connectorRefreshedAt ?? null;
            }

            const session_conversations = Array.isArray(saved?.conversations) ? saved.conversations : [];
            const local_conversations = Array.isArray(local_values?.[config.CONVERSATION_CACHE_KEY])
                ? local_values[config.CONVERSATION_CACHE_KEY]
                : [];
            const merged = new Map();
            for (const item of [...session_conversations, ...local_conversations]) {
                if (!item?.conversationId || !item?.appId) continue;
                merged.set(item.conversationId, {
                    ...(merged.get(item.conversationId) ?? {}),
                    ...item,
                });
            }
            state.conversation_cache = [...merged.values()].slice(0, config.MAX_CONVERSATIONS);
        } catch {}
    },

    update_conversation_cache(message) {
        const relation = message?.relation;
        if (!relation?.conversationId || !relation?.appId) return false;

        const index = state.conversation_cache.findIndex((item) => item.conversationId === relation.conversationId);
        if (index >= 0) {
            const existing = state.conversation_cache[index];
            if (existing.appId !== relation.appId) {
                console.warn('[Codexter][Cache] 会话已绑定其它 appId，忽略重复匹配', {
                    conversationId: relation.conversationId,
                    existingAppId: existing.appId,
                    ignoredAppId: relation.appId,
                });
                return false;
            }
            state.conversation_cache[index] = service.enrich_relation({
                ...relation,
                ...existing,
                title: relation.relationSource === 'history' && relation.title ? relation.title : (existing.title || relation.title || null),
                linkId: existing.linkId || relation.linkId || null,
                appName: existing.appName || relation.appName || null,
                gizmoId: existing.gizmoId || relation.gizmoId || null,
            });
            void service.persist_cache();
            return false;
        }

        const item = service.enrich_relation(relation);
        state.conversation_cache.unshift(item);
        if (state.conversation_cache.length > config.MAX_CONVERSATIONS) {
            state.conversation_cache.length = config.MAX_CONVERSATIONS;
        }
        console.log('[Codexter][Cache] 新增会话关联', item);
        void service.persist_cache();
        service.send_socket({ type: 'conversation.matched', conversation: item });
        return true;
    },

    refresh_connectors(request_id = null) {
        state.pending_connector_request_id = request_id;
        const tab_id = [...state.tabs][0];
        if (!Number.isInteger(tab_id)) {
            service.send_socket(service.connector_result(request_id));
            state.pending_connector_request_id = null;
            return false;
        }
        chrome.tabs.sendMessage(tab_id, {
            source: 'codexter-worker',
            type: 'connectors.refresh',
            reason: 'bridge_request',
        }).catch(() => state.tabs.delete(tab_id));
        return true;
    },

    update_connector_cache(message) {
        state.connector_cache = Array.isArray(message.connectors) ? message.connectors : [];
        state.connector_refreshed_at = message.refreshedAt ?? Date.now();
        state.conversation_cache = state.conversation_cache.map((item) => service.enrich_relation(item));
        void service.persist_cache();
        const request_id = state.pending_connector_request_id;
        if (request_id != null) {
            service.send_socket(service.connector_result(request_id));
            state.pending_connector_request_id = null;
        }
    },

    inspect_known_tabs(reason = 'worker_request') {
        for (const tab_id of [...state.tabs]) {
            chrome.tabs.sendMessage(tab_id, {
                source: 'codexter-worker',
                type: 'conversation.inspect',
                reason,
            }).catch(() => state.tabs.delete(tab_id));
        }
    },

    set_status(connected, detail = null) {
        service.broadcast({
            source: 'codexter-worker',
            type: 'bridge.status',
            connected,
            detail,
        });
    },

    stop_ping() {
        clearInterval(state.ping_timer);
        state.ping_timer = null;
    },

    start_ping() {
        service.stop_ping();
        state.ping_timer = setInterval(() => {
            if (state.socket?.readyState === WebSocket.OPEN) {
                state.socket.send(JSON.stringify({ type: 'bridge.ping' }));
            }
        }, config.PING_INTERVAL_MS);
    },

    wait_connect() {
        return new Promise((resolve) => {
            const started_at = Date.now();
            const timer = setInterval(() => {
                if (state.socket?.readyState === WebSocket.OPEN) {
                    clearInterval(timer);
                    resolve(true);
                    return;
                }
                const stopped = !state.socket || state.socket.readyState === WebSocket.CLOSED;
                if (stopped || Date.now() - started_at > config.CONNECT_TIMEOUT_MS) {
                    clearInterval(timer);
                    resolve(false);
                }
            }, 50);
        });
    },

    connect() {
        if (state.socket?.readyState === WebSocket.OPEN) return Promise.resolve(true);
        if (state.socket?.readyState === WebSocket.CONNECTING) return service.wait_connect();

        return new Promise((resolve) => {
            let settled = false;
            const finish = (value) => {
                if (settled) return;
                settled = true;
                resolve(value);
            };

            try {
                state.socket = new WebSocket(config.BRIDGE_URL, config.BRIDGE_PROTOCOL);
            } catch (error) {
                state.socket = null;
                service.set_status(false, String(error));
                finish(false);
                return;
            }

            const timeout = setTimeout(() => {
                if (state.socket?.readyState === WebSocket.OPEN) return;
                try {
                    state.socket?.close();
                } catch {}
                state.socket = null;
                service.set_status(false, 'Codexter 连接超时');
                finish(false);
            }, config.CONNECT_TIMEOUT_MS);

            state.socket.onopen = () => {
                clearTimeout(timeout);
                service.set_status(true);
                service.start_ping();
                finish(true);
            };

            state.socket.onmessage = (event) => {
                let message;
                try {
                    message = JSON.parse(event.data);
                } catch {
                    return;
                }
                if (message?.type === 'connectors.get') {
                    const has_cache = state.connector_cache.length > 0;
                    if (has_cache && message.forceRefresh !== true) {
                        service.send_socket(service.connector_result(message.requestId ?? null));
                    } else {
                        service.refresh_connectors(message.requestId ?? null);
                    }
                    return;
                }
                if (message?.type === 'conversations.get') {
                    service.send_socket(service.conversation_result(message.requestId ?? null));
                    if (state.conversation_cache.length === 0 || message.forceRefresh === true) {
                        service.inspect_known_tabs('bridge_request');
                    }
                    return;
                }
                service.broadcast({
                    source: 'codexter-worker',
                    type: 'bridge.message',
                    message,
                });
            };

            state.socket.onerror = () => {
                service.set_status(false, 'WebSocket error');
            };

            state.socket.onclose = () => {
                clearTimeout(timeout);
                state.socket = null;
                service.stop_ping();
                service.set_status(false, 'Codexter 未连接');
                finish(false);
            };
        });
    },

    disconnect() {
        service.stop_ping();
        if (state.socket) {
            try {
                state.socket.close();
            } catch {}
            state.socket = null;
        }
        service.set_status(false, 'Codexter 未连接');
    },

    send(message, sender) {
        const tab_id = sender.tab?.id;
        if (Number.isInteger(tab_id)) state.tabs.add(tab_id);
        if (state.socket?.readyState !== WebSocket.OPEN) return false;

        state.socket.send(JSON.stringify({
            ...message,
            tabId: tab_id,
            pageUrl: sender.tab?.url,
        }));
        return true;
    },

};

chrome.runtime.onMessage.addListener((message, sender, send_response) => {
    const tab_id = sender.tab?.id;
    if (Number.isInteger(tab_id)) state.tabs.add(tab_id);

    if (message?.type === 'bridge.status') {
        send_response({ connected: state.socket?.readyState === WebSocket.OPEN });
        return false;
    }
    if (message?.type === 'popup.snapshot') {
        Promise.resolve(state.cache_ready).then(() => send_response(service.snapshot_result()));
        return true;
    }
    if (message?.type === 'popup.refresh') {
        Promise.resolve(state.cache_ready).then(() => {
            service.refresh_connectors(null);
            service.inspect_known_tabs('popup_refresh');
            send_response({ refreshing: true });
        });
        return true;
    }
    if (message?.type === 'conversation.lookup') {
        Promise.resolve(state.cache_ready).then(() => {
            const conversation = state.conversation_cache.find((item) => item.conversationId === message.conversationId) ?? null;
            send_response({ found: Boolean(conversation), conversation });
        });
        return true;
    }
    if (message?.type === 'bridge.connect') {
        service.connect().then((connected) => send_response({ connected }));
        return true;
    }
    if (message?.type === 'bridge.disconnect') {
        service.disconnect();
        send_response({ connected: false });
        return false;
    }
    if (message?.source === 'codexter-content' && message.type === 'connectors.cache') {
        Promise.resolve(state.cache_ready).then(() => {
            service.update_connector_cache(message);
            send_response({ cached: true, count: state.connector_cache.length });
        });
        return true;
    }
    if (message?.source === 'codexter-content' && (message.type === 'conversation.relation' || message.type === 'conversation.metadata')) {
        Promise.resolve(state.cache_ready).then(() => {
            const added = service.update_conversation_cache(message);
            send_response({ cached: true, added, count: state.conversation_cache.length });
        });
        return true;
    }
    if (message?.source === 'codexter-content') {
        send_response({ sent: service.send(message, sender) });
        return false;
    }
    return false;
});

state.cache_ready = service.restore_cache();
