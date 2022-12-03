#!/bin/sh

MONITOR_TELNET="-monitor telnet:127.0.0.1:10101,server,nowait"
MONITOR_STDIO="-monitor stdio"

MONITOR=""
DEBUG=""
QDISPLAY="-curses"
EXTRAPARAM=""
KVM=""

DISK="disk00.raw"

# available options: 
#	-m	monitor on stdio|telnet
#	-d 	freeze CPU at start
#	-x	disable curses
#	-k	enable kvm
#	-p	extra parameters passed to qemu
#
while [ $# -gt 0 ]; do
	case "$1" in
		 "-d")
			DEBUG="-S"
			;;

		"-k")
			KVM="-enable-kvm"
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
		"-x")	QDISPLAY=""
			;;

		"-p")	shift
			EXTRAPARAM="$1"
			;;

		*)
			echo "unknown option $1"
			exit 1
			;;
	esac
	shift

done

# use defaults
if [ "z${MONITOR}" = "z" ]; then
	MONITOR="${MONITOR_STDIO}"
fi

qemu-system-i386 ${KVM} -m 512 -s ${DEBUG} ${MONITOR} ${QDISPLAY} ${EXTRAPARAM} \
-drive id=disk,file=${DISK},if=none -device ahci,id=ahci -device ide-hd,drive=disk,bus=ahci.0
