#ifndef HAVE_ASM_H
#define HAVE_ASM_H

#include <stdint.h>

/* in order whihc pusha saves them */

struct regs16 {
	uint16_t	ax,cx,dx,bx,sp,bp,si,di;
	uint16_t	efl;
	uint16_t	es,cs,ss,ds,fs;
} __attribute__((packed));

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

#endif /* HAVE_ASM_H */
