#ifndef HAVE_MM_H
#define	HAVE_MM_H

#define	MM_MAX_ENTRIES			128		// XXX: limit set by us for now

#include <stdint.h>

enum map_types {
	MEM_AVAIL=1,
	MEM_RESERVED,
	MEM_ACPI_RECLAIM,
	MEM_ACPI_NVS
};

typedef struct mementry {
	uint64_t	e_base;
	uint64_t	e_len;
	uint32_t	e_type;
	uint32_t	e_xattr;				// extended attributes 
} __attribute__((packed)) mementry_t; 


typedef struct memmap {
	uint32_t	mm_count;
	uint32_t 	mm_size;
	mementry_t	map[MM_MAX_ENTRIES];
} __attribute__((packed)) memmap_t;

#define	PAGE_SIZE		4096

void testmem();

#endif /* ifndef HAVE_MM_H */
