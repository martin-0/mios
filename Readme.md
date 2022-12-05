# MIOS
My **attempt** to write something. Calling it an OS would be .. overstatement. I've decided to create README file to keep main notes on what I was doing last time and what should I do. Coming back to this project after few months is painful.

## Status
### loading kernel
pmbr searches for MIOS boot partition: 736F696D-0001-0002-0003-FEEDCAFEF00D. When found rest of the partition is loaded (upper size limit). gboot then searches for linux ext2 partition as its root partition.<br />
Kernel is being searched in "/boot/kernel". Symlinks are supported. <br /><br />
elf32 loader loads the PT_LOAD segments of the kernel.
pm_copy() does the copy in protected mode, kernel can be loaded about 1MB without problem.

### kernel
IDT is set. idt.S used  __irq_setframe_early and __trap_setframe_early code for interrupts/traps that set the same trapframe on the stack for handler to process. As not all traps generate error code I used nop instructions to make sure code size in idt.S is the same size. Current logic in the IDT is the following: every entry in IDT has entry to the stub, either __trap_setframe_early or __irq_setframe_early. Code inside it (trap_dispatch/irq_dispatch) then calls the appropriate handler that can be changed. 


### To run the VM
```sh
make disk
make
./run.sh
```
I've not included build tools though. make will fail if crosscompiling tools are not present on the system.
