#ifndef HAVE_CONS_H
#define HAVE_CONS_H

#include <stdint.h>

#define	VGA_SCREEN	0xB8000

#define	VGA_INDEX_REGISTER	0x3d4
#define	VGA_DATA_REGISTER	0x3d5

// VGA char atrributes
#define	BLUE_ON_BLACK		9
#define	WHITE_ON_BLACK		15
#define	GREEN_ON_BLACK		0x2
#define	UNKNOWN			0x9f
#define	DEFAULT_CHAR_ATTRIB	WHITE_ON_BLACK

void clrscr();
void clearto(unsigned char newx);
void scroll();

void setcursor();
void puts(char* s);
void cputc(char c, char attrib);
uint8_t getc();

#define putc(c)	cputc(c, DEFAULT_CHAR_ATTRIB)

#define	TABSPACE	4

#endif /* ifndef HAVE_CONS_H */
