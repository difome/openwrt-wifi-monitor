'use strict';
'require view';
'require uci';
'require ui';
'require fs';
'require poll';

return view.extend({

    load: function() {
        return uci.load('wifi_monitor');
    },

    callRpc: function(cmd, args) {
        var params = [cmd].concat(args || []);
        return fs.exec('/usr/bin/wifi_monitor_rpc.sh', params).then(function(res) {
            try {
                return JSON.parse(res.stdout);
            } catch(e) {
                return { result: 'error', msg: res.stdout || res.stderr };
            }
        });
    },

    pollClients: function() {
        return this.callRpc('clients').then(function(data) {
            var tbody = document.getElementById('wm-clients');
            if (!tbody || !data.clients) return;
            if (data.clients.length === 0) {
                tbody.innerHTML = '<tr><td colspan="4" style="color:#888;padding:12px 8px">Нет подключённых устройств</td></tr>';
                return;
            }
            tbody.innerHTML = data.clients.map(function(c) {
                return '<tr>' +
                    '<td><code style="font-size:12px">' + c.mac + '</code></td>' +
                    '<td>' + (c.hostname || '—') + '</td>' +
                    '<td>' + (c.ip || '—') + '</td>' +
                    '<td><code>' + c.iface + '</code></td>' +
                    '</tr>';
            }).join('');
            document.getElementById('wm-count').textContent = data.clients.length;
        });
    },

    pollLog: function() {
        return this.callRpc('log').then(function(data) {
            var el = document.getElementById('wm-log');
            if (!el || !data.log) return;
            el.textContent = data.log;
            el.scrollTop = el.scrollHeight;
        });
    },

    handleSave: function(ev) {
        var enabled   = document.getElementById('wm-enabled').checked ? '1' : '0';
        var bot_token = document.getElementById('wm-token').value.trim();
        var chat_id   = document.getElementById('wm-chatid').value.trim();

        var btn = ev.target;
        btn.disabled = true;
        btn.textContent = 'Сохранение...';

        return this.callRpc('save', [enabled, bot_token, chat_id]).then(function(res) {
            btn.disabled = false;
            btn.textContent = '💾 Сохранить';
            if (res.result === 'ok') {
                var statusEl = document.getElementById('wm-status');
                statusEl.textContent = enabled === '1' ? '🟢 Включён' : '⚪ Выключен';
                statusEl.style.color = enabled === '1' ? '#2ecc71' : '#888';
                ui.addNotification(null, E('p', '✅ Настройки сохранены'), 'info');
            } else {
                ui.addNotification(null, E('p', '❌ Ошибка: ' + (res.msg || 'неизвестно')), 'error');
            }
        }.bind(this));
    },

    handleTest: function(ev) {
        var btn = ev.target;
        btn.disabled = true;
        btn.textContent = 'Отправка...';
        return this.callRpc('test').then(function(res) {
            btn.disabled = false;
            btn.textContent = '📨 Тест';
            if (res.result === 'ok')
                ui.addNotification(null, E('p', '✅ Тест отправлен — проверь Telegram'), 'info');
            else
                ui.addNotification(null, E('p', '❌ Ошибка: ' + (res.msg || 'нет ответа')), 'error');
        });
    },

    handleClearLog: function(ev) {
        return this.callRpc('clear_log').then(function() {
            var el = document.getElementById('wm-log');
            if (el) el.textContent = '';
            ui.addNotification(null, E('p', 'Лог очищен'), 'info');
        });
    },

    render: function() {
        var enabled   = uci.get('wifi_monitor', 'settings', 'enabled')   || '0';
        var bot_token = uci.get('wifi_monitor', 'settings', 'bot_token') || '';
        var chat_id   = uci.get('wifi_monitor', 'settings', 'chat_id')   || '';

        var view = E('div', { class: 'cbi-map' }, [

            E('h2', {}, '📡 WiFi Monitor → Telegram'),

            /* ── Статус + управление ── */
            E('div', { class: 'cbi-section' }, [
                E('div', { style: 'display:flex;align-items:center;gap:16px;flex-wrap:wrap' }, [
                    E('span', { style: 'font-size:15px' }, 'Статус: '),
                    E('span', {
                        id: 'wm-status',
                        style: 'font-weight:bold;font-size:15px;color:' + (enabled === '1' ? '#2ecc71' : '#888')
                    }, enabled === '1' ? '🟢 Включён' : '⚪ Выключен'),
                ])
            ]),

            /* ── Онлайн клиенты ── */
            E('div', { class: 'cbi-section' }, [
                E('h3', {}, [ '🔗 Онлайн: ', E('span', { id: 'wm-count' }, '...') ]),
                E('div', { class: 'table-wrapper' }, [
                    E('table', { class: 'table cbi-section-table' }, [
                        E('tr', { class: 'tr table-titles' }, [
                            E('th', { class: 'th' }, 'MAC'),
                            E('th', { class: 'th' }, 'Устройство'),
                            E('th', { class: 'th' }, 'IP'),
                            E('th', { class: 'th' }, 'Интерфейс'),
                        ]),
                        E('tbody', { id: 'wm-clients' }, [
                            E('tr', {}, E('td', { colspan: 4, style: 'color:#888;padding:12px 8px' }, 'Загрузка...'))
                        ])
                    ])
                ])
            ]),

            /* ── Настройки ── */
            E('div', { class: 'cbi-section' }, [
                E('h3', {}, '⚙️ Настройки'),
                E('div', { class: 'cbi-section-node' }, [

                    E('div', { class: 'cbi-value' }, [
                        E('label', { class: 'cbi-value-title' }, 'Включить'),
                        E('div', { class: 'cbi-value-field' }, [
                            E('input', {
                                id: 'wm-enabled',
                                type: 'checkbox',
                                checked: enabled === '1' ? '' : null,
                                style: 'width:auto;transform:scale(1.5);margin:6px 4px'
                            })
                        ])
                    ]),

                    E('div', { class: 'cbi-value' }, [
                        E('label', { class: 'cbi-value-title' }, 'Bot Token'),
                        E('div', { class: 'cbi-value-field' }, [
                            E('input', {
                                id: 'wm-token',
                                type: 'password',
                                value: bot_token,
                                placeholder: '1234567890:AAFxxx...',
                                class: 'cbi-input-text',
                                style: 'width:100%;max-width:400px;font-family:monospace'
                            })
                        ])
                    ]),

                    E('div', { class: 'cbi-value' }, [
                        E('label', { class: 'cbi-value-title' }, 'Chat ID'),
                        E('div', { class: 'cbi-value-field' }, [
                            E('input', {
                                id: 'wm-chatid',
                                type: 'text',
                                value: chat_id,
                                placeholder: '123456789',
                                class: 'cbi-input-text',
                                style: 'width:100%;max-width:400px;font-family:monospace'
                            })
                        ])
                    ]),

                    E('div', { class: 'cbi-value' }, [
                        E('label', { class: 'cbi-value-title' }, ''),
                        E('div', { class: 'cbi-value-field', style: 'display:flex;gap:8px;flex-wrap:wrap' }, [
                            E('button', {
                                class: 'cbi-button cbi-button-apply',
                                click: ui.createHandlerFn(this, 'handleSave')
                            }, '💾 Сохранить'),
                            E('button', {
                                class: 'cbi-button cbi-button-action',
                                click: ui.createHandlerFn(this, 'handleTest')
                            }, '📨 Тест')
                        ])
                    ])
                ])
            ]),

            /* ── Лог ── */
            E('div', { class: 'cbi-section' }, [
                E('h3', {}, '📋 Лог'),
                E('pre', {
                    id: 'wm-log',
                    style: 'background:#111;color:#7fc97f;padding:12px;border-radius:4px;' +
                           'max-height:280px;overflow-y:auto;font-size:12px;' +
                           'white-space:pre-wrap;word-break:break-all;margin:0 0 10px 0'
                }, 'Загрузка...'),
                E('div', { style: 'display:flex;gap:8px' }, [
                    E('button', {
                        class: 'cbi-button cbi-button-negative',
                        click: ui.createHandlerFn(this, 'handleClearLog')
                    }, '🗑 Очистить')
                ])
            ])
        ]);

        /* Polling каждые 5 секунд */
        poll.add(L.bind(this.pollClients, this), 5);
        poll.add(L.bind(this.pollLog, this), 5);

        return view;
    },

    handleSaveApply: null,
    handleReset: null
});
