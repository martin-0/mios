#!/bin/sh

MONITOR_TELNET="-monitor telnet:127.0.0.1:10101,server,nowait"
MONITOR_STDIO="-monitor stdio"

MONITOR=""
DEBUG=""

# available options: 
#	-m	monitor on stdio|telnet
#	-d 	freeze CPU at start
#
while [ $# -gt 0 ]; do
	case "$1" in
		 "-d")
			DEBUG="-S"
			;;
		"-m")	shift
			case $1 in
				"s")	MONITOR="${MONITOR_STDIO}"
					;;
				"t")	MONITOR="${MONITOR_TELNET}"
					;;
				*)	echo "error: unknonw monitor option $1"
					exit 1
					;;
			esac
			;;
		*)
			echo "unknown option $1"
			exit 1
			;;
	esac
	shift

done

# use default
if [ "z${MONITOR}" = "z" ]; then
	MONITOR="${MONITOR_STDIO}"
fi

qemu-system-i386 -s ${DEBUG} ${MONITOR} -curses -hda disk00.raw

