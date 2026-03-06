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

    showLogModal: function(ev) {
        var btn = ev.target;
        btn.disabled = true;
        btn.textContent = 'Загрузка...';
        return this.callRpc('log').then(function(data) {
            btn.disabled = false;
            btn.textContent = '📋 Посмотреть лог';
            ui.showModal('Лог WiFi Monitor', [
                E('pre', {
                    style: 'background:#111;color:#7fc97f;padding:12px;border-radius:4px;max-height:60vh;overflow-y:auto;font-size:12px;white-space:pre-wrap;word-break:break-all;'
                }, data.log || 'Лог пуст'),
                E('div', { class: 'right', style: 'margin-top:16px; display:flex; gap:8px; justify-content:flex-end;' }, [
                    E('button', {
                        class: 'btn cbi-button cbi-button-negative',
                        click: function() {
                            this.callRpc('clear_log').then(function() {
                                ui.hideModal();
                                ui.addNotification(null, E('p', 'Лог очищен'), 'info');
                            });
                        }.bind(this)
                    }, '🗑 Очистить'),
                    E('button', {
                        class: 'btn cbi-button cbi-button-neutral',
                        click: ui.hideModal
                    }, 'Закрыть')
                ])
            ]);
        }.bind(this));
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



    render: function() {
        var enabled   = uci.get('wifi_monitor', 'settings', 'enabled')   || '0';
        var bot_token = uci.get('wifi_monitor', 'settings', 'bot_token') || '';
        var chat_id   = uci.get('wifi_monitor', 'settings', 'chat_id')   || '';

        var view = E('div', { class: 'cbi-map' }, [

            E('h2', { style: 'display:flex; justify-content:space-between; align-items:center;' }, [
                '📡 WiFi Monitor → Telegram',
                E('div', { id: 'wm-version-box', style: 'font-size:14px; font-weight:normal;' }, 'Версия: ...')
            ]),

            /* ── Статус + управление ── */
            E('div', { class: 'cbi-section' }, [
                E('div', { style: 'display:flex;align-items:center;gap:16px;flex-wrap:wrap' }, [
                    E('span', { style: 'font-size:15px' }, 'Статус: '),
                    E('span', {
                        id: 'wm-status',
                        style: 'font-weight:bold;font-size:15px;color:' + (enabled === '1' ? '#2ecc71' : '#888')
                    }, enabled === '1' ? '🟢 Включён' : '⚪ Выключен'),
                    E('button', {
                        class: 'cbi-button cbi-button-action',
                        style: 'margin-left:auto;',
                        click: ui.createHandlerFn(this, 'showLogModal')
                    }, '📋 Посмотреть лог')
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


        ]);

        /* Мгновенная загрузка + Polling каждые 3 секунды */
        this.pollClients();
        poll.add(L.bind(this.pollClients, this), 3);

        /* Проверка версии 1 раз при открытии страницы */
        this.callRpc('version').then(function(res) {
            var vEl = document.getElementById('wm-version-box');
            if (res.local && res.remote) {
                var isOld = (res.local !== res.remote) && (res.remote !== '0.0.0');
                vEl.innerHTML = 'Версия: <b>' + res.local + '</b>';
                if (isOld) {
                    vEl.appendChild(E('button', {
                        class: 'cbi-button cbi-button-apply',
                        style: 'margin-left:12px; padding: 2px 8px;',
                        click: function() {
                            ui.showModal('📡 Доступно обновление', [
                                E('p', {}, [ 'Новая версия: ', E('strong', {}, res.remote) ]),
                                E('p', {}, 'Выполните в терминале роутера следующую команду:'),
                                E('pre', { style: 'padding:8px; background:#111; color:#fff;' },
                                    'sh <(wget -O - https://raw.githubusercontent.com/difome/openwrt-wifi-monitor/refs/heads/main/install.sh)'
                                ),
                                E('div', { class: 'right', style: 'margin-top:16px;' }, [
                                    E('button', { class: 'btn cbi-button cbi-button-neutral', click: ui.hideModal }, 'Закрыть')
                                ])
                            ]);
                        }
                    }, '🔄 Доступно обновление (' + res.remote + ')'));
                }
            } else {
                vEl.textContent = 'Версия: неизвестна';
            }
        });

        return view;
    },

    handleSaveApply: null,
    handleReset: null
});
