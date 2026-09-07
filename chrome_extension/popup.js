const config = {
    HISTORY_KEY: 'codexter.trimHistoricalConversation',
    VIRTUAL_KEY: 'codexter.nativeTurnVirtualization',
    COMPAT_KEY: 'codexter.nativeVirtualizationCompatibility',
    CONVERSATION_CACHE_KEY: 'codexter.conversationRelations',
};

const ui = {
    history_toggle: null,
    virtual_toggle: null,
    virtual_status: null,
    bridge_dot: null,
    bridge_text: null,
    cache_summary: null,
    connector_list: null,
    conversation_list: null,
    connector_count: null,
    conversation_count: null,
    refresh_button: null,

    bind() {
        ui.history_toggle = document.getElementById('history-trim');
        ui.virtual_toggle = document.getElementById('native-virtual');
        ui.virtual_status = document.getElementById('virtual-status');
        ui.bridge_dot = document.getElementById('bridge-dot');
        ui.bridge_text = document.getElementById('bridge-text');
        ui.cache_summary = document.getElementById('cache-summary');
        ui.connector_list = document.getElementById('connector-list');
        ui.conversation_list = document.getElementById('conversation-list');
        ui.connector_count = document.getElementById('connector-count');
        ui.conversation_count = document.getElementById('conversation-count');
        ui.refresh_button = document.getElementById('refresh-cache');
        document.getElementById('version-text').textContent = `v${chrome.runtime.getManifest().version}`;
    },

    short(value, head = 8, tail = 6) {
        if (!value) return '—';
        const text = String(value);
        return text.length > head + tail + 2 ? `${text.slice(0, head)}…${text.slice(-tail)}` : text;
    },

    empty(text) {
        const node = document.createElement('div');
        node.className = 'empty-state';
        node.textContent = text;
        return node;
    },

    render_connectors(items) {
        ui.connector_count.textContent = String(items.length);
        ui.connector_list.replaceChildren();
        if (items.length === 0) {
            ui.connector_list.append(ui.empty('暂未发现用户安装的 MCP 插件'));
            return;
        }
        for (const item of items) {
            const row = document.createElement('div');
            row.className = 'data-row';
            const icon = document.createElement('div');
            icon.className = 'row-icon';
            icon.textContent = (item.name || 'M').trim().slice(0, 1).toUpperCase();
            const main = document.createElement('div');
            main.className = 'row-main';
            const title = document.createElement('div');
            title.className = 'row-title';
            title.textContent = item.name || '未命名插件';
            const code = document.createElement('div');
            code.className = 'row-code';
            code.textContent = item.appId || '—';
            code.title = item.appId || '';
            main.append(title, code);
            const tag = document.createElement('span');
            tag.className = 'row-tag';
            tag.textContent = item.workspaceUuid ? ui.short(item.workspaceUuid, 6, 4) : '未匹配';
            tag.title = item.workspaceUuid || item.baseUrl || '未识别工作区';
            row.append(icon, main, tag);
            ui.connector_list.append(row);
        }
    },

    render_conversations(items) {
        ui.conversation_count.textContent = String(items.length);
        ui.conversation_list.replaceChildren();
        if (items.length === 0) {
            ui.conversation_list.append(ui.empty('打开或使用一个已关联插件的 ChatGPT 会话后会显示在这里'));
            return;
        }
        for (const item of items) {
            const row = document.createElement('div');
            row.className = 'data-row';
            const icon = document.createElement('div');
            icon.className = 'row-icon chat';
            icon.textContent = 'C';
            const main = document.createElement('div');
            main.className = 'row-main';
            const title = document.createElement('div');
            title.className = 'row-title';
            title.textContent = item.title || '未命名会话';
            title.title = item.title || '';
            const sub = document.createElement('div');
            sub.className = 'row-sub';
            sub.textContent = `${item.appName || ui.short(item.appId, 10, 5)} · ${ui.short(item.conversationId, 8, 6)}`;
            sub.title = `${item.conversationId || ''}\n${item.appId || ''}`;
            main.append(title, sub);
            const tag = document.createElement('span');
            tag.className = 'row-tag';
            tag.textContent = item.workspaceUuid ? ui.short(item.workspaceUuid, 6, 4) : '待映射';
            tag.title = item.workspaceUuid || item.relationSource || '';
            row.append(icon, main, tag);
            ui.conversation_list.append(row);
        }
    },

    render_snapshot(snapshot = {}) {
        const connectors = Array.isArray(snapshot.connectors) ? snapshot.connectors : [];
        const connector_map = new Map(connectors.map((item) => [item.appId, item]));
        const conversations = (Array.isArray(snapshot.conversations) ? snapshot.conversations : []).map((item) => {
            const connector = connector_map.get(item.appId);
            return {
                ...item,
                appName: item.appName || connector?.name || null,
                workspaceUuid: item.workspaceUuid || connector?.workspaceUuid || null,
                baseUrl: item.baseUrl || connector?.baseUrl || null,
            };
        });
        const connected = snapshot.connected === true;
        ui.bridge_dot.classList.toggle('is-online', connected);
        ui.bridge_text.textContent = connected ? 'Codexter 已连接' : 'Codexter 未连接';
        const refreshed = snapshot.connectorRefreshedAt
            ? new Date(snapshot.connectorRefreshedAt).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
            : '尚未刷新';
        ui.cache_summary.textContent = `${connectors.length} 个插件映射 · ${conversations.length} 个会话 · ${refreshed}`;
        ui.render_connectors(connectors);
        ui.render_conversations(conversations);
    },

    render_compat(record = null) {
        if (!ui.virtual_status) return;
        ui.virtual_status.classList.remove('is-ok', 'is-checking', 'is-error');
        let text = '等待长会话检测';
        if (!ui.virtual_toggle.checked) text = '原生虚拟化未启用';
        else if (record?.status === 'compatible') {
            text = '兼容性正常';
            ui.virtual_status.classList.add('is-ok');
        } else if (record?.status === 'checking') {
            text = '正在检测兼容性';
            ui.virtual_status.classList.add('is-checking');
        } else if (record?.status === 'incompatible') {
            text = '兼容性失效，ChatGPT 页面结构可能已更新';
            ui.virtual_status.classList.add('is-error');
        }
        ui.virtual_status.title = text;
        ui.virtual_status.setAttribute('aria-label', text);
    },
};

