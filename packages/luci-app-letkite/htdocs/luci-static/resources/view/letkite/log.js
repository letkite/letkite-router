'use strict';
'require view';
'require rpc';
'require poll';
'require dom';

/* Services > LetKite > Log: the agent's lines in the system log. */

var callLog = rpc.declare({ object: 'letkite', method: 'log', params: [ 'lines' ] });

return view.extend({
	lines: 200,

	load: function() {
		return callLog(this.lines);
	},

	show: function(res) {
		var pre = document.getElementById('letkite-log');
		var lines = (res && res.lines) || [];
		var atBottom = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 10;
		dom.content(pre, lines.length ? lines.join('\n') : _('No log lines from the agent.'));
		if (atBottom)
			pre.scrollTop = pre.scrollHeight;
	},

	refresh: function() {
		return callLog(this.lines).then(L.bind(this.show, this));
	},

	render: function(res) {
		var select = E('select', { 'class': 'cbi-input-select' }, [ 100, 200, 500, 1000 ].map(L.bind(function(n) {
			return E('option', { 'value': n, 'selected': n === this.lines ? '' : null }, _('Last %d lines').format(n));
		}, this)));
		select.addEventListener('change', L.bind(function() {
			this.lines = +select.value;
			this.refresh();
		}, this));

		var view = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Log')),
			E('div', { 'class': 'cbi-map-descr' }, _('What the agent wrote to the system log (logread -e letkite).')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', {}, [ select ]),
				E('pre', {
					'id': 'letkite-log',
					'style': 'max-height:60vh;overflow:auto;white-space:pre-wrap;font-size:90%'
				})
			])
		]);

		requestAnimationFrame(L.bind(function() {
			this.show(res);
			var pre = document.getElementById('letkite-log');
			pre.scrollTop = pre.scrollHeight;
		}, this));
		poll.add(L.bind(this.refresh, this), 10);

		return view;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
