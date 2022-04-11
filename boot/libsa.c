#include <stdint.h>

// XXX: va_list and NULL should be defined in some header that makes sense not here in libsa

// XXX: subdivide printf to smaller functions to handle printing ? make it will come useful later 
//	if I decide to use *printf or similar .. but then, most likely not needed in libsa

#ifndef NULL
	#define	NULL	(void*)0
#endif

#include "cons.h"
#include "asm.h"

#define	MAX_HEXDIGITS_INT_32		8

void do_dump(void);
void dump_memory(uint32_t* addr, uint32_t size);

uint32_t printf(char* fmt, ...) { 

	// XXX: pointer arithmetic is not allowed on void* ptrs. defaulting to char* then
	char** va_args = (&fmt)+1;
	char* pchar = fmt;
	
	int32_t i,nr;
	char c,islz;

	while (*pchar != '\0') {
		switch(*pchar) {
		// FMT specifier
		case '%': 	if (*(++pchar) == '\0') goto exit;
			
				// go through known formats	
				switch(*pchar) {
				case 'p':
				case 'X':
				case 'x':	
						nr = *(int32_t*)va_args;

						// always print leading zeros with %p
						if (*pchar == 'p') {
							islz = 0;
							puts("0x");
						}
						else {
							islz = 1;		/* leading 0s, don't print */
						}
					
						for (i = 0; i < MAX_HEXDIGITS_INT_32; i++) {
							nr = rorl(nr);
							c = nr & 0xf;

							if (islz) {
								if(c == 0) continue;
								else
									islz = 0;
							}
							if (c < 10) c += 0x30;
							else {
								// handle lower/upper case
								c+= (*pchar & 0x20) ? 0x57 : 0x37;
							}
							putc(c);
						}
						va_args++;
						break;

				case 'u':
						nr = *(uint32_t*)va_args;
						uint32_t divisor;

				handle_unsigned_decimal:
						divisor = 1000000000;

						islz = 1;
						while (divisor > 0) { 
							i = nr / divisor;
							nr -= (i*divisor);
							divisor /= 10;
							if (islz) { 
								if (i == 0) continue;
								else
									islz = 0;
							}
							putc(i+0x30);
						}

						va_args++;
						break;
				case 'd':
						nr = *(uint32_t*)va_args;
						if (nr & 0x80000000) {
							putc('-');
							nr = ~nr +1;
						}
				
						// XXX: very dirty .. creating subfunctions for printf would be better way to go;	
						goto handle_unsigned_decimal;	
						
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
				
				break;

		// escaping characte
		case '\\':	if (*(++pchar) == '\0') goto exit;
				putc(*pchar);
				break;

		default:
				putc(*pchar);

		}
		pchar++;
	}

exit:

	return 0;
}

void do_dump() {
	dump_memory((uint32_t*)0x00080000, 0x200);
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

void do_printf(void) { 
	printf("this is a string: %s, %s, %s\nhex numbers: 0x%x\t0x%X\t%p\ndecimal numbers: %d %u\nchar: %c %c\npercent: %%\n", 
			"asd", "huh?", "meh", 0xcafe, 0xc0de, 0xdebeef, -42, -42, 'a', 'n');
}
