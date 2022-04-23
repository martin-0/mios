/* martin */

#include "asm.h"
#include "pic.h"

#if defined(DEBUG) || defined(DEBUG_IRQ)
	#include "libsa.h"
#endif

interrupt_desc_t idt_entries[IDT_ENTRIES];			// IDT entries

idt_t IDT = {	.size = sizeof(idt_entries)-1,
		.idt_desc = idt_entries
	};

volatile uint64_t ticks;					// IRQ0 ticks

interrupt_handler_t irq_handlers[IRQ_ENTRIES];			// IRQ handlers
uint64_t irq_stats[IRQ_ENTRIES];				// IRQ stats

// defined in idt.S
extern void trap_handler_dflt();
extern void irq_main_handler();
extern void irq_handler_dflt();
extern void irq_dispatch();
extern void nmi_trap();

// NOTE: static inlines can't be included in headers
static inline void write_8259(uint8_t ctrl, uint8_t cmd) {
	outb(ctrl, cmd);
	delay_out();
}

static inline int8_t read_8259(uint8_t ctrl) {
	return inb(ctrl);
}

void init_8259(void) {
	// ICW1: send INIT to PICs
	outb(MASTER_PIC_COMMAND, 0x11);
	outb(SLAVE_PIC_COMMAND, 0x11);
	delay_out();

	// ICW2: actual remapping of IRQs
	outb(MASTER_PIC_DATA, 0x20);				// IRQ 0-7  0x20-0x27 
	outb(SLAVE_PIC_COMMAND, 0x28);				// IRQ 8-15 0x28-0x2f
	delay_out();

	// ICW3: set relationship between master and slave PIC 
	outb(MASTER_PIC_DATA, 4);				// 2nd bit - IRQ2 goes to slave 
	outb(SLAVE_PIC_COMMAND, 2);				// bit notation: 010: master IRQ to slave
	delay_out();
	
	// ICW4: x86 mode
	outb(MASTER_PIC_DATA, 1);
	outb(SLAVE_PIC_COMMAND, 1);
	delay_out();

	// on slave disable all IRQs
	write_8259(SLAVE_PIC_DATA, ~0);

	// on master enable IRQ2 only 
	write_8259(MASTER_PIC_DATA, ~4);

	#ifdef DEBUG_IRQ
		debug_status_8259("init_8259");
	#endif
}

void mask_irq(uint8_t irq) {
	uint8_t ctrl,cur_m, m;
	m = irq;

	if (irq > 7) {
		m = (irq >> 4);
		ctrl = SLAVE_PIC_DATA;
	}
	else {
		ctrl = MASTER_PIC_DATA;
	}
	cur_m = read_8259(ctrl);
	delay_out();

	#ifdef DEBUG_IRQ
		if (irq) printf("mask_irq%d: curmask: %x\n", irq, cur_m);
	#endif

	cur_m |= (1 << m);

	#ifdef DEBUG_IRQ
		// too many msgs with irq0
		if (irq) printf("mask_irq%d: applying: %x\n", irq, cur_m);
	#endif

	write_8259(ctrl, cur_m);
	delay_out();

	#ifdef DEBUG_IRQ
		if (irq) debug_status_8259("mask_irq");
	#endif
}

void clear_irq(uint8_t irq) {
	uint8_t ctrl,cur_m, m;
	m = irq;

	if (irq > 7) {
		m = (irq >> 4);
		ctrl = SLAVE_PIC_DATA;
	}
	else {
		ctrl = MASTER_PIC_DATA;
	}
	cur_m = read_8259(ctrl);
	delay_out();

	#ifdef DEBUG_IRQ 
		if (irq) printf("clear_irq%d: curmask: %x\n", irq, cur_m);
	#endif

	cur_m &= ~(1 << m );

	#ifdef DEBUG_IRQ
		if (irq) printf("clear_irq%d: applying: %x\n", irq, cur_m);
	#endif

	write_8259(ctrl, cur_m);
	delay_out();

	#ifdef DEBUG_IRQ
		if (irq) debug_status_8259("clear_irq");
	#endif
}

void send_8259_EOI(uint8_t irq) {
	if (irq > 7)
		outb(SLAVE_PIC_COMMAND, OCW2_EOI);

	outb(MASTER_PIC_COMMAND, OCW2_EOI);
	delay_out();
}

void init_pit(void) {
	outb(PIT_MODE_CMD_REG, 0x36);		/* ch0, lo/hi access, square wave gen, count in 16bit binary */
	
	/* XXX: using static FQ 100hz (0x2a9b) for channel 0 */
	outb(PIT_CHANNEL_0, 0x9b);
	delay_out();
	outb(PIT_CHANNEL_0, 0x2e);
	delay_out();

	// IRQ0 handler can be installed now
	irq_handlers[0] = irq0_handler;
	clear_irq(0);

	#ifdef DEBUG_IRQ
		debug_status_8259("init_pit");
	#endif
}

