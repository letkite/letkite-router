#!/bin/sh
# Run locally on OpenWrt after a secure manual install. No status refresh,
# enrollment output, configuration contents, logs, or mutations.
agent=/opt/letkite-agent/letkite-agent
[ -x "$agent" ] || { echo 'LetKite executable missing'; exit 1; }
"$agent" --version || exit 1
[ -x /etc/init.d/letkite-agent ] || { echo 'Agent-owned service missing; finish pairing/setup'; exit 1; }
/etc/init.d/letkite-agent running || { echo 'Agent service not running'; exit 1; }
[ -f /etc/letkite/ceiling.toml ] || { echo 'Local access ceiling missing'; exit 1; }
echo 'Service running; ceiling present (connectivity and policy contents not assessed)'
