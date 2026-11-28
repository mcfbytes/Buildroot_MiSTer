# SPDX-License-Identifier: GPL-3.0-or-later
# Clock-domain crossings inside de25_hdmi (docs/de25-base-image.md §6.2). The base design defines
# clk and pclk; these paths are synchronised by two-flop stages or held stable by a handshake.

# Toggles into their first synchroniser stage.
set_false_path -to [get_keepers {*u_f|s_freq[0] *u_f|s_lreq[0] *u_f|p_fack[0]}]

# Bundled data, stable from before its toggle until after the far side has sampled it.
set_false_path -from [get_keepers {*u_f|p_lrow[*] *u_f|p_lbuf}]
set_false_path -from [get_keepers {*u_f|f_en *u_f|f_w[*] *u_f|f_h[*] *u_f|f_x0[*] *u_f|f_y0[*] *u_f|scale[*]}] \
               -to [get_keepers {*u_f|p_*}]

# Reset synchronisers: asynchronous assertion into the first stages.
set_false_path -to [get_keepers {*srst[*] *prst[*]}]
