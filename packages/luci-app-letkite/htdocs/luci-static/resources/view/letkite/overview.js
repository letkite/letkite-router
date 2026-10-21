'use strict';
'require view';
'require rpc';
'require ui';
'require poll';
'require dom';
'require letkite.qrcode as qrcode';

/*
 * Services > LetKite > Overview: the agent's state, pairing this router
 * with a LetKite account, and pausing or resuming the agent. Everything goes
 * through the rpcd plugin "letkite" (/usr/libexec/rpcd/letkite).
 */

var callStatus = rpc.declare({ object: 'letkite', method: 'status' });
var callEnrollStart = rpc.declare({ object: 'letkite', method: 'enroll_start', params: [ 'name' ] });
var callEnrollPoll = rpc.declare({ object: 'letkite', method: 'enroll_poll' });
var callPause = rpc.declare({ object: 'letkite', method: 'pause', params: [ 'duration' ] });
var callResume = rpc.declare({ object: 'letkite', method: 'resume' });

var DASHBOARD = 'https://dashboard.letkite.com';
var DOCS = 'https://github.com/letkite/letkite-router#readme';
var DURATION = /^[0-9]{1,4}[mhd]$/;
var NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/;

function httpsLink(url) {
	return (typeof url == 'string' && /^https:\/\/[^\s"'<>]+$/.test(url)) ? url : null;
}

function when(seconds) {
	return new Date(seconds * 1000).toLocaleString();
}

function row(label, value) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '33%' }, [ label ]),
		E('td', { 'class': 'td left' }, [ value ])
	]);
}

function failed(res) {
	return !res || res.ok === false;
}

