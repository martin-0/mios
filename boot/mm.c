/* martin */

/* XXX: Assumption: we are 32B system, no PAE, no address is more than 4G
	Only E820 call was used that doesn't report more memory anyway

	But base+len could wrap around .. is this a problem?
*/

#include "mm.h"
#include "libsa.h"

// libsa16
extern e820_map_t smap;

char* e820_mem_types[5] = {
		"unknown",
		"usable",
		"reserved",
		"ACPI data",
		"ACPI NVS"
	};

physical_map_t pm; 						// contains the whole 4GB memory range

void init_pm() {
	#ifdef DBEUG_PM
		printf("init_pm: smap: %p, entries: %d\n", &smap, smap.count);
	#endif

	uint32_t i,block,bitpos;
	uint32_t base,end;

	e820_entry_t* cur;

	// disable all memory first
	for (i =0 ; i < MM_MAX_BLOCKS; i++) {
		pm.block_map[i] = -1;
	}
	pm.blocks = 0;
	pm.pages = 0;

	for (i = 0; i < smap.count; i++) {
		cur = &smap.map[i];

		// free memory
		if (smap.map[i].e_type != E820_TYPE_AVAIL) continue;

		// if the size of the free memory is not more than a PAGE_SIZE we can't use it
		if ( (cur->e_len / PAGE_SIZE) == 0 ) continue;

		// skip everything under 1MB
		if (cur->e_base + cur->e_len < MM_HIMEM_START) continue;

		// XXX: There's expected reserved range at ~0xC0000000 so we should never never
		//	have situation where base+end wraps around 32b integer. Is "should" ok enough ?
		base = ( cur->e_base + PAGE_SIZE-1 ) & ~(PAGE_SIZE-1);
		end = ( cur->e_base + cur->e_len ) & ~(PAGE_SIZE-1);

		// map starts < 1MB but there is at least one page above 1MB; adjust the base
		if (cur->e_base + cur->e_len - MM_HIMEM_START > PAGE_SIZE ) base = MM_HIMEM_START;
		else continue;

		#ifdef DEBUG_PM
			printf("init_pm: adjusted map:\t0x%x - 0x%x, len: 0x%x, pages: %d\n", base, end, end-base, (end-base)/PAGE_SIZE);
		#endif

		// NOTE: a bit annoying but seems practical to do it here. if we start at bitpos other than 0 we need to set blocks
		//	 to 1, loop increass blocks on pos 0 only
		if ((base % BLOCK_SIZE)/PAGE_SIZE) pm.blocks++;

		// XXX: ISA hole: 15-16MB .. shouldn't it be reported by BIOS as reserved though ?

		while (base < end) {
			block = base / BLOCK_SIZE;				// current bitmap block
			bitpos = (base % BLOCK_SIZE)/PAGE_SIZE;			// current position

			pm.block_map[block] &= ~(1 << bitpos);			// mark page as free

			base += PAGE_SIZE;
			if (bitpos == 0) {
				pm.blocks++;
			}
			pm.pages++;

			if (pm.blocks > MM_MAX_BLOCKS) {
				// XXX: create panic function
				printf("init_pm: fatal error, pm.blocks: %d\n", pm.blocks);
				asm("cli;hlt");
			}
		}
	}
	printf("init_pm: valid blocks: %d, pages: %d, free memory: %d MB\n", pm.blocks, pm.pages, (pm.pages*PAGE_SIZE) >> 20);
}

void show_e820map() {
	uint32_t i;

	uint64_t usable = 0;
	printf("memory map address: %p, entries: %d, size: %d\n", &smap, smap.count, smap.entry_size);

	for (i = 0; i < smap.count; i++) {
		printf("0x%llx - 0x%llx\t%s\n", smap.map[i].e_base, smap.map[i].e_base + smap.map[i].e_len, e820_mem_types[smap.map[i].e_type]);
		if (smap.map[i].e_type == E820_TYPE_AVAIL) usable += smap.map[i].e_len;
	}
	usable >>= 20;
	printf("total usable memory: %d MB\n", (uint32_t)usable);
}
