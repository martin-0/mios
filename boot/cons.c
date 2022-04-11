#include <stdint.h>

#include "asm.h"
#include "cons.h"

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
	#define TABSPACE	8
	/* handle special cases of character */
	switch (c) { 
			// XXX: does it make sense to cleanup the screen up to COLS ? probably yes .. 
	case '\n':	cursy++;
			cursx =0;
			goto exit;

			// XXX: well, tabs are more sophisticated than this, but for the time being ok
	case '\t':	if (cursx + TABSPACE > COLS ) {
				cursy++;
				cursx = cursx + TABSPACE - COLS+1;
			}
			else {
				cursx += TABSPACE;
			}
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

void clrscr() { 
	uint32_t* lvga_text = (uint32_t*)VGA_SCREEN;
	uint16_t pos;
	for (pos = 0; pos < 1000; pos++) { 
		*(lvga_text + pos) = 0; 
	}

	cursx = cursy = 0;
	setcursor();	
}

void setcursor() { 
	uint16_t pos = cursy * COLS + cursx;

	// cursor low
	outw(0xf, VGA_INDEX_REGISTER);
	outb(pos & 0xff, VGA_DATA_REGISTER);
	
	// cursor high
	outw(0xe, VGA_INDEX_REGISTER);
	outb( (pos >> 8 ) & 0xff, VGA_DATA_REGISTER);
}

