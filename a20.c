#include <stdint.h>

#include "asm.h"

/* when reading this port */
#define	KBD_RD_STATUS_REGISTER	0x64

#define FAST_PORT	0x92
#define DELAY_PORT	0x80

//uint8_t check_kbd_status();
//void do_wait();

uint8_t check_kbd_status(void) {
	uint8_t c = inb(KBD_RD_STATUS_REGISTER);
	return c;
}

void do_wait(void) {
	outb(0, DELAY_PORT);
}

/* 8204 ctrl, port A, aka FAST_PORT */
void enable_a20_fast(void) {
	uint8_t c;

	c = inb(FAST_PORT);		/* read the current value from System port A on 8204 ctrl*/
	c |= 2;				/* bit1: enable A20 gate */
	c &= ~1;			/* make sure bit0 is 0: system reset */
	outb(c, FAST_PORT);		/* write back */
}

uint16_t test_a20(void) {
	uint16_t es,fs;
	es = get_es();
	fs = get_fs();

	/* restore es, fs segments */
	set_es(es);
	set_fs(fs);

	return 0;
}

/* attempt to enable A20 gate using several methods */
uint8_t enable_a20(void) {
	uint8_t status = 0;
	enable_a20_fast();

	return status;	
}
