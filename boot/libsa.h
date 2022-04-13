/* martin */

#ifndef HAVE_LIBSA_H
#define HAVE_LIBSA_H

#ifndef NULL
	#define	NULL	(void*)0
#endif

#include <stdint.h>

#define	ROL(n) do { 											\
	asm volatile("movl %1, %%eax; roll $4, %%eax; movl %%eax, %0" : "=m"(n) : "r"(n) : "eax" );	\
} while(0)

#define	ROR(n) do { 											\
	asm volatile("movl %1, %%eax; rorl $4, %%eax; movl %%eax, %0" : "=m"(n) : "r"(n) : "eax" );	\
} while(0)

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
#define	DIVISOR_INT_32			1000000000

/* long long type */
typedef struct long_t {
	uint32_t low;
	uint32_t high;
} __attribute__((packed)) long_t;

void dump_memory(uint32_t* addr, uint32_t size);
int parse_memmap();

uint32_t printf(char* fmt, ...);
void helper_printf_x(uint32_t nr, char lz, char ofst);
void helper_printf_u(uint32_t nr, char lz);

#endif /* ifndef HAVE_LIBSA_H */
