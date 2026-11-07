# shellcheck shell=sh
# No agent invocation or network access during login.
if [ -f /etc/letkite/setup.toml ] && [ ! -f /etc/letkite/agent.toml ]; then
	# shellcheck disable=SC2016 # literal command for the person logging in
	printf '%s\n' 'LetKite: run `letkite-agent claim` to add this router'
fi
