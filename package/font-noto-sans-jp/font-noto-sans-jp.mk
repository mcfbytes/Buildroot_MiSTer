################################################################################
#
# font-noto-sans-jp
#
################################################################################

# The Japanese region subset of Noto Sans CJK (family "Noto Sans JP"); see docs/slint.md.
FONT_NOTO_SANS_JP_VERSION = 2.004
FONT_NOTO_SANS_JP_SOURCE = 16_NotoSansJP.zip
FONT_NOTO_SANS_JP_SITE = https://github.com/notofonts/noto-cjk/releases/download/Sans$(FONT_NOTO_SANS_JP_VERSION)
FONT_NOTO_SANS_JP_LICENSE = OFL-1.1
FONT_NOTO_SANS_JP_LICENSE_FILES = LICENSE

define FONT_NOTO_SANS_JP_EXTRACT_CMDS
	$(UNZIP) -d $(@D) $(FONT_NOTO_SANS_JP_DL_DIR)/$(FONT_NOTO_SANS_JP_SOURCE)
endef

ifeq ($(BR2_PACKAGE_FONT_NOTO_SANS_JP_ALL_WEIGHTS),y)
FONT_NOTO_SANS_JP_FILES = NotoSansJP-*.otf
else
FONT_NOTO_SANS_JP_FILES = NotoSansJP-Regular.otf NotoSansJP-Bold.otf
endif

define FONT_NOTO_SANS_JP_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/fonts/noto-sans-jp
	cd $(@D) && \
		$(INSTALL) -m 0644 $(FONT_NOTO_SANS_JP_FILES) \
			$(TARGET_DIR)/usr/share/fonts/noto-sans-jp/
endef

$(eval $(generic-package))
