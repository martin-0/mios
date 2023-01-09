#include "gshell.h"

#include "kbd.h"
#include "uart.h"

extern kbd_state_t kbd;
extern uart_state_t com0_state;

int getc() {
	int c;
	// XXX: we should use mutex here!!
	while(1) {
		if (kbd.flags & 1) {
			c = kbd.key;
			kbd.flags &= ~1;
			goto out;
		}

		if (com0_state.flags & 1) {
			c = com0_state.byte;
			com0_state.flags &= ~1;
			goto out;
		}

		asm volatile("pause");
	}
out:
	return c;	
}
