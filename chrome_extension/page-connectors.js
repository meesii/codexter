(() => {
    const app = globalThis.__codexter_page;
    if (!app || app.connectors) return;

    const config = {
        INSTALLED_URL: '/backend-api/ps/plugins/installed?limit=1000',
        AUTH_URL: '/api/auth/session',
        CONNECTOR_URL: (id) => `/backend-api/aip/connectors/${encodeURIComponent(id)}?include_logo=false&include_actions=false`,
        CONVERSATION_URL: (id) => `/backend-api/conversation/${encodeURIComponent(id)}`,
    };

    const runtime = {
        refreshing: null,
        cache: [],
        refreshed_at: null,
        token: null,
    };

    const connectors = {
        normalize_app_id(value) {
            if (typeof value !== 'string') return null;
            const match = value.match(/(?:plugin_)?(asdk_app_[0-9a-f]+)/i);
            return match ? match[1] : null;
        },

        find_app_id(value, seen = new WeakSet()) {
            if (typeof value === 'string') return connectors.normalize_app_id(value);
            if (!value || typeof value !== 'object' || seen.has(value)) return null;
            seen.add(value);
            if (Array.isArray(value)) {
                for (const child of value) {
                    const found = connectors.find_app_id(child, seen);
                    if (found) return found;
                }
                return null;
            }
            const preferred = [value.id, value.app_id, value.appId, value.plugin_id, value.pluginId, value.connector_id];
            for (const candidate of preferred) {
                const found = connectors.normalize_app_id(candidate);
                if (found) return found;
            }
            for (const child of Object.values(value)) {
                const found = connectors.find_app_id(child, seen);
                if (found) return found;
            }
            return null;
        },

        collect_user_plugins(value, output = [], seen = new WeakSet()) {
            if (!value || typeof value !== 'object' || seen.has(value)) return output;
            seen.add(value);
            if (!Array.isArray(value) && String(value.scope ?? '').toUpperCase() === 'USER') {
                const app_id = connectors.find_app_id(value);
                if (app_id) {
                    output.push({
                        appId: app_id,
                        pluginId: `plugin_${app_id}`,
                        name: value.name ?? value.display_name ?? value.title ?? null,
                    });
                }
            }
            for (const child of Array.isArray(value) ? value : Object.values(value)) {
                if (child && typeof child === 'object') connectors.collect_user_plugins(child, output, seen);
            }
            return output;
        },

        workspace_uuid(base_url) {
            if (typeof base_url !== 'string') return null;
            return base_url.match(/\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/mcp(?:[/?#]|$)/i)?.[1] ?? null;
        },

        async access_token() {
            if (runtime.token) return runtime.token;
            const response = await fetch(config.AUTH_URL, { credentials: 'include' });
            if (!response.ok) throw new Error(`auth/session ${response.status}`);
            const auth = await response.json();
            const token = auth?.accessToken;
            if (!token) throw new Error('ChatGPT accessToken 不存在');
            runtime.token = token;
            return token;
        },

        async request_json(url, token = null) {
            const access_token = token ?? await connectors.access_token();
            const response = await fetch(url, {
                credentials: 'include',
                headers: {
                    Accept: 'application/json',
                    Authorization: `Bearer ${access_token}`,
                },
            });
            if (!response.ok) throw new Error(`${response.status} ${response.statusText || url}`);
            return response.json();
        },

        conversation_relation(data) {
            if (!data || typeof data !== 'object') return null;
            const mapping = data.mapping;
            if (!mapping || typeof mapping !== 'object') return null;

            for (const node of Object.values(mapping)) {
                const message = node?.message;
                if (!message || typeof message !== 'object') continue;
                const metadata = message.metadata ?? {};
                const hints = Array.isArray(metadata.system_hints) ? metadata.system_hints.join(' ') : '';
                const resource_uri = typeof metadata.invoked_resource?.resource_uri === 'string'
                    ? metadata.invoked_resource.resource_uri
                    : '';
                const content_text = typeof message.content?.text === 'string' ? message.content.text : '';
                const app_id = connectors.normalize_app_id(`${hints} ${resource_uri} ${content_text}`);
                if (!app_id) continue;
                const link_id = `${resource_uri} ${content_text}`.match(/link_[0-9a-f]+/i)?.[0] ?? null;
                return {
                    conversationId: data.conversation_id ?? app.service.conversation_id(),
                    appId: app_id,
                    linkId: link_id,
                    appName: metadata.invoked_resource?.app_name ?? null,
                    title: data.title ?? null,
                    gizmoId: data.gizmo_id ?? data.conversation_template_id ?? null,
                    relationSource: 'history',
                };
            }
            return null;
        },

        async inspect_conversation(conversation_id, reason = 'page_load') {
            if (!conversation_id) return null;
            if (app.socket?.matched_conversations?.has(conversation_id)) return null;
            try {
                const data = await connectors.request_json(config.CONVERSATION_URL(conversation_id));
                const relation = connectors.conversation_relation(data);
                if (!relation) {
                    console.info(`[Codexter][会话关联] 历史记录未发现插件：${conversation_id}`);
                    return null;
                }
                console.info(`[Codexter][会话关联] 历史查询命中，reason=${reason}`, relation);
                const added = app.socket?.record_relation(relation) === true;
                if (!added) app.service.emit('conversation.metadata', relation);
                return relation;
            } catch (error) {
                console.warn(`[Codexter][会话关联] 历史查询失败：${conversation_id}`, error);
                return null;
            }
        },

        async load(reason = 'startup') {
            console.info(`[Codexter][Connectors] 开始主动刷新，reason=${reason}`);
            const token = await connectors.access_token();
            const installed = await connectors.request_json(config.INSTALLED_URL, token);
            const plugins = connectors.collect_user_plugins(installed);
            const unique = [...new Map(plugins.map((item) => [item.appId, item])).values()];
            console.info(`[Codexter][Connectors] 找到 USER 插件 ${unique.length} 个`);

            const result = [];
            for (const plugin of unique) {
                try {
                    const detail = await connectors.request_json(config.CONNECTOR_URL(plugin.appId), token);
                    const base_url = detail?.base_url ?? null;
                    const item = {
                        appId: plugin.appId,
                        pluginId: plugin.pluginId,
                        name: detail?.name ?? plugin.name,
                        baseUrl: base_url,
                        workspaceUuid: connectors.workspace_uuid(base_url),
                    };
                    result.push(item);
                } catch (error) {
                    console.warn(`[Codexter][Connectors] ${plugin.appId} 查询失败`, error);
                }
            }
            return result;
        },

        refresh(reason = 'manual') {
            if (runtime.refreshing) return runtime.refreshing;
            runtime.refreshing = connectors.load(reason)
                .then((items) => {
                    runtime.cache = items;
                    runtime.refreshed_at = Date.now();
                    console.info(`[Codexter][Connectors] 主动刷新完成，共 ${items.length} 个映射`);
                    console.table(items.map((item) => ({
                        name: item.name,
                        appId: item.appId,
                        workspaceUuid: item.workspaceUuid,
                        baseUrl: item.baseUrl,
                    })));
                    app.service.emit('connectors.cache', {
                        connectors: items,
                        refreshedAt: runtime.refreshed_at,
                        reason,
                    });
                    return items;
                })
                .catch((error) => {
                    console.error('[Codexter][Connectors] 主动刷新失败', error);
                    app.service.emit('connectors.cache_error', {
                        error: String(error?.message ?? error),
                        reason,
                    });
                    return [];
                })
                .finally(() => {
                    runtime.refreshing = null;
                });
            return runtime.refreshing;
        },

        install() {},

    };

    app.connectors = connectors;
})();
