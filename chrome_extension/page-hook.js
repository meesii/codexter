(() => {
    const app = globalThis.__codexter_page;
    if (!app || globalThis.__codexter_page_started) return;
    globalThis.__codexter_page_started = true;

    const service = {
        handle_message(event) {
            if (event.source !== window || event.data?.source !== app.config.CONTENT_SOURCE) return;
            const data = event.data;

            if (data.type === 'performance.config') {
                app.state.history_trim = data.history_trim !== false;
                app.state.native_virtual = data.native_virtual !== false;
                if (!app.state.native_virtual) app.virtual.disable_check();
                return;
            }
            if (data.type === 'composer.send') {
                const text = String(data.text ?? '').trim();
                if (text) void app.composer.send(data.requestId, text);
                return;
            }
            if (data.type === 'composer.stop') {
                app.composer.stop();
                return;
            }
            if (data.type === 'content.ready') {
                app.socket?.replay_relations?.();
                void app.connectors?.refresh('content_ready');
                return;
            }
            if (data.type === 'connectors.refresh') {
                void app.connectors?.refresh(data.reason || 'bridge_request');
                return;
            }
            if (data.type === 'conversation.known') {
                const conversation_id = data.conversationId || app.service.conversation_id();
                if (conversation_id) app.socket?.matched_conversations?.add(conversation_id);
                return;
            }
            if (data.type === 'conversation.inspect') {
                void app.connectors?.inspect_conversation(data.conversationId || app.service.conversation_id(), data.reason || 'navigation');
            }
        },

        init() {
            app.virtual.install();
            app.history.install();
            app.socket.install();
            app.connectors?.install();
            window.addEventListener('message', service.handle_message);
            app.service.emit('hook.ready', { status: app.state.status });
        },
    };

    service.init();
})();
