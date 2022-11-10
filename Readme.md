# MIOS
My **attempt** to write something. Calling it an OS would be .. overstatement. I've decided to create README file to keep main notes on what I was doing last time and what should I do. Coming back to this project after few months is painful.

## Current TODO
**ext2 boot module** - I'm able to find the file in path including the symlink. Few tests were done, all ok.
** elf parser/loader** - time to write the ELF parser/loader that will load the kernel to desired location. Then I can finally work on the kernel part again.

### To run the VM
```sh
make disk
make
./run.sh
```
