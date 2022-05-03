#ifndef HAVE_MM_H
#define	HAVE_MM_H

#define	MM_MAX_ENTRIES			128		// XXX: limit set by us; smap's data in idt.S is of this size

#include <stdint.h>

enum map_types {
	MEM_AVAIL=1,
	MEM_RESERVED,
	MEM_ACPI_RECLAIM,
	MEM_ACPI_NVS
};

// memory entry as returned by int 0x15 ax=E820h
typedef struct e820_mem {
	uint64_t	e_base;
	uint64_t	e_len;
	uint32_t	e_type;
	uint32_t	e_xattr;				// extended attributes 
} __attribute__((packed)) e820_mem_t; 


typedef struct e820_map {
	uint32_t	count;
	uint32_t 	size;
	e820_mem_t	map[MM_MAX_ENTRIES];
} __attribute__((packed)) e820_map_t;

// our consolidated memory type
typedef struct mem_entry {
	uint64_t	base;
	uint64_t	size;
	uint32_t	type;
} mem_entry_t;

typedef struct mem_map {
	uint32_t	count;
	mem_entry_t	map[MM_MAX_ENTRIES];
} mem_map_t;

#define PTE_PER_TABLE		1024
typedef uint32_t pte_t;
typedef struct page_table {
	pte_t pte[PTE_PER_TABLE];
} page_table_t;

#define	PTE_GETFRAME(p)			( (p) >> 12 )

#define	PDE_PER_TABLE		1024
typedef uint32_t pde_t;
typedef struct pde_table {
	pde_t pde[PDE_PER_TABLE];
} pde_table_t;


#define	PAGE_SIZE		4096


void testmem();
void parse_memmap();

#endif /* ifndef HAVE_MM_H */
