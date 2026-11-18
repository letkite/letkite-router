'use strict';
'require view';
'require rpc';
'require ui';

/*
 * Services > LetKite > LAN routing: the devices on this router's LAN whose
 * connections follow the LetKite account's routing rules (UCI
 * letkite.lan, read by the agent every 5 seconds). The agent redirects their
 * TCP to itself while routing is on; if it stops, they go out directly again
 * within 15 seconds.
 */

var callGet = rpc.declare({ object: 'letkite', method: 'lanroute_get' });
var callSet = rpc.declare({ object: 'letkite', method: 'lanroute_set', params: [ 'enabled', 'block_quic', 'clients' ] });

var README = 'https://github.com/letkite/letkite-router#lan-routing';
var MAC = /^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/;

/* The agent's rule (lan.rs `mac`): not a group address, not all zeros. */
function deviceMac(mac) {
	return MAC.test(mac) && (parseInt(mac.substr(0, 2), 16) & 1) === 0 && mac !== '00:00:00:00:00:00';
}

var MODES = {
	'off': _('off'),
	'ai-tools': _('AI tools'),
	'rules': _('rules'),
	'global': _('everything')
};

function modeText(mode) {
	return MODES[mode] || mode || _('unknown');
}

function row(id, title, field) {
	return E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title', 'for': id }, title),
		E('div', { 'class': 'cbi-value-field' }, field)
	]);
}

