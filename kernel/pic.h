#ifndef HAVE_PIC_H
#define HAVE_PIC_H 

#include "asm.h"

/* PIC 8259 */
#define	MASTER_PIC_COMMAND		0x20
#define MASTER_PIC_DATA			0x21
#define	SLAVE_PIC_COMMAND		0xa0
#define	SLAVE_PIC_DATA			0xa1

/*
		A0	D7	D6	D5	D4	D3	D2	D1	D0
	----------------------------------------------------------------------------
	OCW1	1	M7	M6	M5	M4	M3	M2	M1	M0
	OCW2	0	R	SL	EOI	0	0	L2	L1	L0
	OCW3	0	0	ESMM	SMM	0	1	P	RR	RIS
*/

// OCW1 - read from DATA port

// options to set in ICW1 word; bits 5-7 should be always 0 on x86
#define ICW1_USE_ICW4                   1
#define ICW1_SINGLE_PIC                 2
#define ICW1_EDGE_TRIGGERED_MODE        0
#define ICW1_LEVEL_TRIGGERED_MODE       8
#define ICW1_INIT_PIC                   16

#define	OCW2_EOI			0x20

// OCW3 uses COMMAND port (A0 is 0)
#define	OCW3_RQ_IRR			0x0a
#define	OCW3_RQ_ISR			0x0b

#define ICW4_MODE_x86           1
#define ICW4_MODE_AUTO_EOI      2
#define ICW4_MODE_BUF_MASTER    4
#define ICW4_MODE_BUFFERED      8
#define ICW4_MODE_NESTED        16

/* PIT 825x */
#define	PIT_MODE_CMD_REG		0x43		/* write only */
#define	PIT_CHANNEL_0			0x40
#define	PIT_CHANNEL_1			0x41
#define	PIT_CHANNEL_2			0x42

#define	IDT_ENTRIES			256

#define	KERN_CS				0x8		// comes from GDT

#define	IDT_TYPE_SEGMENT_PRESENT	0x80
#define	IDT_GATE32_TRAP			0x8f		// IDT descriptor values
#define	IDT_GATE32_IRQ			0x8e

/* IDT descriptor */
typedef struct interrupt_desc {
	uint16_t base_lo;
	uint16_t selector;
	uint8_t reserved;
	uint8_t type;
	uint16_t base_hi;
} __attribute__((packed)) interrupt_desc_t;


// NOTE: should be 8B aligned 
typedef struct idt {
	uint16_t size;
	interrupt_desc_t* idt_desc;
} __attribute__((packed)) idt_t;


#define	IRQ_ENTRIES			16
typedef void (*interrupt_handler_t)();

#define	TRAP_ENTRIES_LOW		0x20			// first reserved exceptions/traps starting from 0 (0x0-0x1f)
typedef void (*trap_handler_t)(struct trapframe* tf);

/* PIC functions */
void init_8259(void);
void send_8259_EOI(uint8_t irq);
void mask_irq(uint8_t irq);
void clear_irq(uint8_t irq);

/* PIT functions */
void init_pit(void);

void install_handler(interrupt_handler_t handler, uint16_t sel, uint8_t irq, uint8_t type);
void set_interrupt_handler(interrupt_handler_t handler, uint8_t irq);

// debug
void debug_status_8259(char* caller);
void check_irq_stats(void);

void irq0_handler(struct trapframe* f);
void irq1_handler(struct trapframe* f);

void debug_install_irq1(void);
void debug_irq_frame(struct trapframe* f);
void debug_trap_frame(struct trapframe* f);
void unused_trap_handler(struct trapframe* f);

void handle_nmi(struct trapframe* f, uint16_t reason);

#endif /* ifndef HAVE_PIC_H */
