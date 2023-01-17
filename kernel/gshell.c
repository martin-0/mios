#include <stddef.h>

#include "gshell.h"
#include "kbd.h"
#include "uart.h"
#include "libk.h"
#include "cons.h"

extern struct kbd atkbd;
extern uart_state_t com0_state;

#define         MAX_SC1_LINES           255             // sizeof(char)

// XXX: this is so wrong!!
// scancode should be index to the table for ascii code
//sc1_line_t sc1_lookup_table[MAX_SC1_LINES] = {
//};

int getc() {
	int c;
	// XXX: we should use mutex here!!
	while(1) {
		if (atkbd.flags & 1) {
			// XXX	we are on a single CPU computer and lack mutex protection right now
			//	lame but doable approach here is to disable interrupts
			asm volatile("cli");

			atkbd.flags &= ~1;
			asm volatile("sti");
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
	// print ascii
	if (c > 0x1f && c < 0x80)
		putc(c);
	return c;	
}

// XXX: one by one reading into str
// read string up to n chars
int read_string(char* buf, size_t n) {
	char c;
	size_t i = 0;

	while(i < n) {
		c = getc();

		// XXX: why is c over serial line sending \r only ?
		if ( c == 0x0d || c == 0x0a ) {
			*(buf+i) = '\0';
			goto out;
		}

		// backspace
		if (c == 0x7f || c == 0x08 ) {
			if (i > 0) i--;
			*(buf+i) = '\0';
			continue;
		}

		*(buf+i) = c;
		i++;
	}

	if (!i) return 0;

	*(buf+i-1) = '\0';
out:
	return i;
}

