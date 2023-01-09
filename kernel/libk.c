/* martin */

#include <stdint.h>
#include <stdarg.h>

#include "libsa.h"
#include "cons.h"
#include "uart.h"

uint32_t printk(char* fmt, ...) {
	va_list ap;
	
	long_t lnr;
	int32_t nr;
	char c, islz, *s;

	va_start(ap, fmt);
	while (*fmt != '\0') {
		switch(*fmt) {
		// FMT specifier
		case '%': 	// if '%' is the last char just break
				if ( LAST_CHAR(fmt) ) {
					break;
				}
		
				// advance fmt and check what we have
				switch(*(++fmt)) {
				case 'l':	// check for end of str
						if ( LAST_CHAR(fmt) ) {
							putc('l');
							break;
						}

						// if second argument is not l just continue with the print
						// XXX: so %lx is not a valid format then ..
						if (*(++fmt) != 'l') {
							putc(*fmt);
							break;
						}

						switch(*(++fmt)) {
						case 'x':
						case 'X':
								islz = 0;		// always print leading 0s with 64b
								c = (*fmt & 0x20) ? 0x57 : 0x37;

								lnr = va_arg(ap, long_t);

								helper_printk_x(lnr.high,islz,c);
								helper_printk_x(lnr.low,islz,c);
								break;

						/* XXX
							Well, doing decimal integers is harder than I thought. I should figure that out just
							out of curiosity. I failed to do this in two hrs or so I dedicated to this problem.
							Moving on..
						*/
						default:
								putc(*fmt);
						}
						break;

				case 'h':	// half-word size
						if ( LAST_CHAR(fmt) ) {
							putc('h');
							break;
						}
						
						// XXX: word size format for Xx only for now
						switch(*(++fmt)) {
						case 'x':
						case 'X':
								islz = 1;
								c = (*fmt & 0x20) ? 0x57 : 0x37;
								uint16_t nr2 = (uint16_t)va_arg(ap, uint32_t);

								helper_printk_x16(nr2, islz, c);
								break;
						default:
								putc(*fmt);
						}

						break;
						
				case 'p':
				case 'X':
				case 'x':	
						nr = va_arg(ap, uint32_t);
						islz = 1;				// don't print leading 0s by default

						// always print leading zeros with %p
						if (*fmt == 'p') {
							islz = 0;
							puts("0x");
						}

						c = (*fmt & 0x20) ? 0x57 : 0x37;

						helper_printk_x(nr,islz,c);
						break;

				case 'u':
						nr = va_arg(ap, uint32_t);
						helper_printk_u(nr, 1);
						break;
				case 'd':
						nr = va_arg(ap, uint32_t);
						if (nr & 0x80000000) {
							putc('-');
							nr = ~nr +1;
						}
						helper_printk_u(nr, 1);
						break;

				case 'c':
						c = (char)va_arg(ap, int32_t);
						putc(c);
						break;
				case 's':	
						s = va_arg(ap, char*);
						puts(s);
						break;

				case '%':	putc('%');
						break;
						
				}
				
				break; // case %

		default:
				putc(*fmt);

		}
		fmt++;
	}
	va_end(ap);

	return 0;
}

void helper_printk_u(uint32_t nr, char lz) {
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

void helper_printk_x(uint32_t nr, char lz, char ofst) {
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

void helper_printk_x16(uint16_t nr, char lz, char ofst) {
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

	printk("%p", cur_addr);
	for(i =0; i < chunks; i++) {
		printk("\t%p", *cur_addr++);
		if ((i+1)%4 == 0) {
			printk("\n%p", cur_addr);
		}
	}
	putc('\n');
}

char* memset(char* str, int c, uint32_t size) {
	uint32_t i;
	for(i =0; i < size; i++) {
		*(str+i) = (char)c;
	}
	return str;
}
