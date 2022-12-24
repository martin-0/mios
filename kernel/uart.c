#include "asm.h"

#define	COM1_BASE	0x3f8

#define	OFFSET_LCR	3		// Line Control Register

int init_uart() {

	uint8_t	r;

	inb(COM1_BASE+OFFSET_LCR);
	

	return 0;
}
