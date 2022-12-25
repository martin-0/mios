#ifndef HAVE_KBD_H
#define	HAVE_KBD_H

#include "asm.h"

void __init_kbd_module();
void kbd_handler(struct trapframe* f);

// debug
uint8_t getc();


#endif /* ifndef HAVE_KBD_H */
