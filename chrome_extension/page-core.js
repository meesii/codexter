(() => {
    if (globalThis.__codexter_page) return;

    const config = {
        PAGE_SOURCE: 'codexter-page',
        CONTENT_SOURCE: 'codexter-content',
        MIN_TURNS: 12,
        COMPAT_TIMEOUT_MS: 6000,
    };

    const state = {
        conversation_id: null,
        turn_id: null,
        status: 'idle',
        last_patch: null,
        completed_turn: null,
        history_trim: true,
        native_virtual: true,
    };

    const stats = {
        map_hits: 0,
        matched: 0,
        patched: 0,
        last_hit: 0,
    };

    const runtime = {
        compat_timer: null,
        compat_check_id: 0,
    };

    const service = {
        conversation_id() {
            return location.pathname.match(/\/c\/([0-9a-f-]{20,})/i)?.[1] ?? null;
        },

        emit(type, data = {}) {
            const url_id = service.conversation_id();
            if (url_id && url_id !== state.conversation_id) {
                state.conversation_id = url_id;
                state.turn_id = null;
                state.completed_turn = null;
            }
            window.postMessage({
                ...data,
                source: config.PAGE_SOURCE,
                type,
                conversation_id: state.conversation_id,
                turn_id: state.turn_id,
            }, '*');
        },

        update_ids(data) {
            if (!data || typeof data !== 'object') return;
            const conversation_id = data.conversation_id ?? data.conversationId;
            const turn_id = data.turn_id ?? data.turnId ?? data.turn_exchange_id;
            if (typeof conversation_id === 'string' && conversation_id) state.conversation_id = conversation_id;
            if (typeof turn_id === 'string' && turn_id) state.turn_id = turn_id;
        },

        set_status(status, reason) {
            if (state.status === status) return;
            state.status = status;
            service.emit('chat.state', { status, reason });
        },

        complete(reason) {
            const turn_id = state.turn_id;
            if (turn_id && state.completed_turn === turn_id) return;
            state.completed_turn = turn_id;
            state.status = 'idle';
            service.emit('chat.completed', { status: 'idle', reason });
        },
    };

    state.conversation_id = service.conversation_id();
    globalThis.__codexter_page = {
        config,
        state,
        stats,
        runtime,
        service,
        virtual: null,
        history: null,
        socket: null,
        composer: null,
        connectors: null,
    };
})();
