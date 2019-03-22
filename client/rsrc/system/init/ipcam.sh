export PATH=/system/system/bin:$PATH
#telnetd
export LD_LIBRARY_PATH=/system/system/lib:/mnt/lib:$LD_LIBRARY_PATH
mount -t tmpfs none /tmp -o size=3m

/system/system/bin/brushFlash
/system/system/bin/updata
/system/system/bin/wifidaemon &
/system/system/bin/upgrade &
