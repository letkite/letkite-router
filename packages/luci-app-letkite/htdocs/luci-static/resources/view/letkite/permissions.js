'use strict';
'require view';
'require rpc';
'require ui';
'require dom';

/*
 * Services > LetKite > Permissions: the agent's local ceiling
 * (/etc/letkite/ceiling.toml), the most AI assistants may ever be granted on
 * this router, whatever the account allows. Its seven switches can be turned
 * on and off here; its other settings (commands, files, screen, tunnels) are
 * not true or false, and are shown read-only: they are changed in the file.
 */

var callCeilingGet = rpc.declare({ object: 'letkite', method: 'ceiling_get' });
var callCeilingSet = rpc.declare({ object: 'letkite', method: 'ceiling_set', params: [ 'switch', 'value' ] });

var README = 'https://github.com/letkite/letkite-router#permissions';

var SWITCHES = {
	handover: [ _('Hand over'), _('Let someone at this device hand it over to AI assistants and leave. Meant for desktops; a router has no use for it.') ],
	direct: [ _('Direct transfers'), _('Allow direct peer-to-peer transfers with the account\'s other devices.') ],
	updates: [ _('Updates'), _('Install newer agent releases signed by LetKite.') ],
	env: [ _('Environment variables'), _('Take the environment variables set in the dashboard.') ],
	accelerate: [ _('Access points'), _('Reach LetKite\'s servers through its access points.') ],
	telemetry: [ _('Crash reports'), _('Send the agent\'s crash reports to LetKite: version, system and where it failed; never commands, paths or output.') ],
	mesh: [ _('Mesh network'), _('Join the account\'s mesh network, so that its other devices can reach this one as its rules allow.') ]
};

/*
 * Turning these on widens what AI assistants on the account can do or reach
 * on this router: ask first. The others are about how the agent itself runs
 * (updates, crash reports, the route to LetKite's servers).
 */
var CONFIRM = {
	handover: _('AI assistants on your LetKite account could then be handed this device to work on unattended.'),
	direct: _('AI assistants on your LetKite account could then move files between this router and the account\'s other devices directly, not only through LetKite\'s servers.'),
	env: _('The environment variables set in the dashboard would then be written on this router, for the commands AI assistants run here.'),
	mesh: _('The account\'s other devices, and the AI assistants using them, could then reach this router over the mesh network, as the account\'s rules allow.')
};

var SETTINGS = {
	shell: [ _('Commands and terminals'), _('off, sandboxed or full') ],
	files: [ _('Files'), _('The most of the file system AI assistants may be granted') ],
	deny: [ _('Always hidden'), _('Paths no one may read or write') ],
	gui: [ _('Screen'), _('off, observe or act') ],
	gui_apps: [ _('Apps on screen'), _('The apps AI assistants may see and drive') ],
	tunnel_targets: [ _('Tunnel targets'), _('Where tunnels may connect') ],
	keep_awake: [ _('Keep awake'), _('off, plugged_in or always') ],
	local_control: [ _('Pause at this device'), _('Who may pause the connection here: users or admins') ],
	exit_node: [ _('Exit node'), _('Set only on LetKite\'s own servers') ]
};

function settingText(value) {
	if (Array.isArray(value)) {
		if (!value.length)
			return _('nothing');
		if (value.length === 1 && value[0] === '*')
			return _('no limit');
		return value.join(', ');
	}
	if (typeof value == 'boolean')
		return value ? _('yes') : _('no');
	return (value == null) ? '-' : String(value);
}

function row(id, title, field) {
	return E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title', 'for': id }, title),
		E('div', { 'class': 'cbi-value-field' }, field)
	]);
}

