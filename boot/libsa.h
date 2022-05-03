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

#define	ROLH(n) do { 											\
	asm volatile("movw %1, %%ax; rolw $4, %%ax; movw %%ax, %0" : "=m"(n) : "r"(n) : "ax" );	\
} while(0)

#define	RORH(n) do { 											\
	asm volatile("movw %1, %%ax; rorw $4, %%ax; movw %%ax, %0" : "=m"(n) : "r"(n) : "ax" );	\
} while(0)

#define	MAX_HEXDIGITS_INT_16		4
#define	MAX_HEXDIGITS_INT_32		8
#define	DIVISOR_INT_32			1000000000

/* long long type ; I can use this with ROL/ROR macros */
typedef struct long_t {
	uint32_t low;
	uint32_t high;
} __attribute__((packed)) long_t;


uint32_t printf(char* fmt, ...);
void helper_printf_x(uint32_t nr, char lz, char ofst);
void helper_printf_x16(uint16_t nr, char lz, char ofst);
void helper_printf_u(uint32_t nr, char lz);

void dump_memory(uint32_t* addr, uint32_t size);

#endif /* ifndef HAVE_LIBSA_H */
