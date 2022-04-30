/* martin */

#include "mm.h"
#include "libsa.h"

// libsa16
extern memmap_t smap;

void testmem() { 
	uint32_t* addr = (uint32_t*)0x100000;
	uint32_t found,i;

	for (i =0 ; i < smap.mm_count; i++) { 
		if (smap.map[i].e_base >= (uint64_t)0x100000) {
			printf("found map, index %d, base: 0x%llx, size: 0x%llx\n", i, smap.map[i].e_base, smap.map[i].e_len);
			found = 1;
			break;
		}
	}

	if (!found) { printf("no memory range above 0x100000\n"); }
	else {
		printf("\n");
		found = i;

		while ((uint32_t)addr < smap.map[found].e_base + smap.map[found].e_len) {		// XXX: i know smap is 64b
	
			for (i =0 ; i < PAGE_SIZE << 2; i++) {
				*(addr+i) = 0x41414141;
			}

			if ( ( (uint32_t)addr % 0x100000) == 0) printf("%p\t\t\r", addr); 				

			addr += PAGE_SIZE;
		}
		printf("%p\t\t\ndone\nReading back\n", addr);

		addr = (uint32_t*)0x100000;
		uint32_t err,nr;
		err =0;
	
		while ((uint32_t)addr < smap.map[found].e_base + smap.map[found].e_len) {
			for (i =0 ; i < PAGE_SIZE >> 2; i++) {
				nr = 0;
				nr = *(addr+i);
				if ( nr != 0x41414141) {
					err++;
					printf("bad location: %p, val: %x, i: %d\n", (addr+i), nr, i);
					break;
				}
			}
			addr += PAGE_SIZE;
			if ( ( (uint32_t)addr % 0x100000) == 0) printf("%p\t\t\r", addr); 				
		}

		printf("errors: %d\n", err);

	}

}
