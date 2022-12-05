#ifndef HAVE_ASM_H
#define HAVE_ASM_H

#include <stdint.h>

typedef struct trap_desc {
	char*	desc;
	int8_t	no;
	int8_t	pushes_err:1;
} __attribute__((packed)) trap_desc_t;

/* used for both trap and irq */
struct trapframe {
	uint32_t	edi;
	uint32_t	esi;
	uint32_t	ebp;
	uint32_t	esp;
	uint32_t	ebx;
	uint32_t	edx;
	uint32_t	ecx;
	uint32_t	eax;
	uint16_t	ds;
	uint16_t	es;
	uint16_t	fs;
	uint16_t	gs;
	union {
		uint32_t	trapnr;
		uint32_t	irqdup;		/* duplicate: same as irq */
	};
	union {
		uint32_t	err;
		uint32_t	irq;
	};
	uint32_t	eip;
	uint32_t	cs;
	uint32_t	eflags;
} __attribute__((packed));

typedef struct regs {
	uint32_t	edi;
	uint32_t	esi;
	uint32_t	ebp;
	uint32_t	esp;
	uint32_t	ebx;
	uint32_t	edx;
	uint32_t	ecx;
	uint32_t	eax;
	uint16_t	ds;
	uint16_t	es;
	uint16_t	fs;
	uint16_t	gs;
	uint32_t	eip;
	uint32_t	cs;
	uint32_t	eflags;
} __attribute__((packed)) regs_t;

/*
 * https://gcc.gnu.org/onlinedocs/gcc/Machine-Constraints.html#Machine-Constraints
 *
 * I keep forgetting these :/ .. so:
 *
 *	N	Unsigned 8-bit integer constant (for in and out instructions).
 *	d	The d register (a,b,c,d,S,D..)
 *	m	A memory operand is allowed ( there are special cases for o,V)
 *	=	Means that this operand is written to by this instruction
 *	+	Means that this operand is both read and written by the instruction.
 */

static inline void outb(uint16_t port, uint8_t val) {
	asm volatile("outb %0, %1" : : "a"(val), "dN"(port));
}

static inline void outw(uint16_t port, uint16_t val) {
	asm volatile("outw %0, %1" : : "a"(val), "dN"(port));
}

static inline void outl(uint16_t port, uint32_t val) {
	asm volatile("outl %0,%1" : : "a"(val), "dN"(port));
}

static inline uint8_t inb(uint16_t port) {
	uint8_t ret;
	asm volatile("inb %1, %0" : "=a"(ret) : "dN"(port));
	return ret;
}

static inline uint16_t inw(uint16_t port) {
	uint16_t ret;
	asm volatile("intw %1, %0" : "=a"(ret) : "dN"(port));
	return ret;
}

static inline uint32_t inl(uint16_t port) {
	uint32_t ret;
	asm volatile("intl %1, %0" : "=a"(ret) : "dN"(port));
	return ret;
}

/* set segment registers */
static inline void set_ds(uint16_t val) {
	asm volatile("movw %0, %%ds"  : : "rm"(val));
}

static inline void set_es(uint16_t val) {
	asm volatile("movw %0, %%es"  : : "rm"(val));
}

static inline void set_fs(uint16_t val) {
	asm volatile("movw %0, %%fs"  : : "rm"(val));
}

static inline void set_gs(uint16_t val) {
	asm volatile("movw %0, %%gs"  : : "rm"(val));
}

/* get segment registers */
static inline uint16_t get_ds(void) {
	uint16_t ds;
	asm volatile(	"movw %%ds, %0" : "=rm"(ds));
	return ds;
}

static inline uint16_t get_es(void) {
	uint16_t es;
	asm volatile(	"movw %%es, %0" : "=rm"(es));
	return es;
}

static inline uint16_t get_fs(void) {
	uint16_t fs;
	asm volatile(	"movw %%fs, %0" : "=rm"(fs));
	return fs;
}

static inline uint16_t get_gs(void) {
	uint16_t gs;
	asm volatile(	"movw %%gs, %0" : "=rm"(gs));
	return gs;
}

static inline uint32_t rorl(uint32_t v) {
	uint32_t t;
	asm volatile("movl %1, %%eax; roll $4, %%eax; movl %%eax, %0" : "=m"(t) : "r"(v));
	return t;
}

static inline uint32_t rorr(uint32_t v) {
	uint32_t t;
	asm volatile("movl %1, %%eax; rorl $4, %%eax; movl %%eax, %0" : "=m"(t) : "r"(v));
	return t;
}

static inline void delay_out(void) {
	asm volatile("outb %al, $0x80");	
}

static inline void disable_interrupts(void) {
	asm volatile ("cli");
}

static inline void enable_interrupts(void) {
	asm volatile ("sti");
}

static inline void halt_cpu(void) {
	asm volatile ("hlt");
}

#endif /* HAVE_ASM_H */
