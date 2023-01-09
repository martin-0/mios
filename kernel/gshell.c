#include <stddef.h>

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

// XXX: one by one reading into str
// read string up to n chars
int read_string(char* buf, size_t n) {
	char c;
	size_t i = 0;

	while(i < n) {
		c = getc();

		if (c == 0xa) {
			*(buf+i) = 0;
			goto out;
		}
		*(buf+i) = c;
		i++;
	}

	// unlikely event of n being 0
	if (!n) return 0;

	*(buf+i-1) = 0;
out:
	return i;
}
