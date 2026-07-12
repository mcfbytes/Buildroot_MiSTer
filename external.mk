################################################################################
#
# external.mk for the MISTER BR2_EXTERNAL tree
#
# Pulls in every package .mk under package/*/*.mk. Nothing lives there yet —
# P3.1-P3.3 add the Realtek Wi-Fi (rtl8188eu, rtl8188fu, rtl8812au, rtl8821au,
# rtl8821cu, rtl88x2bu) and xone kernel-module packages (see PLAN.md §6,
# TASKS.md class E). This is the standard Buildroot br2-external idiom, so new
# packages need no change here — just add package/<name>/<name>.mk.
#
################################################################################

include $(sort $(wildcard $(BR2_EXTERNAL_MISTER_PATH)/package/*/*.mk))