return view.extend({
	enrollPolling: false,

	load: function() {
		return callStatus();
	},

	statusTable: function(st) {
		var a = (st && st.agent) || {};

		if (!st || !st.installed)
			return E('p', { 'class': 'alert-message warning' },
				_('The LetKite agent is not installed. Reinstall the letkite-agent package.'));

		var connection;
		if (a.paused)
			connection = a.paused_until
				? _('Paused until %s').format(when(a.paused_until))
				: _('Paused until resumed');
		else if (a.connected === true)
			connection = _('Connected');
		else if (a.connected === false)
			connection = _('Not connected');
		else
			connection = '-';

		var rows = [
			row(_('Agent version'), a.version || '-'),
			row(_('Paired'), a.enrolled
				? (a.name ? _('Yes, as %s').format(a.name) : _('Yes'))
				: _('No')),
			row(_('Connection'), connection),
			row(_('Service'), a.service_running ? _('Running') : _('Not running'))
		];
		if (a.node_id)
			rows.push(row(_('Node'), a.node_id));
		if (a.last_error)
			rows.push(row(_('Last error'), a.last_error));

		var out = [ E('table', { 'class': 'table' }, rows) ];
		if (!st.cli)
			out.push(E('p', { 'class': 'alert-message notice' },
				_('This agent version does not report its full status to LuCI yet; it will once it updates itself.')));
		return E('div', {}, out);
	},

	renderStatus: function(st) {
		this.status = st;
		dom.content(document.getElementById('letkite-status'), this.statusTable(st));
		dom.content(document.getElementById('letkite-pair'), this.pairSection(st));
		dom.content(document.getElementById('letkite-pause'), this.pauseSection(st));
	},

	refresh: function() {
		return callStatus().then(L.bind(this.renderStatus, this));
	},

	/* Pairing: the agent shows a code to approve after signing in. */

	pairSection: function(st) {
		if (!st || !st.installed || (st.agent && st.agent.enrolled))
			return E('div');
		if (this.enrollPolling || st.enrolling) {
			this.startEnrollPoll();
			return E('div', { 'id': 'letkite-enroll' }, [ E('p', { 'class': 'spinning' }, _('Starting…')) ]);
		}

		var name = E('input', {
			'class': 'cbi-input-text',
			'type': 'text',
			'placeholder': _('optional; the host name by default'),
			'maxlength': 63
		});

		return E('div', {}, [
			E('h3', {}, _('Pair this router')),
			E('p', {}, _('Pairing connects this router to your LetKite account. You will get a code to approve after signing in.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Name')),
				E('div', { 'class': 'cbi-value-field' }, [ name ])
			]),
			E('button', {
				'class': 'cbi-button cbi-button-action important',
				'click': ui.createHandlerFn(this, function() {
					var n = name.value.trim();
					if (n && !NAME.test(n)) {
						ui.addNotification(null, E('p', _('A name is 1 to 63 letters, digits, dots, dashes and underscores.')), 'warning');
						return;
					}
					return callEnrollStart(n || null).then(L.bind(function(res) {
						if (failed(res)) {
							ui.addNotification(null, E('p', res ? res.error : _('Pairing could not start.')), 'danger');
							return;
						}
						this.enrollPolling = true;
						return this.refresh();
					}, this));
				})
			}, _('Pair'))
		]);
	},

	startEnrollPoll: function() {
		if (this.enrollPollFn)
			return;
		this.enrollPollFn = L.bind(function() {
			return callEnrollPoll().then(L.bind(this.renderEnroll, this));
		}, this);
		poll.add(this.enrollPollFn, 2);
	},

	stopEnrollPoll: function() {
		if (this.enrollPollFn)
			poll.remove(this.enrollPollFn);
		this.enrollPollFn = null;
		this.enrollPolling = false;
	},

	renderEnroll: function(res) {
		var box = document.getElementById('letkite-enroll');
		if (!box || !res)
			return;

		if (res.state === 'code' && res.code) {
			var link = httpsLink(res.code.verification_uri_complete) || httpsLink(res.code.verification_uri);
			var parts = [
				E('h3', {}, _('Approve this router')),
				E('p', {}, _('Open the link, sign in to LetKite and approve the code. You can scan the QR code with your phone.')),
				E('p', { 'style': 'font-size:2em;font-family:monospace;letter-spacing:.1em' }, res.code.user_code || '')
			];
			if (link) {
				parts.push(E('p', {}, E('a', { 'href': link, 'target': '_blank', 'rel': 'noopener noreferrer' }, link)));
				parts.push(E('div', { 'style': 'margin:1em 0' }, qrcode.svg(link, 220)));
			}
			if (res.code.expires_in)
				parts.push(E('p', { 'class': 'cbi-value-description' },
					_('The code is valid for %d minutes.').format(Math.round(res.code.expires_in / 60))));
			parts.push(E('p', { 'class': 'spinning' }, _('Waiting for approval…')));
			dom.content(box, parts);
		}
		else if (res.state === 'enrolled') {
			if (res.running)
				return dom.content(box, E('p', { 'class': 'spinning' }, _('Approved; starting the service…')));
			this.stopEnrollPoll();
			var msg = [ E('p', {}, res.name ? _('Paired as %s.').format(res.name) : _('Paired.')) ];
			if (res.service_installed === false)
				msg.push(E('pre', {}, res.install_output || ''));
			ui.addNotification(null, msg, res.service_installed === false ? 'warning' : 'info');
			return this.refresh();
		}
		else if (res.state === 'error') {
			this.stopEnrollPoll();
			var err = res.error || {};
			dom.content(box, [
				E('p', { 'class': 'alert-message warning' }, _('Pairing failed: %s').format(err.message || err.code || _('unknown error'))),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function() { return this.refresh(); })
				}, _('Try again'))
			]);
		}
		else if (!res.running && res.state === 'idle') {
			this.stopEnrollPoll();
			return this.refresh();
		}
	},

	/* Pause and resume. */

	pauseSection: function(st) {
		var a = (st && st.agent) || {};
		if (!st || !st.installed || !a.enrolled)
			return E('div');

		var self = this;
		function run(fn, arg) {
			return fn(arg).then(function(res) {
				if (failed(res))
					ui.addNotification(null, E('p', res ? res.error : _('The agent did not answer.')), 'danger');
				return self.refresh();
			});
		}

		if (a.paused)
			return E('div', {}, [
				E('h3', {}, _('Paused')),
				E('p', {}, _('AI assistants cannot reach this router until it is resumed.')),
				E('button', {
					'class': 'cbi-button cbi-button-positive',
					'click': ui.createHandlerFn(this, function() { return run(callResume); })
				}, _('Resume'))
			]);

		var custom = E('input', {
			'class': 'cbi-input-text',
			'type': 'text',
			'placeholder': _('e.g. 45m, 2h, 3d'),
			'size': 8,
			'maxlength': 5
		});

		var btn = function(label, duration) {
			return E('button', {
				'class': 'cbi-button cbi-button-neutral',
				'style': 'margin-right:.5em',
				'click': ui.createHandlerFn(self, function() { return run(callPause, duration); })
			}, label);
		};

		return E('div', {}, [
			E('h3', {}, _('Pause')),
			E('p', {}, _('Pausing disconnects the agent: AI assistants cannot reach this router or its network until the time is up or it is resumed.')),
			E('div', {}, [
				btn(_('30 minutes'), '30m'),
				btn(_('1 hour'), '1h'),
				btn(_('1 day'), '1d'),
				btn(_('Until resumed'), null)
			]),
			E('div', { 'style': 'margin-top:.5em' }, [
				custom, ' ',
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'click': ui.createHandlerFn(this, function() {
						var d = custom.value.trim();
						if (!DURATION.test(d)) {
							ui.addNotification(null, E('p', _('A duration is a number and m, h or d, e.g. 30m, 1h, 1d.')), 'warning');
							return;
						}
						return run(callPause, d);
					})
				}, _('Pause for'))
			])
		]);
	},

	render: function(st) {
		var view = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('LetKite')),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('The LetKite agent lets AI assistants on your LetKite account reach this router and the devices behind it, within the permissions you set here.'),
				' ',
				E('a', { 'href': DASHBOARD, 'target': '_blank', 'rel': 'noopener noreferrer' }, _('Open the dashboard')),
				' · ',
				E('a', { 'href': DOCS, 'target': '_blank', 'rel': 'noopener noreferrer' }, _('Documentation'))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Status')),
				E('div', { 'id': 'letkite-status' }, this.statusTable(st))
			]),
			E('div', { 'class': 'cbi-section', 'id': 'letkite-pair' }, this.pairSection(st)),
			E('div', { 'class': 'cbi-section', 'id': 'letkite-pause' }, this.pauseSection(st))
		]);

		this.status = st;
		poll.add(L.bind(function() {
			if (this.enrollPollFn)
				return;
			return callStatus().then(L.bind(function(next) {
				dom.content(document.getElementById('letkite-status'), this.statusTable(next));
				var was = this.status || {}, wa = was.agent || {}, na = (next && next.agent) || {};
				if (!!wa.enrolled !== !!na.enrolled || !!wa.paused !== !!na.paused || wa.paused_until !== na.paused_until || !!was.installed !== !!(next && next.installed))
					this.renderStatus(next);
				this.status = next;
			}, this));
		}, this), 10);

		return view;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
