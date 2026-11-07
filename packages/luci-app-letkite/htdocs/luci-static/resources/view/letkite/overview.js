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
var callClaim = rpc.declare({ object: 'letkite', method: 'claim_status', timeout: 30000 });
var callEnrollStart = rpc.declare({ object: 'letkite', method: 'enroll_start', params: [ 'name' ] });
var callEnrollPoll = rpc.declare({ object: 'letkite', method: 'enroll_poll' });
var callPause = rpc.declare({ object: 'letkite', method: 'pause', params: [ 'duration' ] });
var callResume = rpc.declare({ object: 'letkite', method: 'resume' });

var DASHBOARD = 'https://dashboard.letkite.com';
var DOCS = 'https://github.com/letkite/letkite-router#readme';
var DURATION = /^[0-9]{1,4}[mhd]$/;

function httpsLink(url) {
	return (typeof url == 'string' && /^https:\/\/[^\s"'<>]+$/.test(url)) ? url : null;
}

function terminalError(enrollment) {
	return enrollment && enrollment.error && [ 'expired', 'unreachable' ].indexOf(enrollment.error) < 0;
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
	claimStopped: false,

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
		var before = (this.status && this.status.agent) || {}, after = (st && st.agent) || {};
		this.status = st;
		dom.content(document.getElementById('letkite-status'), this.statusTable(st));
		dom.content(document.getElementById('letkite-pair'), this.pairSection(st));
		if (!!before.enrolled !== !!after.enrolled || !!before.paused !== !!after.paused || before.paused_until !== after.paused_until)
			dom.content(document.getElementById('letkite-pause'), this.pauseSection(st));
	},

	refresh: function() {
		return callStatus().then(L.bind(this.renderStatus, this));
	},

	/* Claim uses short status calls; old agents retain explicit enrollment. */
	pairSection: function(st) {
		var a = (st && st.agent) || {}, en = a.enrollment || {};
		if (!st || !st.installed)
			return E('div');
		if (a.enrolled && a.last_error)
			return E('p', { 'class': 'alert-message warning' }, a.last_error);
		if (a.enrolled)
			return E('p', { 'class': 'alert-message success' }, a.name ? _('Paired as %s.').format(a.name) : _('Paired.'));

		if (!L.hasViewPermission())
			return E('div');
		var parts = [ E('h3', {}, _('Pair this router')) ];
		if (st.error || (en.error && en.error !== 'expired')) {
			parts.push(E('p', { 'class': 'alert-message warning' },
				_('Pairing failed: %s').format(st.error || en.problem || en.error)));
		}
		if (this.legacy && !this.enrolling) {
			parts.push(E('button', {
				'class': 'cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, function() {
					return callEnrollStart('').then(L.bind(function(res) {
						if (failed(res)) {
							ui.addNotification(null, E('p', res.error), 'warning');
							return;
						}
						this.enrolling = true;
						this.nextStatus = 0;
						this.renderStatus(this.status);
					}, this));
				})
			}, _('Pair')));
			return E('div', {}, parts);
		}
		if (this.claimStopped) {
			parts.push(E('button', {
				'class': 'cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, function() {
					this.claimStopped = false;
					this.nextStatus = 0;
				})
			}, _('Try again')));
			return E('div', {}, parts);
		}
		var remaining = Math.max(0, Math.ceil((en.expires_at || 0) - Date.now() / 1000));
		if (en.user_code && remaining) {
			parts.push(E('p', { 'style': 'font-size:2.5em;font-family:monospace;letter-spacing:.1em' }, en.user_code));
			var fallback = httpsLink(en.verification_uri), complete = httpsLink(en.verification_uri_complete);
			var dashboard = fallback && /^https:\/\/id\.[^/]+\//.test(fallback)
				? fallback.replace(/^https:\/\/id\.([^/]+)\/.*$/, 'https://dashboard.$1') : DASHBOARD;
			parts.push(E('p', {}, _('Enter it at %s → Add device → Enter the code').format(dashboard)));
			parts.push(E('p', {}, E('a', { 'href': dashboard, 'target': '_blank', 'rel': 'noopener noreferrer' }, _('Open the dashboard'))));
			if (fallback)
				parts.push(E('p', {}, E('a', { 'href': fallback, 'target': '_blank', 'rel': 'noopener noreferrer' }, fallback)));
			if (complete)
				parts.push(E('div', { 'style': 'margin:1em 0' }, qrcode.svg(complete, 220)));
			parts.push(E('p', { 'role': 'timer', 'id': 'letkite-countdown' }, _('Code expires in %d seconds.').format(remaining)));
			parts.push(E('p', { 'class': 'spinning' }, _('Waiting for approval…')));
		}
		else {
			parts.push(E('p', { 'class': 'spinning' }, _('Starting…')));
			if (en.problem)
				parts.push(E('p', {}, en.problem));
		}
		return E('div', {}, parts);
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
		this.claimStopped = !!terminalError(st && st.agent && st.agent.enrollment);
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
		var self = this;
		var stop = function() {
			self.closed = true;
			poll.remove(tick);
			window.removeEventListener('pagehide', stop);
		};
		var tick = function() {
			if (!view.isConnected) {
				stop();
				return;
			}
			if (self.closed)
				return;
			var current = (self.status && self.status.agent && self.status.agent.enrollment) || {};
			var timer = document.getElementById('letkite-countdown');
			if (timer && current.user_code)
				dom.content(timer, _('Code expires in %d seconds.').format(Math.max(0, Math.ceil(current.expires_at - Date.now() / 1000))));
			if (self.busy || Date.now() < (self.nextStatus || 0))
				return;
			var a = (self.status && self.status.agent) || {};
			var claim = self.status.installed && !a.enrolled && !self.legacy && !self.claimStopped && L.hasViewPermission();
			var enrolling = self.legacy && self.enrolling && L.hasViewPermission();
			self.busy = true;
			return (enrolling ? callEnrollPoll() : claim ? callClaim() : callStatus()).then(function(next) {
				if (self.closed || !view.isConnected)
					return;
				if (next.unsupported) {
					self.legacy = true;
					self.enrolling = !!self.status.enrolling;
					self.renderStatus(self.status);
					return;
				}
				if (enrolling) {
					var legacyAgent = Object.assign({}, self.status.agent);
					if (next.state === 'enrolled' && next.running)
						return;
					if (next.state === 'enrolled') {
						self.enrolling = false;
						legacyAgent.enrolled = true;
						legacyAgent.name = next.name;
						legacyAgent.enrollment = {};
					}
					else if (next.state === 'error' || !next.running) {
						self.enrolling = false;
						legacyAgent.enrollment = {};
					}
					else if (next.code) {
						var old = legacyAgent.enrollment || {};
						legacyAgent.enrollment = Object.assign({}, next.code, {
							expires_at: old.user_code === next.code.user_code ? old.expires_at : Date.now() / 1000 + next.code.expires_in
						});
					}
					next = Object.assign({}, self.status, { agent: legacyAgent, error: next.error && next.error.message });
				}
				if (failed(next))
					next = Object.assign({}, self.status, next);
				var enrollment = (next.agent && next.agent.enrollment) || {};
				if (failed(next) || terminalError(enrollment))
					self.claimStopped = true;
				if (self.claimStopped && !next.agent.enrolled && !next.error && self.status.error)
					next.error = self.status.error;
				self.renderStatus(next);
			}).catch(function(err) {
				if (!self.closed && view.isConnected)
					ui.addNotification(null, E('p', err.message), 'warning');
			}).finally(function() {
				self.busy = false;
				var active = self.status.installed && L.hasViewPermission() && !self.status.agent.enrolled
					&& (self.enrolling || (!self.legacy && !self.claimStopped));
				self.nextStatus = Date.now() + (active ? 3000 : 10000);
			});
		};
		window.addEventListener('pagehide', stop);
		poll.add(tick, 1);

		return view;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
