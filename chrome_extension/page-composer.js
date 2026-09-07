(() => {
    const app = globalThis.__codexter_page;
    if (!app || app.composer) return;

    const composer = {
        find_editor() {
            return document.querySelector('#prompt-textarea') ||
                document.querySelector('[data-testid="composer-input"]') ||
                document.querySelector('div[contenteditable="true"][role="textbox"]') ||
                document.querySelector('div[contenteditable="true"]');
        },

        set_text(editor, text) {
            editor.focus();
            if (editor instanceof HTMLTextAreaElement || editor instanceof HTMLInputElement) {
                const proto = editor instanceof HTMLTextAreaElement
                    ? HTMLTextAreaElement.prototype
                    : HTMLInputElement.prototype;
                const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
                setter?.call(editor, text);
                editor.dispatchEvent(new InputEvent('input', {
                    bubbles: true,
                    inputType: 'insertText',
                    data: text,
                }));
                return;
            }

            const selection = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(editor);
            selection?.removeAllRanges();
            selection?.addRange(range);
            let inserted = false;
            try {
                inserted = document.execCommand('insertText', false, text);
            } catch {}
            if (inserted && editor.textContent === text) return;

            editor.replaceChildren();
            const paragraph = document.createElement('p');
            paragraph.textContent = text;
            editor.appendChild(paragraph);
            editor.dispatchEvent(new InputEvent('input', {
                bubbles: true,
                inputType: 'insertText',
                data: text,
            }));
        },

        find_send(editor) {
            return document.querySelector('[data-testid="send-button"]') ||
                document.querySelector('button[aria-label="发送提示"]') ||
                document.querySelector('button[aria-label="发送"]') ||
                document.querySelector('button[aria-label="Send prompt"]') ||
                editor?.closest('form')?.querySelector('button[type="submit"]');
        },

        find_stop() {
            return document.querySelector('[data-testid="stop-button"]') ||
                document.querySelector('button[aria-label="停止生成"]') ||
                document.querySelector('button[aria-label="Stop generating"]') ||
                document.querySelector('button[aria-label="停止"]');
        },

        async send(req_id, text) {
            if (app.state.status === 'generating' || app.state.status === 'sending' || composer.find_stop()) {
                app.service.emit('composer.result', { requestId: req_id, ok: false, error: '当前对话仍在生成中' });
                return;
            }

            const editor = composer.find_editor();
            if (!editor) {
                app.service.emit('composer.result', { requestId: req_id, ok: false, error: '未找到 ChatGPT 输入框' });
                return;
            }

            composer.set_text(editor, text);
            let button = composer.find_send(editor);
            const deadline = Date.now() + 1800;
            while ((!button || button.disabled) && Date.now() < deadline) {
                await new Promise((resolve) => setTimeout(resolve, 60));
                button = composer.find_send(editor);
            }
            if (!button || button.disabled) {
                app.service.emit('composer.result', { requestId: req_id, ok: false, error: '发送按钮当前不可用' });
                return;
            }

            button.click();
            app.service.set_status('sending', 'composer_submit');
            app.service.emit('composer.result', { requestId: req_id, ok: true });
        },

        stop() {
            const button = composer.find_stop();
            if (button) {
                button.click();
                app.service.emit('composer.stop_result', { ok: true });
                return;
            }
            app.service.emit('composer.stop_result', { ok: false, error: '未找到停止按钮' });
        },
    };

    app.composer = composer;
})();
