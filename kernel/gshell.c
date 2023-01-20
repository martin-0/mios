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

	c = 0; // silence gcc warning while kbd is not properly working
	// XXX: we should use mutex here!!
	while(1) {
		if (atkbd.flags & 1) {
			// XXX	we are on a single CPU computer and lack mutex protection right now
			//	lame but doable approach here is to disable interrupts
			asm volatile("cli");

			atkbd.flags &= ~1;
			asm volatile("sti");

			// XXX	basicaly don't produce any character from keyboard yet
			continue;
		}

		if (com0_state.flags & 1) {
			c = com0_state.byte;
			com0_state.flags &= ~1;
			goto out;
		}
		asm volatile("pause");
	}
out:
	/*
	if (c > 0x1f && c < 0x80)
		putc(c);
	*/
	return c;	
}

/* reads up to n-1 characters, 0-terminates the string */
int read_string(char* buf, int n) {
	char c;
	int i;

	if (n < 1) return 0;

	n--;
	i = 0;
	while(i < n) {
		c = getc();

		// XXX: why is c over serial line sending \r only ?
		if ( c == 0x0d || c == 0x0a ) {
			goto out;
		}

		// backspace
		if (c == 0x7f || c == 0x08 ) {
			if (--i < 0) i=0;
			putc(c);
			continue;
		}

		putc(c);
		*(buf+i) = c;
		i++;
	}

out:
	*(buf+i) = '\0';
	return i;
}

