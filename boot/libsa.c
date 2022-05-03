/* martin */

#include <stdint.h>

#include "libsa.h"
#include "cons.h"

extern struct memory_map smap;

uint32_t printf(char* fmt, ...) { 

	char** va_args = (&fmt)+1;					// XXX: pointer arithmetic is not allowed on void* ptrs. defaulting to char* then
	char* pchar = fmt;
	
	int32_t nr;
	long_t lnr;
	char c, islz;

	// Right now we treat % as something special. Anything else goes to putc().
	while (*pchar != '\0') {

		switch(*pchar) {
		// FMT specifier
		case '%': 	// there's nothing else to check if % is the last char
				if (*(pchar+1) == '\0') {
					putc('%');
					break;
				}
		
				// advance pchar and check what we have
				switch(*(++pchar)) {
				case 'l':	// check for end of str
						if (*(pchar+1) == '\0') {
							putc('l');
							break;
						}

						// if second argument is not l just continue with the print
						// XXX: so %lx is not a valid format then ..
						if (*(++pchar) != 'l') {
							putc(*pchar);
							break;
						}

						switch(*(++pchar)) {
						case 'x':
						case 'X':
								islz = 0;		// always print leading 0s with 64b
								c = (*pchar & 0x20) ? 0x57 : 0x37;

								lnr = *(long_t*)va_args;
								helper_printf_x(lnr.high,islz,c);
								helper_printf_x(lnr.low,islz,c);

								va_args++; va_args++;		// sizeof ptr* is 4, we pushed 8B on stack
								break;

						/* XXX
							Well, doing decimal integers is harder than I thought. I should figure that out just
							out of curiosity. I failed to do this in two hrs or so I dedicated to this problem.
							Moving on..
						*/
						default:
								putc(*pchar);
						}
						break;

				case 'h':	// half-word size
						if (*(pchar+1) == '\0') {
							putc('h');
							break;
						}
						
						// XXX: word size format for Xx only for now
						switch(*(++pchar)) {
						case 'x':
						case 'X':
								islz = 1;
								c = (*pchar & 0x20) ? 0x57 : 0x37;
								uint16_t nr2 = *(uint16_t*)va_args;

								helper_printf_x16(nr2, islz, c);

								va_args++;
								break;
						default:
								putc(*pchar);
						}

						break;
						
				case 'p':
				case 'X':
				case 'x':	
						nr = *(uint32_t*)va_args;
						islz = 1;				// don't print leading 0s by default

						// always print leading zeros with %p
						if (*pchar == 'p') {
							islz = 0;
							puts("0x");
						}

						c = (*pchar & 0x20) ? 0x57 : 0x37;

						helper_printf_x(nr,islz,c);
						va_args++;
						break;

				case 'u':
						nr = *(uint32_t*)va_args;
						helper_printf_u(nr, 1);
						va_args++;
						break;
				case 'd':
						nr = *(uint32_t*)va_args;
						if (nr & 0x80000000) {
							putc('-');
							nr = ~nr +1;
						}
						helper_printf_u(nr, 1);
						va_args++;
						break;

				case 'c':
						c = *(char*)va_args;
						putc(c);
						va_args++;
						break;
				case 's':	
						puts(*va_args);
						va_args++;
						break;

				case '%':	putc('%');
						break;
						
				}
				
				break; // case %

		default:
				putc(*pchar);

		}
		pchar++;
	}

	return 0;
}

void helper_printf_u(uint32_t nr, char lz) {
	uint32_t i,divisor = DIVISOR_INT_32;

	while (divisor > 0) { 
		i = nr / divisor;
		nr -= (i*divisor);
		divisor /= 10;
		if (lz) { 
			// maybe a bit confusing but we dividied divisor by 10 already as a prep for next loop
			if ( (divisor > 0) && ( i == 0) ) continue;
			else
				lz = 0;
		}
		putc(i+0x30);
	}
}

void helper_printf_x(uint32_t nr, char lz, char ofst) {
	uint16_t i;
	char c;

	for (i = 0; i < MAX_HEXDIGITS_INT_32 ; i++) {
		ROL(nr);
		c = nr & 0xf;

		if (lz) {
			if(i != (MAX_HEXDIGITS_INT_32-1) && c == 0) continue;
			else lz = 0;
		}
		if (c < 10) c += 0x30;
		else {
			c+= ofst;
		}
		putc(c);
	}
}

void helper_printf_x16(uint16_t nr, char lz, char ofst) {
	uint16_t i;
	char c;

	for (i = 0; i < MAX_HEXDIGITS_INT_16 ; i++) {
		ROLH(nr);
		c = nr & 0xf;

		if (lz) {
			if(i != (MAX_HEXDIGITS_INT_16-1) && c == 0) continue;
			else lz = 0;
		}
		if (c < 10) c += 0x30;
		else {
			c+= ofst;
		}
		putc(c);
	}
}

void dump_memory(uint32_t* addr, uint32_t size) {
	uint32_t* cur_addr = addr;
	uint32_t i, chunks;

	// round up chunks
	chunks = ( size + sizeof(uint32_t)-1 ) / sizeof(uint32_t);	

	clrscr();
	printf("addr: %p, size: %x, chunks: %d\n", addr, size, chunks);

	printf("%p", cur_addr);
	for(i =0; i < chunks; i++) {
		printf("\t%p", *cur_addr++);
		if ((i+1)%4 == 0) {
			printf("\n%p", cur_addr);
		}
	}
	putc('\n');
}

