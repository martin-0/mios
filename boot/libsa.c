#include <stdint.h>

#include "libsa.h"
#include "cons.h"
#include "asm.h"

extern struct memory_map smap;

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

// XXX: not handling 64b integers 
int parse_memmap() {
	char* mem_type_desc[5] = {
                "unknown",
                "memory available to OS",
                "reserved",
                "ACPI reclaimable memory",
                "ACPI NVS memory"
        };

	uint64_t i;
//	clrscr();
	printf("memory map address: %p, entries: %d, size: %d\n", &smap, smap.entries, smap.entry_size);

	for (i = 0; i < smap.entries; i++) {
		printf("%p - %p		%s\n", (uint32_t)smap.data[i].base, (uint32_t)smap.data[i].base + (uint32_t)smap.data[i].len, mem_type_desc[smap.data[i].type]);
	}

	return 0;
}
