# MIOS
My **attempt** to write something. Calling it an OS would be .. overstatement. I've decided to create README file to keep main notes on what I was doing last time and what should I do. Coming back to this project after few months is painful.

## Current TODO
**ext2 boot module** - symlink issue resolved. test program is able to traverse the symlink just fine.
interesting "issue" was with the block cache. For 4k block having relatively small cache didn't help much (d'oh). As PoC ok but I'll probably
won't use bufcache at all in ext2 module. Will see..


### To run the VM
```sh
make disk
make
./run.sh
```
