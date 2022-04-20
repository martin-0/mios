#include <stdint.h>

#include "asm.h"
#include "cons.h"
#include "libsa.h"

unsigned char* vga_text = (unsigned char*)VGA_SCREEN;
uint16_t* ivga_text = (uint16_t*)VGA_SCREEN;

// XXX:	well, this is an assumption .. we don't know what screen size we're set to .. 
//	for the time being it's ok

// current cursor position
unsigned char cursx, cursy;
unsigned char COLS = 80, ROWS = 25;

// XXX: it doesn't handle \t or \r
// XXX: i could call the cputc in the loop ; idea was to speed it up, no sure there's much of a benefit here though
void puts(char* s) {
	uint16_t pos, vgac;
	char c;

	vgac = (DEFAULT_CHAR_ATTRIB << 8); 
	while ((c = *s++)) { 
		if (c == '\n') { 
			cursx = 0;
			if (cursy++ == ROWS) scroll();
			goto cursor_adjust;
		}

		// set attribute
		*(char*)(&vgac) = c;

		// print char
		pos = cursy * COLS + cursx;
		*(ivga_text + pos) = vgac;
	
		cursx++;
		if (cursx > COLS) { 
			cursx = 0;
			if (cursy++ == ROWS) scroll();
		}	
cursor_adjust:
		setcursor();
	}

}

void cputc(char c, char attrib) {
	/* handle special cases of character */
	switch (c) { 
			// XXX: does it make sense to cleanup the screen up to COLS ? probably yes .. 
	case '\n':	
			cursy++;
			cursx =0;
			clearto(cursy, cursx);

			goto exit;

			// XXX: well, tabs are more sophisticated than this, but for the time being ok
	case '\t':	if (cursx + TABSPACE > COLS ) {
				cursy++;
				cursx = cursx + TABSPACE - COLS;
			}
			else {
				cursx += TABSPACE;
			}
			goto exit;

	case '\r':	cursx = 0;
			goto exit;
	}
	
	*(ivga_text + ( cursy * COLS + cursx)) = (attrib << 8 ) | c; 
		
	cursx++;
	if (cursx > COLS) { 
		cursx = 0;
		cursy++;
	}
exit:
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

void clearto(unsigned char newx, unsigned char newy) {
	return;
	uint16_t* lvga_text = (uint16_t*)VGA_SCREEN;
	uint16_t curpos = (cursy*ROWS+cursx) << 1;
	uint16_t newpos = (newy*ROWS+newx-1) << 1;
	uint16_t pos, i;

	if (newpos <= curpos)
		return;
	
	for (pos = 0, i =0; pos < (newpos-curpos); i+=2, pos++)
		*(lvga_text+curpos+i) = 0x0720;
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
	outw(VGA_INDEX_REGISTER, 0xf);
	outb(VGA_DATA_REGISTER, pos & 0xff);
	
	// cursor high
	outw(VGA_INDEX_REGISTER, 0xe);
	outb(VGA_DATA_REGISTER, (pos >> 8 ) & 0xff);

	/* this was needed for realmode
	uint16_t* bios_cursor = (uint16_t*)0x450;
	*bios_cursor = cursy << 8 | cursx;
	*/
}