return view.extend({
	load: function() {
		return callCeilingGet();
	},

	confirm: function(name) {
		return new Promise(function(resolve) {
			ui.showModal(_('Turn on %s?').format(SWITCHES[name][0]), [
				E('p', {}, CONFIRM[name]),
				E('p', {}, _('Only turn it on if you trust the people and assistants on that account.')),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'cbi-button cbi-button-neutral',
						'click': function() { ui.hideModal(); resolve(false); }
					}, _('Cancel')),
					' ',
					E('button', {
						'class': 'cbi-button cbi-button-negative',
						'click': function() { ui.hideModal(); resolve(true); }
					}, _('Turn on'))
				])
			]);
		});
	},

	toggle: function(name, input) {
		var value = input.checked;
		var ask = (value && CONFIRM[name]) ? this.confirm(name) : Promise.resolve(true);

		return ask.then(function(yes) {
			if (!yes) {
				input.checked = !value;
				return;
			}
			input.disabled = true;
			return callCeilingSet(name, value).then(function(res) {
				input.disabled = false;
				if (!res || res.ok === false) {
					input.checked = !value;
					ui.addNotification(null, E('p', (res && res.error) || _('The agent did not answer.')), 'danger');
				}
				else if (res.restarted) {
					ui.addNotification(null, E('p', _('Saved. The agent restarted to apply it.')), 'info');
				}
				else if (res.restart_output != null) {
					ui.addNotification(null, [
						E('p', _('Saved, but the agent did not restart, so the change is not applied yet. Restart it under System > Startup, or with /etc/init.d/letkite-agent restart.')),
						E('pre', {}, res.restart_output)
					], 'warning');
				}
				else {
					ui.addNotification(null, E('p', _('Saved. It applies when the agent next starts.')), 'info');
				}
			});
		});
	},

	renderSwitches: function(names, values) {
		var rows = [];

		names.forEach(L.bind(function(name) {
			if (typeof values[name] != 'boolean')
				return;
			var label = SWITCHES[name] || [ name, '' ];
			var id = 'letkite-sw-' + name;
			var input = E('input', { 'type': 'checkbox', 'id': id });
			input.checked = values[name];
			input.addEventListener('change', ui.createHandlerFn(this, 'toggle', name, input));
			rows.push(row(id, label[0], [ input, E('div', { 'class': 'cbi-value-description' }, label[1]) ]));
		}, this));

		return rows.length ? E('div', {}, rows) : E('p', {}, _('The agent reported no switches.'));
	},

	renderSettings: function(settings) {
		var rows = [];

		Object.keys(SETTINGS).concat(Object.keys(settings).filter(function(k) { return !SETTINGS[k]; })).forEach(function(name) {
			if (!(name in settings))
				return;
			var label = SETTINGS[name] || [ name, '' ];
			var id = 'letkite-set-' + name;
			rows.push(row(id, label[0], [
				E('code', { 'id': id }, settingText(settings[name])),
				E('div', { 'class': 'cbi-value-description' }, label[1])
			]));
		});

		return E('div', {}, [
			E('p', {}, [
				_('These are not on/off switches, so LuCI does not change them. Set them in /etc/letkite/ceiling.toml over SSH, then restart the agent.'),
				' ',
				E('a', { 'href': README, 'target': '_blank', 'rel': 'noreferrer' }, _('How to edit the ceiling'))
			]),
			E('div', {}, rows)
		]);
	},

	render: function(res) {
		var body;

		if (!res || res.ok === false) {
			body = [ E('div', { 'class': 'cbi-section' }, E('p', { 'class': 'alert-message warning' }, (res && res.error) || _('The agent did not answer.'))) ];
		}
		else if (!res.supported) {
			body = [ E('div', { 'class': 'cbi-section' }, E('p', { 'class': 'alert-message notice' },
				_('This agent version cannot change its permissions from LuCI yet; it will once it updates itself. Until then, edit /etc/letkite/ceiling.toml over SSH.'))) ];
		}
		else if (!res.ceiling || res.ceiling.valid === false) {
			body = [ E('div', { 'class': 'cbi-section' }, [
				E('p', { 'class': 'alert-message warning' }, [
					_('The agent cannot read %s, and does not start until it is fixed: %s').format(
						(res.ceiling && res.ceiling.path) || '/etc/letkite/ceiling.toml',
						(res.ceiling && res.ceiling.error) || _('no ceiling')),
					' ',
					E('a', { 'href': README, 'target': '_blank', 'rel': 'noreferrer' }, _('How to edit the ceiling'))
				])
			]) ];
		}
		else {
			body = [
				E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, _('Switches')),
					E('div', { 'class': 'cbi-section-descr' },
						_('Changes are written to %s, and the agent restarts to apply them.').format(res.ceiling.path || '/etc/letkite/ceiling.toml')),
					this.renderSwitches(res.switches || [], res.ceiling.switches || {})
				]),
				E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, _('Other limits')),
					this.renderSettings(res.ceiling.settings || {})
				])
			];
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Permissions')),
			E('div', { 'class': 'cbi-map-descr' },
				_('The most AI assistants may ever do on this router, whatever your LetKite account allows.'))
		].concat(body));
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
