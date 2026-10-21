# SPDX-License-Identifier: MIT
#
# luci-app-letkite: Services > LetKite in LuCI. Pairs the router with a
# LetKite account, pauses and resumes the agent, sets its permissions and
# shows its log, through the agent's command line (an rpcd plugin).

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-letkite
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=LetKite <contact@letkite.com>

LUCI_TITLE:=LuCI support for the LetKite agent
LUCI_DESCRIPTION:=Pair this router with a LetKite account, pause and resume \
	the agent, choose what AI assistants may do here, and read its log.
LUCI_DEPENDS:=+letkite-agent +luci-base +jsonfilter
LUCI_PKGARCH:=all

PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)
PKG_SRC_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

define Package/luci-app-letkite/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache
/etc/init.d/rpcd reload
exit 0
endef

define Package/luci-app-letkite/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
# a pairing still waiting for its code to be approved
for f in enroll.pid enroll.agent.pid; do
	pid=$$(cat "/var/run/letkite/$$f" 2>/dev/null)
	[ -n "$$pid" ] && kill "$$pid" 2>/dev/null
done
rm -rf /var/run/letkite
exit 0
endef

define Package/luci-app-letkite/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache
/etc/init.d/rpcd reload
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
