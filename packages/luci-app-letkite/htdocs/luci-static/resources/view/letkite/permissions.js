'use strict';
'require view';
'require rpc';
'require ui';
'require dom';

/*
 * Services > LetKite > Permissions: the top-level switches of the agent's
 * local ceiling (/etc/letkite/ceiling.toml), the most AI assistants may ever
 * be granted on this router, whatever the account allows.
 */

var callCeilingGet = rpc.declare({ object: 'letkite', method: 'ceiling_get' });
var callCeilingSet = rpc.declare({ object: 'letkite', method: 'ceiling_set', params: [ 'switch', 'value' ] });

/* Turning these on lets an AI assistant act on the router itself: ask first. */
var DANGEROUS = { exec: true, shell: true, terminal: true, files: true };

var LABELS = {
	exec: [ _('Run commands'), _('Run commands on this router.') ],
	files: [ _('Files'), _('Read and write files on this router.') ],
	shell: [ _('Shell'), _('Keep shell sessions open on this router.') ],
	terminal: [ _('Terminal'), _('Open interactive terminals on this router.') ],
	mesh: [ _('Mesh network'), _('Join the account\'s mesh network, so that its other devices can reach this one as its rules allow.') ],
	exit: [ _('Network exit'), _('Let other devices of the account send their traffic out through this router.') ],
	env: [ _('Environment variables'), _('Take the environment variables set in the dashboard.') ],
	telemetry: [ _('Diagnostics'), _('Send diagnostics that help LetKite fix problems.') ],
	direct: [ _('Direct transfers'), _('Allow direct peer-to-peer transfers.') ],
	updates: [ _('Updates'), _('Install newer agent releases signed by LetKite.') ],
	accelerate: [ _('Access points'), _('Reach LetKite\'s servers through its access points.') ]
};

return view.extend({
	load: function() {
		return callCeilingGet();
	},

	confirm: function(name) {
		return new Promise(function(resolve) {
			ui.showModal(_('Allow %s?').format(LABELS[name] ? LABELS[name][0] : name), [
				E('p', {}, _('This lets AI assistants on your LetKite account act on this router directly, as root, within the rules set in the dashboard. Only allow it if you trust the people and assistants on that account.')),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'cbi-button cbi-button-neutral',
						'click': function() { ui.hideModal(); resolve(false); }
					}, _('Cancel')),
					' ',
					E('button', {
						'class': 'cbi-button cbi-button-negative',
						'click': function() { ui.hideModal(); resolve(true); }
					}, _('Allow'))
				])
			]);
		});
	},

	toggle: function(name, input) {
		var value = input.checked;
		var ask = (value && DANGEROUS[name]) ? this.confirm(name) : Promise.resolve(true);

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
				else {
					ui.addNotification(null, E('p', _('Saved.')), 'info');
				}
			});
		});
	},

	render: function(res) {
		var body;

		if (!res || res.ok === false) {
			body = E('p', { 'class': 'alert-message warning' }, (res && res.error) || _('The agent did not answer.'));
		}
		else if (!res.supported) {
			body = E('p', { 'class': 'alert-message notice' },
				_('This agent version cannot change its permissions from LuCI yet; it will once it updates itself. Until then, edit /etc/letkite/ceiling.toml over SSH.'));
		}
		else {
			var ceiling = res.ceiling || {};
			var values = ceiling.switches || ceiling;
			var rows = [];

			(res.switches || []).forEach(L.bind(function(name) {
				if (typeof values[name] != 'boolean')
					return;
				var label = LABELS[name] || [ name, '' ];
				var input = E('input', { 'type': 'checkbox', 'id': 'letkite-sw-' + name });
				input.checked = values[name];
				input.addEventListener('change', ui.createHandlerFn(this, 'toggle', name, input));
				rows.push(E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title', 'for': 'letkite-sw-' + name }, label[0]),
					E('div', { 'class': 'cbi-value-field' }, [
						input,
						E('div', { 'class': 'cbi-value-description' }, label[1])
					])
				]));
			}, this));

			body = rows.length ? E('div', {}, rows) : E('p', {}, _('The agent reported no switches.'));
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Permissions')),
			E('div', { 'class': 'cbi-map-descr' },
				_('The most AI assistants may ever do on this router, whatever your LetKite account allows. Changes are written to /etc/letkite/ceiling.toml.')),
			E('div', { 'class': 'cbi-section' }, body)
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