const service = {
    load_settings() {
        return chrome.storage.local.get([config.HISTORY_KEY, config.VIRTUAL_KEY, config.COMPAT_KEY]);
    },

    save(key, value) {
        return chrome.storage.local.set({ [key]: value }).catch(() => {});
    },

    async load_snapshot() {
        try {
            const [snapshot, local] = await Promise.all([
                chrome.runtime.sendMessage({ type: 'popup.snapshot' }).catch(() => ({})),
                chrome.storage.local.get(config.CONVERSATION_CACHE_KEY).catch(() => ({})),
            ]);
            const local_conversations = Array.isArray(local?.[config.CONVERSATION_CACHE_KEY])
                ? local[config.CONVERSATION_CACHE_KEY]
                : [];
            const merged = new Map();
            for (const item of [...(snapshot?.conversations || []), ...local_conversations]) {
                if (!item?.conversationId || !item?.appId) continue;
                merged.set(item.conversationId, {
                    ...(merged.get(item.conversationId) ?? {}),
                    ...item,
                });
            }
            ui.render_snapshot({
                ...(snapshot || {}),
                conversations: [...merged.values()],
            });
        } catch {
            ui.render_snapshot({});
        }
    },
};

const action = {
    bind_events() {
        for (const button of document.querySelectorAll('.tab-button')) {
            button.addEventListener('click', () => {
                const tab = button.dataset.tab;
                document.querySelectorAll('.tab-button').forEach((node) => node.classList.toggle('is-active', node === button));
                document.querySelectorAll('.tab-page').forEach((node) => node.classList.toggle('is-active', node.dataset.page === tab));
            });
        }

        ui.history_toggle.addEventListener('change', () => void service.save(config.HISTORY_KEY, ui.history_toggle.checked));
        ui.virtual_toggle.addEventListener('change', () => {
            ui.render_compat();
            void service.save(config.VIRTUAL_KEY, ui.virtual_toggle.checked);
        });
        ui.refresh_button.addEventListener('click', async () => {
            ui.refresh_button.classList.add('is-loading');
            ui.refresh_button.disabled = true;
            try {
                await chrome.runtime.sendMessage({ type: 'popup.refresh' });
                setTimeout(() => void service.load_snapshot(), 500);
                setTimeout(() => void service.load_snapshot(), 1400);
            } finally {
                setTimeout(() => {
                    ui.refresh_button.classList.remove('is-loading');
                    ui.refresh_button.disabled = false;
                }, 900);
            }
        });

        chrome.storage.onChanged.addListener((changes, area_name) => {
            if (area_name === 'local' && changes[config.COMPAT_KEY]) ui.render_compat(changes[config.COMPAT_KEY].newValue);
            if (area_name === 'local' && changes[config.CONVERSATION_CACHE_KEY]) void service.load_snapshot();
            if (area_name === 'session') void service.load_snapshot();
        });
    },

    async init() {
        ui.bind();
        if (!(ui.history_toggle instanceof HTMLInputElement) || !(ui.virtual_toggle instanceof HTMLInputElement)) return;
        action.bind_events();
        void service.load_snapshot();

        try {
            const values = await service.load_settings();
            ui.history_toggle.checked = values[config.HISTORY_KEY] !== false;
            ui.virtual_toggle.checked = values[config.VIRTUAL_KEY] !== false;
            ui.render_compat(values[config.COMPAT_KEY]);
            const defaults = {};
            if (values[config.HISTORY_KEY] === undefined) defaults[config.HISTORY_KEY] = true;
            if (values[config.VIRTUAL_KEY] === undefined) defaults[config.VIRTUAL_KEY] = true;
            if (Object.keys(defaults).length > 0) await chrome.storage.local.set(defaults);
        } catch {
            ui.history_toggle.checked = true;
            ui.virtual_toggle.checked = true;
            ui.render_compat();
        }
    },
};

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', action.init, { once: true });
else void action.init();
