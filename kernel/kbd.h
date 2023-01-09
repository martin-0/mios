#ifndef HAVE_KBD_H
#define	HAVE_KBD_H

#include "asm.h"

/* let's try something simple first..*/
typedef struct kbd_state {
	unsigned char shift_flags;
	unsigned char led_state;
	volatile int flags;
	volatile char key;              // very simple one byte buffer of a scancode
} kbd_state_t;

int __init_kbd_module();
void kbd_isr_handler(struct trapframe* f);

int8_t kbde_write_command(uint8_t cmd);
int8_t kbde_read_data();

#endif /* ifndef HAVE_KBD_H */
