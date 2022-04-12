#ifndef HAVE_LIBSA_H
#define HAVE_LIBSA_H

#ifndef NULL
	#define	NULL	(void*)0
#endif

#include <stdint.h>

struct memory_map_t {
	uint64_t	base;
	uint64_t	len;
	uint32_t	type;
	uint32_t	xattr;
} __attribute__((packed));

struct memory_map {
	uint32_t		entries;
	uint32_t		entry_size;
	struct memory_map_t	data[128];
} __attribute__((packed));

#define	MAX_HEXDIGITS_INT_32		8

void dump_memory(uint32_t* addr, uint32_t size);
int parse_memmap();

uint32_t printf(char* fmt, ...);


#endif /* ifndef HAVE_LIBSA_H */
