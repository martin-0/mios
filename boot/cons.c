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

void puts(char* s) {
	uint16_t pos, vgac;
	char c;

	vgac = (DEFAULT_CHAR_ATTRIB << 8); 
	while ((c = *s++)) { 
		if (c == '\n') { 
			cursy++;
			cursx = 0;
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
			cursy++;
		}	
cursor_adjust:
		setcursor();
	}

}

void cputc(char c, char attrib) {
	/* handle special cases of character */
	switch (c) { 
			// XXX: does it make sense to cleanup the screen up to COLS ? probably yes .. 
	case '\n':	clearto(cursy, cursx);
			cursy++;
			cursx =0;
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
	setcursor();
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
	uint32_t *ptr = (uint32_t*)0x450;	// XXX: updating for BIOS
	*ptr = 0; ptr++; 
	*ptr = 0;
	setcursor();	
}

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
