# MIOS
My **attempt** to write something. Calling it an OS would be .. overstatement. I've decided to create README file to keep main notes on what I was doing last time and what should I do. Coming back to this project after few months is painful.

## Status
### loading kernel
pmbr searches for MIOS boot partition: 736F696D-0001-0002-0003-FEEDCAFEF00D. When found rest of the partition is loaded (upper size limit). gboot then searches for linux ext2 partition as its root partition.<br />
Kernel is being searched in "/boot/kernel". Symlinks are supported. <br /><br />
elf32 loader loads the PT_LOAD segments of the kernel.

## TODO
boot/ext2.S	ext2_inode_seek() : doubly/triply indirect search not implemented yet<br />
kernel/*	need to adjust idt.S to work with regparm=3

## NOTES
Do a cleanup of the gboot code. Lots of 16/32b assembly mixed together.

### To run the VM
```sh
make disk
make
./run.sh
```
I've not included build tools though. make will fail if crosscompiling tools are not present on the system.
