#ifndef HAVE_LIBK_H
#define HAVE_LIBK_H

#include <stdint.h>
#include <stddef.h>

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


#define LAST_CHAR(s)            ( *((s)+1) == '\0' )

uint32_t printk(char* fmt, ...);
void helper_printk_x(uint32_t nr, char lz, char ofst);
void helper_printk_x16(uint16_t nr, char lz, char ofst);
void helper_printk_u(uint32_t nr, char lz);

void dump_memory(uint32_t* addr, uint32_t size);

/* string functions */
char* memset(void* dst, int c, size_t n);
void* memcpy(void* dst, const void* src, size_t n);
size_t strlen(const char* str);
char* strcpy(char* dst, const char* src);
int strcmp(const char* s1, const char* s2);
int strncmp(const char* s1, const char* s2, size_t n);

#endif /* ifndef HAVE_LIBK_H */