void setup_idt_entry(interrupt_handler_t handler, uint16_t sel, uint8_t irq, uint8_t type) {
	interrupt_desc_t s = {
			.base_lo = (uint32_t)handler & 0xffff,
			.selector = sel,
			.reserved = 0,
			.type = type,
			.base_hi = ( (uint32_t)(handler) >> 16 ) & 0xffff
		};
	idt_entries[irq] = s;
}

void init_idt() {
	uint32_t i,ofst;
	#ifdef DEBUG_IRQ
		printf("init_idt: irq_main_handler: %p, dispatch: %p, ticks: %p\n", irq_main_handler, irq_dispatch, &ticks);
	#endif
	
	// set default trap handler
	for (i =0 ; i < 0x20 ; i++) { 
		setup_idt_entry(trap_handler_dflt, KERN_CS, i, IDT_GATE32_TRAP);
	}

	// NOTE: idt.S defines irq_main_handler
	ofst = 0;
	for (; i < 0x30; i++) {
		setup_idt_entry(irq_main_handler+ofst, KERN_CS, i, IDT_GATE32_IRQ);
		ofst+=4;
	}

	// XXX: makes sense to set it to something .. 
	for (; i < IDT_ENTRIES; i++) {
		setup_idt_entry(trap_handler_dflt, KERN_CS, i, IDT_GATE32_TRAP);
	}

	// default IRQ handlers for the rest
	for (i =0 ; i < IRQ_ENTRIES ; i++) { 
		irq_handlers[i] = irq_handler_dflt;
	}

	// XXX: testing

	printf("init_idt: nmi_trap: %p\n", nmi_trap);
	setup_idt_entry(nmi_trap, KERN_CS, 2, IDT_GATE32_TRAP);


	#ifdef DEBUG_IRQ
		debug_status_8259("init_idt");
	#endif	
}

void irq0_handler(struct irqframe* f) {
	ticks++;
	send_8259_EOI(0);
}

void irq1_handler(struct irqframe* f) { 
	uint8_t scancode = inb(0x60);
	printf("scan code: %x\n", scancode);

	// little debugging
	switch(scancode) {
	case 0x1f:	check_irq_stats();
			break;

	case 0x17:	debug_status_8259("irq1_handler");
			break;

	case 0x20:
			debug_dump_irqframe(f);
			break;

	case 0x32:	__asm__ ("int $2");
			break;

	}

	send_8259_EOI(1);
}

void handle_nmi(struct irqframe* f, uint16_t reason) {
	printf("NMI reason: %x\n", reason);
	debug_dump_irqframe(f);
}

void debug_status_8259(char* caller) {
	uint8_t r1,r2, r3;
	write_8259(MASTER_PIC_COMMAND, OCW3_RQ_IRR);	// IR
	r1 = read_8259(MASTER_PIC_COMMAND);
	r2 = read_8259(MASTER_PIC_DATA);

	write_8259(MASTER_PIC_COMMAND, OCW3_RQ_ISR);	// IS
	r3 = read_8259(MASTER_PIC_COMMAND);

	printf("%s: master: IRR: %x (pending ACKs), IMR: %x (mask), ISR: %x (EOI waiting)\n", caller, r1,r2,r3);

	write_8259(SLAVE_PIC_COMMAND, OCW3_RQ_IRR);	// IR
	r1 = read_8259(SLAVE_PIC_COMMAND);
	r2 = read_8259(SLAVE_PIC_DATA);

	write_8259(SLAVE_PIC_COMMAND, OCW3_RQ_ISR);	// IS
	r3 = read_8259(SLAVE_PIC_COMMAND);

	printf("%s: slave: IRR: %x (pending ACKs), IMR: %x (mask), ISR: %x (EOI waiting)\n", caller, r1,r2,r3);
}

void debug_install_irq1(void) {
	irq_handlers[1] = irq1_handler;
        clear_irq(1);
}

void check_irq_stats(void) {
	uint32_t i;
	for (i =0 ; i < 16; i++) {
		printf("irq%d: %llx\n", i, irq_stats[i]);
	}
}

void debug_dump_irqframe(struct irqframe* f) {
	printf("interrupt: %d\nEIP: %p\tESP: %p\tEBP: %p\n"
		"EAX: %p\tEBX: %p\tECX: %p\nEDX: %p\tEDI: %p\tESI: %p\n"
		"CS: 0x%hx\tEFLAGS: %p\n",
			f->irq, f->eip, f->esp, f->ebp, f->eax, f->ebx, f->ecx, f->edx, f->edi, f->esi, f->cs, f->eflags);
}

