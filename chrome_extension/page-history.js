(() => {
    const app = globalThis.__codexter_page;
    if (!app || app.history) return;

    const history = {
        native_json: Response.prototype.json,

        is_history_res(url) {
            try {
                const parsed = new URL(url, location.href);
                return parsed.origin === location.origin &&
                    /^\/backend-api\/conversation\/[0-9a-f-]{20,}\/?$/i.test(parsed.pathname);
            } catch {
                return false;
            }
        },

        is_user(message) {
            return message?.author?.role === 'user';
        },

        is_final(message) {
            return message?.author?.role === 'assistant' &&
                message?.content?.content_type === 'text' &&
                message?.channel === 'final' &&
                message?.end_turn === true;
        },

        is_image_final(message) {
            if (
                message?.author?.role !== 'tool' ||
                message?.channel !== 'final' ||
                message?.content?.content_type !== 'multimodal_text'
            ) {
                return false;
            }

            const parts = message.content.parts;
            return Array.isArray(parts) && parts.some((part) =>
                part &&
                typeof part === 'object' &&
                part.content_type === 'image_asset_pointer' &&
                typeof part.asset_pointer === 'string' &&
                part.asset_pointer.length > 0
            );
        },

        count_users(data) {
            if (!data || typeof data !== 'object' || !data.mapping || !data.current_node) return 0;
            const mapping = data.mapping;
            const seen = new Set();
            let node_id = data.current_node;
            let count = 0;

            while (node_id && mapping[node_id] && !seen.has(node_id)) {
                seen.add(node_id);
                if (history.is_user(mapping[node_id]?.message)) count += 1;
                node_id = mapping[node_id].parent;
            }
            return count;
        },

        trim(data) {
            if (!data || typeof data !== 'object' || !data.mapping || !data.current_node) return null;
            const mapping = data.mapping;
            const newest_ids = [];
            const seen = new Set();
            let node_id = data.current_node;

            while (node_id && mapping[node_id] && !seen.has(node_id)) {
                seen.add(node_id);
                newest_ids.push(node_id);
                node_id = mapping[node_id].parent;
            }

            const chain = newest_ids.reverse();
            const kept_ids = [];
            let removed_count = 0;

            for (const id of chain) {
                const message = mapping[id]?.message;
                const keep = !message ||
                    history.is_user(message) ||
                    history.is_final(message) ||
                    history.is_image_final(message);
                if (!keep) {
                    removed_count += 1;
                    continue;
                }
                kept_ids.push(id);
            }

            if (kept_ids.length === chain.length) return null;
            const compact_map = {};
            let prev_id = null;

            for (const id of kept_ids) {
                const node = mapping[id];
                node.parent = prev_id;
                node.children = [];
                if (node.message?.metadata && typeof node.message.metadata === 'object' && 'parent_id' in node.message.metadata) {
                    node.message.metadata.parent_id = prev_id;
                }
                compact_map[id] = node;
                if (prev_id) compact_map[prev_id].children = [id];
                prev_id = id;
            }

            const original_count = Object.keys(mapping).length;
            data.mapping = compact_map;
            data.current_node = prev_id;
            return {
                original_count,
                kept_count: kept_ids.length,
                removed_count: original_count - kept_ids.length,
                removed_process: removed_count,
            };
        },

        async response_json(response, args) {
            const data = await history.native_json.apply(response, args);
            try {
                if (!history.is_history_res(response.url)) return data;
                const user_count = history.count_users(data);
                if (app.state.history_trim) {
                    const result = history.trim(data);
                    if (result) app.service.emit('history.trimmed', result);
                }
                app.virtual.schedule_check(user_count);
            } catch {}
            return data;
        },

        install() {
            Response.prototype.json = function codexter_response_json(...args) {
                return history.response_json(this, args);
            };
        },
    };

    app.history = history;
})();
