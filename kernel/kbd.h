#ifndef HAVE_KBD_H
#define	HAVE_KBD_H

#include "asm.h"

int __init_kbd_module();
void kbd_isr_handler(struct trapframe* f);

int8_t kbde_write_command(uint8_t cmd);
int8_t kbde_read_data();

// debug
uint8_t getc();


#endif /* ifndef HAVE_KBD_H */
