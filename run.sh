#qemu-system-x86_64 -curses -hda stand.raw
#qemu-system-x86_64 -curses -monitor stdio mios

MONITOR_TELNET="-monitor telnet:127.0.0.1:10101,server,nowait"
MONITOR_STDIO="-monitor stdio"

DEBUG=""
if [ "z"$1 = "zd" ]; then 
	DEBUG="-S"
fi

# qemu-system-i386 ${DEBUG} ${MONITOR} -curses -hda mios
qemu-system-i386 -s ${DEBUG} ${MONITOR_STDIO} -curses -hda mios

