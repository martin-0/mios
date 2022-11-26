/* martin */

#include "asm.h"
#include "pic.h"

#if defined(DEBUG) || defined(DEBUG_IRQ)
	#include "libsa.h"
#endif

interrupt_desc_t idt_entries[IDT_ENTRIES];			// IDT entries
char c;
idt_t IDT = {	.size = sizeof(idt_entries)-1,
		.idt_desc = idt_entries
	};

volatile uint64_t ticks;					// IRQ0 ticks

// XXX: shold rename interrupt_handler_t to idt_handler_t or something

interrupt_handler_t irq_handlers[IRQ_ENTRIES];			// IRQ handlers
uint64_t irq_stats[IRQ_ENTRIES];				// IRQ stats

// in idt.S
extern interrupt_handler_t trap_idt_entry[TRAP_ENTRIES_LOW];	// address in IDT entry
trap_handler_t trap_handlers[TRAP_ENTRIES_LOW];			// actual trap handler

extern void show_e820map();

trap_desc_t traps[TRAP_ENTRIES_LOW] = {
		{ "Divide by zero",			0, 0 },
		{ "Debug",				1, 0 },
		{ "Non-maskable interrupt",		2, 0 },
		{ "Breakpoint", 			3, 0 },
		{ "Overflow",				4, 0 },
		{ "Bound Range Exceedeed", 		5, 0 },
		{ "Invalid opcode", 			6, 0 },
		{ "Device not available",		7, 0 },
		{ "Double fault",			8, 1 },
		{ "Coprocessor Segment overrun",	9, 0 },		// legacy
		{ "Invalid TSS",			10, 0 },
		{ "Segment Not Present",		11, 1 },
		{ "Stack segment fault",		12, 1 },
		{ "General protection fault",		13, 1 },
		{ "Page fault",				14, 1 },
		{ "RESERVED",				15, 0 },
		{ "x87 Floating-Point Exception",	16, 0,},
		{ "Alignment Check",			17, 1 },
		{ "Machine Check",			18, 0 },
		{ "SIMD Floating-Point Exception",	19, 0 },
		{ "Virtualization Exception",		20, 0 },
		{ "Control Protection Exception",	21, 0 },
		{ "RESERVED",				22, 0 },
		{ "RESERVED",				23, 0 },
		{ "RESERVED",				24, 0 },
		{ "RESERVED",				25, 0 },
		{ "RESERVED",				26, 0 },
		{ "RESERVED",				27, 0 },
		{ "Hypervisor Injection Exception",	28, 0 },
		{ "VMM Communication Exception", 	29, 1 },
		{ "Security Exception",			30, 1 },
		{ "RESERVED",				31, 0 }
	};

// defined in idt.S
extern void trap_handler_dflt();
extern void irq_main_handler();
extern void irq_handler_dflt();
extern void trap_bad_dummy();

#ifdef DEBUG_IRQ
	extern void irq_dispatch();
#endif

#ifdef DEBUG_TRAP
	extern void trap_dispatch();
#endif

extern void int80_handler();
extern void int11_handler();

extern uint32_t* debug_trap;

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

	#ifdef DEBUG_TRAP
		printf("init_idt: trap_handler_dflt: %p, dispatch: %p\n", trap_handler_dflt, trap_dispatch);
	#endif

	//printf("init_idt: debug_trap: %p\n", &debug_trap);

	// set the default lower traps
	// XXX: traps are unhandled, we most likely end up in the infinite loop as saved ip is not modified
	for (i =0 ; i < TRAP_ENTRIES_LOW; i++) {
		setup_idt_entry(trap_idt_entry[i], KERN_CS, i, IDT_GATE32_TRAP);
		//trap_handlers[i] = trap_bad_dummy;
		trap_handlers[i] = debug_dump_trapframe;
	}


	ofst = 0;
	for (i = 0x20; i < 0x30; i++) {
		setup_idt_entry(irq_main_handler+ofst, KERN_CS, i, IDT_GATE32_IRQ);
		ofst+=4;
	}

	// setup the rest of the IDT, segment marked as not present
	// XXX: does it make more sense to rather use smaller IDT instead ?
	for (; i < IDT_ENTRIES; i++) {
		setup_idt_entry(trap_handler_dflt, KERN_CS, i, IDT_GATE32_TRAP & ~(IDT_TYPE_SEGMENT_PRESENT));
	}

	// default IRQ handler for non-assigned IRQ handlers
	// XXX: IRQ0 and IRQ1 are set here in pic.c
	for (i =0 ; i < IRQ_ENTRIES ; i++) { 
		irq_handlers[i] = irq_handler_dflt;
	}

	// XXX: experimenting with traps

	// NP trap
	// NOTE: this means trap_handlers[11] is not called
	setup_idt_entry(int11_handler, KERN_CS, 11, IDT_GATE32_TRAP);

	printf("init_idt: int11_handler: %p\n", int11_handler);

	// trap that has unset P in type at IDT
	setup_idt_entry(int80_handler, KERN_CS, 0x80, IDT_GATE32_TRAP & ~(IDT_TYPE_SEGMENT_PRESENT));

	#ifdef DEBUG_IRQ
		debug_status_8259("init_idt");
	#endif	
}

// XXX: this is just dummy handler ; frame is not used here
void irq0_handler(__attribute__ ((unused)) struct irqframe* f) {
	ticks++;
	//asm("cli;hlt");

	send_8259_EOI(0);
}

// XXX: wait a minute .. who's passing argument to irq1_handler ? probably trap_dispatch()
void irq1_handler(struct irqframe* f) { 
	uint8_t scancode = inb(0x60);
	printf("frame: %p, scan code: %x\n", f, scancode);

	// XXX: debugging ; this really should not be part of the irq1 handler
	switch(scancode) {
	// S
	case 0x1f:	check_irq_stats();
			break;

	// I
	case 0x17:	debug_status_8259("irq1_handler");
			break;

	// P
	case 0x19:	asm("int $0x80");
			break;

	// D
	case 0x20:
			debug_dump_irqframe(f);
			break;
	// N
	case 0x31:	__asm__ ("int $2");
			break;

	// M
	case 0x32:	show_e820map();
			break;

	}

	send_8259_EOI(1);
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

// XXX: this is actually being installed by entry.S !
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

void debug_dump_trapframe(struct trapframe* f) {
	printf("%s\ntrap error: %x\nEIP: %p\tESP: %p\tEBP: %p\n"
		"EAX: %p\tEBX: %p\tECX: %p\nEDX: %p\tEDI: %p\tESI: %p\n"
		"CS: 0x%hx\tEFLAGS: %p\n", traps[f->trapno].desc,
			f->err, f->eip, f->esp, f->ebp, f->eax, f->ebx, f->ecx, f->edx, f->edi, f->esi, f->cs, f->eflags);
}

// XXX: set some temporary routines to debug stuff
void debug_set_handlers() {
}