return view.extend({
	load: function() {
		return callGet();
	},

	renderStatus: function(res) {
		var r = res.route || {};
		var lines = [];

		if (!r.mode) {
			lines.push(E('p', { 'class': 'alert-message warning' }, _('The agent is not running, so nothing is routed.')));
			return lines;
		}
		lines.push(E('p', {}, [ E('strong', {}, _('Routing') + ': '), modeText(r.mode) ]));
		if (r.mode === 'off')
			lines.push(E('p', { 'class': 'alert-message notice' },
				_('Routing is off for this router. Turn it on in the LetKite dashboard, under Routing; devices chosen here follow it then.')));
		if (r.lan)
			lines.push(E('p', {}, [ E('strong', {}, _('LAN') + ': '), r.lan ]));
		if (res.lan_input && res.lan_input !== 'ACCEPT')
			lines.push(E('p', { 'class': 'alert-message warning' },
				_('The firewall zone "lan" does not accept input, so chosen devices would lose their TCP connections. Set its input to accept before choosing devices.')));
		return lines;
	},

	renderDevices: function(res) {
		var chosen = {};
		var seen = {};
		var rows = [];

		(res.clients || []).forEach(function(mac) { chosen[mac] = true; });

		var add = function(mac, name, ip, zone) {
			if (seen[mac])
				return;
			seen[mac] = true;
			var box = E('input', { 'type': 'checkbox', 'data-mac': mac });
			box.checked = !!chosen[mac];
			/* the agent redirects devices on the "lan" zone's interfaces only */
			var note = (zone && zone !== 'lan')
				? E('div', { 'class': 'cbi-value-description' },
					_('Not routed: on the firewall zone "%s", not "lan".').format(zone))
				: '';
			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, box),
				E('td', { 'class': 'td' }, [ name || '-', note ]),
				E('td', { 'class': 'td' }, ip || '-'),
				E('td', { 'class': 'td' }, E('code', {}, mac))
			]));
		};

		(res.devices || []).forEach(function(d) { add(d.mac, d.name, d.ip, d.zone); });
		(res.clients || []).forEach(function(mac) { add(mac, _('(not connected now)'), ''); });

		this.table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Route')),
				E('th', { 'class': 'th' }, _('Name')),
				E('th', { 'class': 'th' }, _('IPv4 address')),
				E('th', { 'class': 'th' }, _('MAC address'))
			])
		].concat(rows));

		this.manual = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': 'aa:bb:cc:dd:ee:ff' });

		return E('div', {}, [
			this.table,
			rows.length ? '' : E('p', {}, _('No devices have an address from this router yet.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Other device')),
				E('div', { 'class': 'cbi-value-field' }, [
					this.manual,
					' ',
					E('button', {
						'class': 'cbi-button cbi-button-add',
						'click': ui.createHandlerFn(this, 'addManual')
					}, _('Add')),
					E('div', { 'class': 'cbi-value-description' }, _('A device with a fixed address: its MAC address.'))
				])
			])
		]);
	},

	addManual: function() {
		var mac = this.manual.value.trim().toLowerCase().replace(/-/g, ':');

		if (!deviceMac(mac)) {
			ui.addNotification(null, E('p', _('That is not a MAC address.')), 'warning');
			return;
		}
		if (this.table.querySelector('input[data-mac="' + mac + '"]')) {
			this.table.querySelector('input[data-mac="' + mac + '"]').checked = true;
		}
		else {
			var box = E('input', { 'type': 'checkbox', 'data-mac': mac });
			box.checked = true;
			this.table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, box),
				E('td', { 'class': 'td' }, '-'),
				E('td', { 'class': 'td' }, '-'),
				E('td', { 'class': 'td' }, E('code', {}, mac))
			]));
		}
		this.manual.value = '';
	},

	render: function(res) {
		var body;

		if (!res || res.ok === false) {
			body = [ E('div', { 'class': 'cbi-section' }, E('p', { 'class': 'alert-message warning' }, (res && res.error) || _('The agent did not answer.'))) ];
		}
		else if (res.answered === false) {
			body = [ E('div', { 'class': 'cbi-section' }, E('p', { 'class': 'alert-message warning' },
				_('The agent is not running, so nothing is routed.'))) ];
		}
		else if (!res.supported) {
			body = [ E('div', { 'class': 'cbi-section' }, E('p', { 'class': 'alert-message notice' },
				_('This agent version cannot route the LAN yet; it will once it updates itself.'))) ];
		}
		else {
			this.enabled = E('input', { 'type': 'checkbox', 'id': 'letkite-lan-enabled' });
			this.enabled.checked = !!res.enabled;
			this.quic = E('input', { 'type': 'checkbox', 'id': 'letkite-lan-quic' });
			this.quic.checked = res.block_quic !== false;
			this.devices = this.renderDevices(res);

			body = [
				E('div', { 'class': 'cbi-section' }, this.renderStatus(res)),
				E('div', { 'class': 'cbi-section' }, [
					row('letkite-lan-enabled', _('Route chosen devices'), [
						this.enabled,
						E('div', { 'class': 'cbi-value-description' },
							_('Their connections follow your account\'s routing rules. Other devices are not touched.'))
					]),
					row('letkite-lan-quic', _('Block QUIC'), [
						this.quic,
						E('div', { 'class': 'cbi-value-description' },
							_('Chosen devices cannot use QUIC (UDP port 443), so browsers use TCP, which the rules apply to. Without this, sites that use QUIC bypass the rules.'))
					])
				]),
				E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, _('Devices')),
					this.devices
				])
			];
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('LAN routing')),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Devices you choose here follow your LetKite account\'s routing rules, without the agent installed on them. Only TCP is routed. If the agent stops, they go out directly again within 15 seconds.'),
				' ',
				E('a', { 'href': README, 'target': '_blank', 'rel': 'noreferrer' }, _('More about LAN routing'))
			])
		].concat(body));
	},

	handleSave: function() {
		if (!this.enabled)
			return Promise.resolve();

		var clients = [];
		this.table.querySelectorAll('input[data-mac]').forEach(function(box) {
			if (box.checked)
				clients.push(box.getAttribute('data-mac'));
		});

		return callSet(this.enabled.checked, this.quic.checked, clients).then(function(res) {
			if (!res || res.ok === false)
				ui.addNotification(null, E('p', (res && res.error) || _('The agent did not answer.')), 'danger');
			else
				ui.addNotification(null, E('p', _('Saved. The agent applies it within 5 seconds.')), 'info');
		});
	},

	handleSaveApply: null,
	handleReset: null
});
