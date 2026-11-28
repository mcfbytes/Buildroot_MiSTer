################################################################################
#
# de25-fpga-load
#
################################################################################

# Our own source, kept in this package (docs/de25-fpga-reconfig.md §12).
DE25_FPGA_LOAD_VERSION = 1.0
DE25_FPGA_LOAD_SITE = $(BR2_EXTERNAL_MISTER_PATH)/package/de25-fpga-load/src
DE25_FPGA_LOAD_SITE_METHOD = local
DE25_FPGA_LOAD_LICENSE = GPL-2.0-only

$(eval $(kernel-module))
$(eval $(generic-package))
