#ifndef HAVE_MM_H
#define	HAVE_MM_H

#include <stdint.h>

#define	E820_MAX_ENTRIES	128				// NOTE: limit set by us; smap's data in idt.S is of this size
								// XXX: maybe include it in some sort of asm.h
#define	E820_TYPE_AVAIL		1
#define	E820_TYPE_RESERVED	2
#define	E820_TYPE_ACPI_RCLM	3
#define	E820_TYPE_ACPI_NVS	4

// memory entry as returned by int 0x15 ax=E820h
typedef struct e820_entry {
	uint64_t	e_base;
	uint64_t	e_len;
	uint32_t	e_type;
	uint32_t	e_xattr;
} __attribute__((packed)) e820_entry_t;

typedef struct e820_map {
	uint32_t	count;
	uint32_t 	entry_size;
	e820_entry_t	map[E820_MAX_ENTRIES];
} __attribute__((packed)) e820_map_t;

/* XXX: how am i going to distinguish between used memory and reserved memory in map_t ?
	i could create a queue of reserved pages and keep a reference to it.

	anything below 0x10000 should be reserved too. for my 32MB test machine that's quite a lot though.
	i could set the special physical mem queues for < 1MB requests

	i should care about the memory holes too..
*/

// index 0 - 31 refers to physical map 0 - 4294967296

typedef uint32_t block_t;

#define	MM_HIMEM_START		1048576					// memory above 1MB
#define	PAGE_SIZE		4096

#define	BLOCK_SIZE		( (PAGE_SIZE)*sizeof(block_t)*8 )
#define	MM_MAX_BLOCKS		32768					// 4GB RAM = 4194304*1024 / PAGE_SIZE / sizeof(block_t)

typedef struct physical_map {
	block_t		block_map[MM_MAX_BLOCKS];
	uint32_t	blocks;						// how many blocks do we use
	uint32_t	pages;						// how many usable pages do we have (could be more than blocks*32)
} physical_map_t;

void init_pm();
void show_e820map();



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


#endif /* ifndef HAVE_MM_H */
