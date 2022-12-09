#include <stdint.h>

#include "asm.h"
#include "cons.h"
#include "libsa.h"

uint16_t* ivga_text = (uint16_t*)VGA_SCREEN;		// XXX: probably not needed as global variable .. 

// XXX:	well, this is an assumption .. we don't know what screen size we're set to .. 
//	for the time being it's ok

// current cursor position
unsigned char cursx, cursy;
unsigned char COLS = 80, ROWS = 25;

void puts(char* s) {
	char c;
	while ((c = *s++)) {
		cputc(c, DEFAULT_CHAR_ATTRIB);
	}
}

void cputc(char c, char attrib) {
	uint16_t t;
	/* handle special cases of character */
	switch (c) { 
	case '\n':	
			clearto(COLS);
			cursy++;
			cursx =0;
			goto exit;

	case '\t':	
			t = TABSPACE - (cursx % TABSPACE);

			if (cursx + t > COLS ) { 
				clearto(COLS);
				cursy++;
				cursx = 0;
			}
			else {
				clearto(cursx+t);
				cursx += t;
			}
			goto exit;

	case '\r':	cursx = 0;
			goto exit;
	}
	
	*(ivga_text + ( cursy * COLS + cursx)) = (attrib << 8 ) | c; 
	cursx++;

exit:
	if (cursx >= COLS) { 
		cursx = 0;
		cursy++;
	}
	if (cursy == ROWS) scroll();
	setcursor();
}

// scroll down n rows
void scroll() {
	uint32_t* lvga_text = (uint32_t*)VGA_SCREEN;
	uint32_t i;

	// (80 * 2 ) / 4 = 40 - offset from lvga_screen
	// (80 *2 * 24 ) / 4 = 920 moves

	for (i = 0; i < 960 ; i++) {
		//*(lvga_text+40+i) = *(lvga_text+i);
		*(lvga_text+i) = *(lvga_text+40+i);
	}
	for( ; i < 960+40; i++) {
		*(lvga_text+i) = 0x07200720;	// blank out the last line
	}
	cursy = ROWS-1;
}

void clearto(unsigned char newx) { 
	uint16_t pos,i;
	uint8_t c = newx-cursx;
	
	pos = cursy*COLS+cursx;
	for (i = 0; i < c; i++) {
		*(ivga_text+pos+i) = 0x0720;
	}
}

void clrscr() { 
	uint32_t* lvga_text = (uint32_t*)VGA_SCREEN;
	uint16_t pos;
	for (pos = 0; pos < 1000; pos++) { 
		*(lvga_text + pos) = 0x07200720;		// space with default attrib
	}

	cursx = cursy = 0;
	
	/*
	uint32_t *ptr = (uint32_t*)0x450;
	*ptr = 0; ptr++; *ptr = 0;
	*/
	setcursor();	
}

// XXX: should we assert cursy/cursx ?
void setcursor() { 
	uint16_t pos = cursy * COLS + cursx;

	// cursor low
	outw(0xf, VGA_INDEX_REGISTER);
	outb(pos & 0xff, VGA_DATA_REGISTER);
	
	// cursor high
	outw(0xe, VGA_INDEX_REGISTER);
	outb((pos >> 8 ) & 0xff, VGA_DATA_REGISTER);
}
