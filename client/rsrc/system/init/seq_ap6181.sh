# WL_REG_ON GPIO7_1 mux 
#himm 0x200f00E4 0

# GPIO7_1 dir out
#himm 0x201b0400 0x2

# GPIO7_1 ON
#himm 0x201b0008 0x2

# GPIO7_1 OFF
#himm 0x201b0008 0x0

# GPIO4_5 mux ETHERNET_POWER_EN
#himm 0x200f0068 0

# GPIO4_6 mux WIFI_POWER_EN
himm 0x200f006c 0x0 

# GPIO4_5 dir out
#himm 0x20180400 0x20

# GPIO4_6 dir out
himm 0x20180400 0x40

# GPIO4_5 ON
#himm 0x20180080 0x20

# GPIO4_5 OFF
#himm 0x20180080 0x0

# GPIO4_6 ON
himm 0x20180100 0x40

# GPIO4_6 OFF
#himm 0x20180100 0x0

# SDIO1_CCMD MUX
himm 0x200f0010 0x4

# SDIO1_CARD_DETECT MUX
himm 0x200f0014 0x4

# SDIO1_CWPR MUX
himm 0x200f0018 0x4

# SDIO1_CDATA1 MUX
himm 0x200f001c 0x4

# SDIO1_CDATA0 MUX
himm 0x200f0020 0x4

# SDIO1_CDATA3 MUX
himm 0x200f0024 0x4

# SDIO1_CCMD MUX
himm 0x200f0028 0x4

# SDIO1_CARD_POWER_EN MUX
himm 0x200f002C 0x4

# SDIO1_CDATA2 MUX
himm 0x200f0034 0x4

sleep 1

# SDIO1 CLK CLOSE
himm 0x10030010 0x0
# SDIO1 RUN CMD
himm 0x1003002c 0xA0202045
# SDIO1 CLK DIV 0 (49.5MHz) // 0xff - 510div(100KHz)
himm 0x10030008 0x0
# SDIO1 RUN CMD
himm 0x1003002c 0xA0202045
# SDIO1 CLK ENABLE
himm 0x10030010 0x1
# SDIO1 RUN CMD
himm 0x1003002c 0xA0202045
