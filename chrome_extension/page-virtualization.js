(() => {
    const app = globalThis.__codexter_page;
    if (!app || app.virtual) return;

    const virtual = {
        native_map: Array.prototype.map,

        emit_status(status, data = {}) {
            app.service.emit('virtual.compat', {
                status,
                map_hits: app.stats.map_hits,
                matched: app.stats.matched,
                patched: app.stats.patched,
                ...data,
            });
        },

        clear_timer() {
            if (!app.runtime.compat_timer) return;
            clearTimeout(app.runtime.compat_timer);
            app.runtime.compat_timer = null;
        },

        schedule_check(user_count) {
            virtual.clear_timer();
            app.runtime.compat_check_id += 1;
            const check_id = app.runtime.compat_check_id;
            if (!app.state.native_virtual || user_count < app.config.MIN_TURNS) return;

            const baseline_hits = app.stats.map_hits;
            virtual.emit_status('checking', { user_count });

            const verify = () => {
                if (check_id !== app.runtime.compat_check_id || !app.state.native_virtual) return;
                if (document.visibilityState === 'hidden') {
                    app.runtime.compat_timer = setTimeout(verify, 1500);
                    return;
                }

                app.runtime.compat_timer = null;
                const compatible = app.stats.map_hits > baseline_hits;
                virtual.emit_status(compatible ? 'compatible' : 'incompatible', { user_count });
            };

            app.runtime.compat_timer = setTimeout(verify, app.config.COMPAT_TIMEOUT_MS);
        },

        map_proxy(callback, this_arg) {
            const result = virtual.native_map.call(this, callback, this_arg);
            if (
                !app.state.native_virtual ||
                !Array.isArray(this) ||
                this.length < 5 ||
                typeof this[0] !== 'string'
            ) {
                return result;
            }

            let matched = 0;
            let patched = 0;
            for (let index = 0; index < result.length; index += 1) {
                const element = result[index];
                const props = element?.props;
                if (
                    !props ||
                    typeof props.turnId !== 'string' ||
                    typeof props.turnIndex !== 'number' ||
                    !('alwaysShow' in props) ||
                    !('intersectionObserver' in props) ||
                    typeof props.onIntersectingChange !== 'function'
                ) {
                    continue;
                }

                matched += 1;
                const always_show = props.isFinalTurn === true;
                if (props.alwaysShow === always_show) continue;
                result[index] = {
                    ...element,
                    props: { ...props, alwaysShow: always_show },
                };
                patched += 1;
            }

            if (matched > 0) {
                app.stats.map_hits += 1;
                app.stats.matched += matched;
                app.stats.patched += patched;
                app.stats.last_hit = performance.now();
                virtual.emit_status('compatible');
            }
            return result;
        },

        install() {
            if (Array.prototype.map.__codexter_virtual_patch === true) return;
            Object.defineProperty(virtual.map_proxy, '__codexter_virtual_patch', { value: true });
            Array.prototype.map = virtual.map_proxy;
        },

        disable_check() {
            app.runtime.compat_check_id += 1;
            virtual.clear_timer();
            virtual.emit_status('disabled');
        },
    };

    app.virtual = virtual;
})();
