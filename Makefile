CC=/local/cross/bin/i686-elf-gcc
AS=/local/cross/bin/i686-elf-as
LD=/local/cross/bin/i686-elf-ld

DISK_RAW=disk00.raw
ROOTFS=/tmp/rootfs
BLOCKSIZE=1024

OBJDIR=obj

.PHONY: tools
all= tools mios

mios:	pmbr tools
	make -C kernel
	make -C boot
	make copy

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
	/sbin/sgdisk -a 1 -n 1:2048:3071 -t 1:736f696d-0001-0002-0003-feedcafef00d -n 2:4096:266239 -t 2:8300 ./disk00.raw
	sudo losetup -P /dev/loop0 ./disk00.raw
	sudo mkfs.ext2 -b $(BLOCKSIZE) /dev/loop0p2
	sudo losetup -D

copy:
	@echo "syncing filesystem"
	sudo losetup -P /dev/loop0 ./disk00.raw
	sudo mkdir -p $(ROOTFS)
	sudo mount /dev/loop0p2 $(ROOTFS)
	sudo mkdir -p $(ROOTFS)/boot
	sudo cp obj/kernel  $(ROOTFS)/boot/
	sudo cp obj/*.o $(ROOTFS)
	#sudo cp tests/debugme $(ROOTFS)
	sudo umount $(ROOTFS)
	sudo losetup -D

disk-mount:
dm:
	sudo losetup -P /dev/loop0 ./disk00.raw
	sudo mkdir -p $(ROOTFS)
	sudo mount /dev/loop0p2 $(ROOTFS)

disk-umount:
du:
	sudo umount $(ROOTFS)
	sudo losetup -D

disk-efi:
	rm -f $(DISK_RAW)
	dd if=/dev/zero of=$(DISK_RAW) bs=1024k count=256
	/sbin/sgdisk -a 1 -n 1:2048:3071 -t 1:736f696d-0001-0002-0003-feedcafef00d -n 2:4096:266239 -t 2:8300 -n 3:266240:331775 -t 3:ef00 ./disk00.raw
	
clean:
	make -C tools clean
	make -C boot clean
	make -C kernel clean
	make -C tests clean
