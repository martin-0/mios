#ifndef HAVE_KBD_H
#define	HAVE_KBD_H

#include "asm.h"

void __init_kbd_module();

void kbd_handler(struct trapframe* f);


#endif /* ifndef HAVE_KBD_H */
