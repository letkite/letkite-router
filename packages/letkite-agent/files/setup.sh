#!/bin/sh
# Shared by postinst and uci-defaults (first boot of a firmware image).
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
agent=/opt/letkite-agent/letkite-agent
if [ ! -x "$agent" ]; then
	echo "letkite-agent: $agent is missing; provide a verified agent in the image or reinstall the package" >&2
	exit 1
fi
[ -e /usr/bin/letkite-agent ] || ln -s "$agent" /usr/bin/letkite-agent
if [ "$(uci -q get letkite.main.claim)" = 1 ]; then
	# Never rewrite a manufacturer's setup.toml (custom gateway/name/CA), or
	# an existing identity. Plain install honours setup.toml too.
	if [ ! -f /etc/letkite/setup.toml ] && [ ! -f /etc/letkite/agent.toml ]; then
		if "$agent" install --claim; then
			exit 0
		fi
		[ "${1:-}" = --firstboot ] && exit 1
		echo "letkite-agent: claim setup failed; falling back to legacy install and LuCI pairing" >&2
	fi
fi
if "$agent" install; then
	exit 0
fi
# Compatibility with agents that cannot install a service before enrollment.
if [ "${1:-}" != --firstboot ]; then
	echo "letkite-agent: service setup deferred; pair in LuCI or enroll over SSH."
	exit 0
fi
exit 1
