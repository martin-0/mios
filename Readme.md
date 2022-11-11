# MIOS
My **attempt** to write something. Calling it an OS would be .. overstatement. I've decided to create README file to keep main notes on what I was doing last time and what should I do. Coming back to this project after few months is painful.

## Current TODO
**A20 vs memory addressing in 16bit**
It seems I forgot I can't address more than 0x10000 in 16b realmode. I should check the current code if I made any assumptions on addressing. I was mixing 16/32 code as it was easier to work with 32b registers when working with 4B integers. Now the question is how should I deal with loading the kernel. 

### To run the VM
```sh
make disk
make
./run.sh
```
