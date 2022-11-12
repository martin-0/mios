# MIOS
My **attempt** to write something. Calling it an OS would be .. overstatement. I've decided to create README file to keep main notes on what I was doing last time and what should I do. Coming back to this project after few months is painful.

## Status
### loading kernel
pmbr searches for MIOS boot partition: 736F696D-0001-0002-0003-FEEDCAFEF00D. When found rest of the partition is loaded (upper size limit). gboot then searches for linux ext2 partition as its root partition.<br />
Kernel is being searched in "/boot/kernel". Symlinks are supported. <br /><br />

Right now ELF32 loader statically loads the kernel as it was PoC to see if I can get it working. WIP to load it properly by going through the PT_LOAD entries.<br /><br />

### TODO
I'm using memcpy_seg to copy program headers to kernel's LINKADDR - 0x20000. Not sure if this is the best idea but I'll stick with it for now. It may not be a bad idea to use multiboot structure to pass arguments to kernel. Right now I'm passing only one argument - smap structure - so I can set the physical memory manager. kernel_entry stub initializes registers, sets the smap pointer and jumps to kernel main. 

##e To run the VM
```sh
make disk
make
./run.sh
```
