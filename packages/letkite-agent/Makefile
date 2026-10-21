# SPDX-License-Identifier: MIT
#
# letkite-agent: installs the LetKite agent, a signed program released by
# LetKite, on OpenWrt. The package does not contain the program: its
# pre-install script (files/fetch.sh) downloads the release pinned in
# files/release and checks its SHA-256; the agent's own `install` then sets up
# the procd service. See README.md.

include $(TOPDIR)/rules.mk

PKG_NAME:=letkite-agent
PKG_VERSION:=$(shell sed -n 's/^AGENT_VERSION=//p' $(CURDIR)/files/release)
PKG_RELEASE:=1

PKG_MAINTAINER:=LetKite <contact@letkite.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=

include $(INCLUDE_DIR)/package.mk

define Package/letkite-agent
  SECTION:=net
  CATEGORY:=Network
  TITLE:=LetKite agent (downloads and verifies the signed release)
  URL:=https://letkite.com
  DEPENDS:=+ca-bundle +uclient-fetch
  PKGARCH:=all
endef

define Package/letkite-agent/description
  Installs the LetKite agent, which connects this router to a LetKite
  account so that AI assistants can reach it and the devices behind it,
  within the limits set on the router. The agent is a closed-source program
  signed by LetKite; this package downloads the release pinned in it from
  get.letkite.com, checks its SHA-256, and lets the agent install its own
  procd service. The agent then updates itself.
  Supported: x86_64, aarch64, and ARMv7 with VFPv3.
endef

# The pre-install script: the release table, then the script that uses it.
# $(file <...) keeps the files as they are (newlines, $).
define newline


endef
LETKITE_PREINST:=\#!/bin/sh$(newline)$(file <$(CURDIR)/files/release)$(newline)$(file <$(CURDIR)/files/fetch.sh)

Package/letkite-agent/preinst=$(LETKITE_PREINST)

define Package/letkite-agent/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
agent=/opt/letkite-agent/letkite-agent
[ -x "$$agent" ] || { echo "letkite-agent: $$agent is missing; reinstall this package" >&2; exit 1; }
[ -e /usr/bin/letkite-agent ] || ln -s "$$agent" /usr/bin/letkite-agent
# the service is the agent's own (init script, sysupgrade keep list)
if "$$agent" install; then
	exit 0
fi
if [ ! -f /etc/letkite/agent.toml ]; then
	echo "letkite-agent: not paired yet. Pair this router in LuCI (Services > LetKite)"
	echo "or with 'letkite-agent enroll'; the service is installed once it is paired."
	exit 0
fi
echo "letkite-agent: 'letkite-agent install' failed" >&2
exit 1
endef

define Package/letkite-agent/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
agent=/opt/letkite-agent/letkite-agent
if [ -e /etc/init.d/letkite-agent ] && [ -x "$$agent" ]; then
	"$$agent" uninstall || echo "letkite-agent: 'letkite-agent uninstall' failed; removing the service" >&2
fi
if [ -e /etc/init.d/letkite-agent ]; then
	/etc/init.d/letkite-agent stop
	/etc/init.d/letkite-agent disable
	rm -f /etc/init.d/letkite-agent
fi
rm -f /lib/upgrade/keep.d/letkite-agent
[ "$$(readlink /usr/bin/letkite-agent)" = "$$agent" ] && rm -f /usr/bin/letkite-agent
# the program (and an update's leftovers); /etc/letkite (node key,
# enrollment, ceiling) stays: rm -rf /etc/letkite to forget the node
rm -rf /opt/letkite-agent
exit 0
endef

define Build/Compile
endef

define Package/letkite-agent/install
	$(INSTALL_DIR) $(1)/usr/share/letkite-agent
	$(INSTALL_DATA) ./files/release $(1)/usr/share/letkite-agent/release
endef

$(eval $(call BuildPackage,letkite-agent))
