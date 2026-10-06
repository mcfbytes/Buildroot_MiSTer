################################################################################
#
# font-noto-sans
#
################################################################################

FONT_NOTO_SANS_VERSION = 2.015
FONT_NOTO_SANS_SOURCE = NotoSans-v$(FONT_NOTO_SANS_VERSION).zip
FONT_NOTO_SANS_SITE = https://github.com/notofonts/latin-greek-cyrillic/releases/download/NotoSans-v$(FONT_NOTO_SANS_VERSION)
FONT_NOTO_SANS_LICENSE = OFL-1.1
FONT_NOTO_SANS_LICENSE_FILES = OFL.txt

define FONT_NOTO_SANS_EXTRACT_CMDS
	$(UNZIP) -d $(@D) $(FONT_NOTO_SANS_DL_DIR)/$(FONT_NOTO_SANS_SOURCE)
endef

ifeq ($(BR2_PACKAGE_FONT_NOTO_SANS_ALL_WEIGHTS),y)
FONT_NOTO_SANS_FILES = NotoSans-*.ttf
else
FONT_NOTO_SANS_FILES = \
	NotoSans-Regular.ttf NotoSans-Italic.ttf \
	NotoSans-Bold.ttf NotoSans-BoldItalic.ttf
endif

# Unhinted static TTFs: smallest set that every rasteriser (FreeType, Slint) renders.
define FONT_NOTO_SANS_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/fonts/noto-sans
	cd $(@D)/NotoSans/unhinted/ttf && \
		$(INSTALL) -m 0644 $(FONT_NOTO_SANS_FILES) \
			$(TARGET_DIR)/usr/share/fonts/noto-sans/
endef

$(eval $(generic-package))
