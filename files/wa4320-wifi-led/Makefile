include $(TOPDIR)/rules.mk

PKG_NAME:=wa4320-wifi-led
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/wa4320-wifi-led
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=H3C WA4320 WiFi LED control
  DEPENDS:=+ubus +jsonfilter
endef

define Build/Compile
endef

define Package/wa4320-wifi-led/install
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/usr/sbin
	$(INSTALL_BIN) ./files/wa4320-wifi-led.init $(1)/etc/init.d/wa4320-wifi-led
	$(INSTALL_BIN) ./files/wa4320-wifi-led.sh $(1)/usr/sbin/wa4320-wifi-led
endef

$(eval $(call BuildPackage,wa4320-wifi-led))
