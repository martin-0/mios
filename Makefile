CC=/local/cross/bin/i686-elf-gcc
AS=/local/cross/bin/i686-elf-as
LD=/local/cross/bin/i686-elf-ld

DISK_RAW=disk00.raw
ROOTFS=/tmp/rootfs

OBJDIR=obj

.PHONY: tools
all= tools mios

mios:	pmbr tools
	make -C kernel
	make -C boot

	# install pmbr
	cd $(OBJDIR) && ./gptfix ../disk00.raw pmbr 

	# install gboot 
	dd if=obj/gboot of=./disk00.raw seek=1048576 bs=1 conv=notrunc

pmbr:
	make -C boot/pmbr

tools:
	make -C tools

disk:
	rm -f $(DISK_RAW)
	dd if=/dev/zero of=$(DISK_RAW) bs=1024k count=256
	/sbin/sgdisk -a 1 -n 1:2048:3071 -t 1:A501 -n 2:4096:266239 -t 2:8300 ./disk00.raw
	sudo losetup -P /dev/loop0 ./disk00.raw
	sudo mkfs.ext2 -b 4096 /dev/loop0p2
	sudo mkdir -p $(ROOTFS)
	sudo mount /dev/loop0p2 $(ROOTFS)
	sudo mkdir $(ROOTFS)/boot
	sudo cp obj/kernel  $(ROOTFS)/boot/
	sudo cp obj/*.o $(ROOTFS)
	sudo umount $(ROOTFS)
	sudo losetup -D

disk-mount:
	sudo losetup -P /dev/loop0 ./disk00.raw
	sudo mkdir -p $(ROOTFS)
	sudo mount /dev/loop0p2 $(ROOTFS)

disk-umount:
	sudo umount $(ROOTFS)
	sudo losetup -D

disk-efi:
	rm -f $(DISK_RAW)
	dd if=/dev/zero of=$(DISK_RAW) bs=1024k count=256
	/sbin/sgdisk -a 1 -n 1:2048:3071 -t 1:A501 -n 2:4096:266239 -t 2:8300 -n 3:266240:331775 -t 3:ef00 ./disk00.raw
	
clean:
	make -C tools clean
	make -C boot clean

