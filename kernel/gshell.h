#ifndef HAVE_GSHELL_H
#define HAVE_GSHELL_H

#include <stdint.h>

typedef struct sc1_line {
	uint8_t	sc1_alone;		// key pressed alone
	uint8_t	sc1_shift;		// with shift
	uint8_t sc1_ctrl;		// wrl
	uint8_t	sc1_alt;		// with alt
} sc1_line_t;

#define         MAX_SC1_LINES           255             // sizeof(scancode)

int getc();
int read_string(char* buf, size_t n);

#endif /* ifndef HAVE_GSHELL_H */
