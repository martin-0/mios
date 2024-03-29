/* martin */

/*
	Location of main IDT table that is being loaded by kernel in entry.S. Both traps and interrupts
	use the same struct trapframe to describe its frame.

	When IRQ/trap occurs jump to a proper location in IDT table happens. Table entries are set to
	appropriate offset within:
		__irq_setframe_early	--> irq_handlers[irq]
		__trap_setframe_early	--> trap_handlers[trap]

	They set the stack to the same struct trapframe. Then they call the main routine defined in
	irq_handlers[] for irq and trap_handlers[] for traps.

	init_idt() initialises entries by an helper function setup_idt_entry(). This function is meant to
	be used only once as it sets the proper location for early frame setup. To change the irq/trap handler
	only change in irq_handlers[] or trap_handlers[] should be done.

*/

#include "asm.h"
#include "pic.h"

#if defined(DEBUG) || defined(DEBUG_IRQ)
	#include "libk.h"
#endif

interrupt_desc_t idt_entries[IDT_ENTRIES];			// IDT entries

/* entry.S is loading this table */
idt_t IDT = {	.size = sizeof(idt_entries)-1,
		.idt_desc = idt_entries
	};

volatile uint64_t ticks;					// IRQ0 ticks

interrupt_handler_t irq_handlers[IRQ_ENTRIES];			// IRQ handlers
uint64_t irq_stats[IRQ_ENTRIES];				// IRQ stats

trap_handler_t trap_handlers[TRAP_ENTRIES_LOW];			// actual trap handlers

typedef enum e_trapnr {
	T_DIV0 = 0,
	T_DEBUG = 1,
	T_NMI = 2,
	T_BREAK = 3,
	T_OVRFLW = 4,
	T_INVOP = 6,
	T_DF = 8,
	T_TSS = 10,
	T_SNP = 11,
	T_SSF = 12,
	T_GPF = 13,
	T_PF = 14
} e_trapnr_t;

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
extern void __trap_setframe_early();
extern void __irq_setframe_early();
extern void irq_handler_dflt();
extern void trap_bad_dummy();

#ifdef DEBUG_IRQ
	extern void irq_dispatch();
#endif

#ifdef DEBUG_TRAP
	extern void trap_dispatch();
#endif

extern void dummy_int11_handler(struct trapframe* f);
extern void dummy_int80_handler(struct trapframe* f);

// NOTE: static inlines can't be included in headers
static inline void write_8259(uint8_t ctrl, uint8_t cmd) {
	outb_p(cmd, ctrl);
}

static inline int8_t read_8259(uint8_t ctrl) {
	return inb_p(ctrl);
}

void init_8259(void) {
	// All ISA IRQs should be edge triggered
	//	https://forum.osdev.org/viewtopic.php?t=23774

	// ICW1: send INIT to PICs
	outb(ICW1_INIT_PIC|ICW1_USE_ICW4|ICW1_EDGE_TRIGGERED_MODE, MASTER_PIC_COMMAND);
	outb(ICW1_INIT_PIC|ICW1_USE_ICW4|ICW1_EDGE_TRIGGERED_MODE, SLAVE_PIC_COMMAND);
	delay_p80();

	// ICW2: actual remapping of IRQs
	outb(0x20, MASTER_PIC_DATA);				// IRQ 0-7  0x20-0x27
	outb(0x28, SLAVE_PIC_DATA);				// IRQ 8-15 0x28-0x2f
	delay_p80();

	// ICW3: set relationship between master and slave PIC 
	outb(4, MASTER_PIC_DATA);				// 2nd bit - IRQ2 goes to slave
	outb(2, SLAVE_PIC_DATA);				// bit notation: 010: master IRQ to slave
	delay_p80();

	// ICW4: x86 mode
	outb(ICW4_MODE_x86, MASTER_PIC_DATA);
	outb(ICW4_MODE_x86, SLAVE_PIC_DATA);
	delay_p80();

	// on slave disable all IRQs
	write_8259(SLAVE_PIC_DATA, ~4);

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
		m = irq - 8;
		ctrl = SLAVE_PIC_DATA;
	}
	else {
		ctrl = MASTER_PIC_DATA;
	}
	cur_m = read_8259(ctrl);

	#ifdef DEBUG_IRQ
		if (irq) printk("mask_irq%d: curmask: %x\n", irq, cur_m);
	#endif

	cur_m |= (1 << m);

	#ifdef DEBUG_IRQ
		// too many msgs with irq0
		if (irq) printk("mask_irq%d: applying: %x\n", irq, cur_m);
	#endif

	write_8259(ctrl, cur_m);

	#ifdef DEBUG_IRQ
		if (irq) debug_status_8259("mask_irq");
	#endif
}

void clear_irq(uint8_t irq) {
	uint8_t ctrl,cur_m, m;
	m = irq;

	if (irq > 7) {
		m = irq - 8;
		ctrl = SLAVE_PIC_DATA;
	}
	else {
		ctrl = MASTER_PIC_DATA;
	}
	cur_m = read_8259(ctrl);

	#ifdef DEBUG_IRQ 
		if (irq) printk("clear_irq%d: curmask: %x\n", irq, cur_m);
	#endif

	cur_m &= ~(1 << m );

	#ifdef DEBUG_IRQ
		if (irq) printk("clear_irq%d: applying: %x\n", irq, cur_m);
	#endif

	write_8259(ctrl, cur_m);

	#ifdef DEBUG_IRQ
		if (irq) debug_status_8259("clear_irq");
	#endif
}

void send_8259_EOI(uint8_t irq) {
	if (irq > 7)
		outb_p(OCW2_EOI, SLAVE_PIC_COMMAND);

	outb_p(OCW2_EOI, MASTER_PIC_COMMAND);
}

void init_pit(void) {
	outb(0x36, PIT_MODE_CMD_REG);		/* ch0, lo/hi access, square wave gen, count in 16bit binary */
	
	/* XXX: using static FQ 100Hz (0x2e9b) for channel 0 */
	outb_p(0x9b, PIT_CHANNEL_0);
	outb_p(0x2e, PIT_CHANNEL_0);

	// IRQ0 handler can be installed now
	irq_handlers[0] = irq0_handler;
	clear_irq(0);

	#ifdef DEBUG_IRQ
		debug_status_8259("init_pit");
	#endif
}

/* NOTE:
	setup_idt_entry() sets the entries in the IDT. It's the early part of the interrupt/trap where
	stack frame is set and then irq_handlers[] or trap_handlers[] are called by the early handler code.
*/
void setup_idt_entry(interrupt_handler_t handler, uint16_t sel, uint8_t irq, uint8_t type) {
	interrupt_desc_t s = {
			.base_lo = (uint32_t)*handler & 0xffff,
			.selector = sel,
			.reserved = 0,
			.type = type,
			.base_hi = ( (uint32_t)(*handler) >> 16 ) & 0xffff
		};
	idt_entries[irq] = s;
}

inline void set_interrupt_handler(interrupt_handler_t handler, uint8_t irq) {
	irq_handlers[irq] = handler;
}

void init_idt() {
	uint32_t i,j,ofst;

	#ifdef DEBUG_IRQ
		printk("init_idt: __irq_setframe_early: %p, dispatch: %p, ticks: %p\n", __irq_setframe_early, irq_dispatch, &ticks);
	#endif

	#ifdef DEBUG_TRAP
		printk("init_idt: __trap_setframe_early: %p, dispatch: %p\n", __trap_setframe_early, trap_dispatch);
	#endif

	// handler for traps 0 - TRAP_ENTRIES_LOW
	ofst = 0;
	for (i =0 ; i < TRAP_ENTRIES_LOW; i++) {
		setup_idt_entry(__trap_setframe_early+ofst, KERN_CS, i, IDT_GATE32_TRAP);
		trap_handlers[i] = dflt_trap_handler;
		ofst += 12;	// each __trap_setframe_early trap is 12B apart in idt.S
		// XXX: I should use some better method than this
	}

	// set all IRQ handlers to irq_handler_dflt
	// i: index to idt, j: index to irq handlers
	for (j=0, ofst=0; j < IRQ_ENTRIES; i++,j++) {
		setup_idt_entry(__irq_setframe_early+ofst, KERN_CS, i, IDT_GATE32_IRQ);
		irq_handlers[j] = irq_handler_dflt;
		ofst+=4;	// 1x pushl + jmp
	}

	// WARNING :
	//		idt.S doesn't currently handle more than TRAP_ENTRIES_LOW entries
	//		does it make sense to make smaller IDT or mark the segment as not present?
	// accessing traps above
	for (; i < IDT_ENTRIES; i++) {
		setup_idt_entry(NULL, KERN_CS, i, IDT_GATE32_TRAP & ~(IDT_TYPE_SEGMENT_PRESENT));
	}

	#ifdef DEBUG_IRQ
		debug_status_8259("init_idt");
	#endif	
}

// XXX: this is just dummy handler ; frame is not used here
void irq0_handler(__attribute__ ((unused)) struct trapframe* f) {
	ticks++;
	send_8259_EOI(0);
}

void debug_status_8259(char* caller) {
	uint8_t r1,r2, r3;
	write_8259(MASTER_PIC_COMMAND, OCW3_RQ_IRR);	// IR
	r1 = read_8259(MASTER_PIC_COMMAND);
	r2 = read_8259(MASTER_PIC_DATA);

	write_8259(MASTER_PIC_COMMAND, OCW3_RQ_ISR);	// IS
	r3 = read_8259(MASTER_PIC_COMMAND);

	printk("%s: master: IRR: %x (pending ACKs), IMR: %x (mask), ISR: %x (EOI waiting)\n", caller, r1,r2,r3);

	write_8259(SLAVE_PIC_COMMAND, OCW3_RQ_IRR);	// IR
	r1 = read_8259(SLAVE_PIC_COMMAND);
	r2 = read_8259(SLAVE_PIC_DATA);

	write_8259(SLAVE_PIC_COMMAND, OCW3_RQ_ISR);	// IS
	r3 = read_8259(SLAVE_PIC_COMMAND);

	printk("%s: slave: IRR: %x (pending ACKs), IMR: %x (mask), ISR: %x (EOI waiting)\n", caller, r1,r2,r3);
}

void check_irq_stats(void) {
	uint32_t i;
	for (i =0 ; i < 16; i++) {
		printk("irq%d: %llx\n", i, irq_stats[i]);
	}
}

void debug_irq_frame(struct trapframe* f) {
	printk("----- IRQ ------\ninterrupt: %d\nEIP: %p\tESP: %p\tEBP: %p\n"
		"EAX: %p\tEBX: %p\tECX: %p\nEDX: %p\tEDI: %p\tESI: %p\n"
		"CS: 0x%hx\tEFLAGS: %p\n",
			f->irq, f->eip, f->esp, f->ebp, f->eax, f->ebx, f->ecx, f->edx, f->edi, f->esi, f->cs, f->eflags);
}

void debug_trap_frame(struct trapframe* f) {

	printk("------ TRAP ------\ntrap %d: %s\ntrap error: 0x%x\n", f->trapnr, traps[f->trapnr].desc, f->err);

	// decode trap specific error
	switch(f->trapnr) {
	case	T_TSS:
	case	T_SSF:
	case	T_GPF:
	case	T_SNP:
			decode_selector_err(f->err);
			break;
	}

	printk("EIP: %p\tESP: %p\tEBP: %p\n"
		"EAX: %p\tEBX: %p\tECX: %p\nEDX: %p\tEDI: %p\tESI: %p\n"
		"CS: 0x%hx\tEFLAGS: %p\n<<----------------\n", f->eip, f->esp, f->ebp, f->eax, f->ebx, f->ecx, f->edx, f->edi, f->esi, f->cs, f->eflags);
}

void decode_selector_err(int err) {
	char* descref[4] = { "GDT", "IDT", "LDT", "IDT" };
	char* origin[2] = { "CPU", "external to CPU" };

	printk( "%s, %s, 0x%x\n", origin[err & 1], descref[(err >> 1) & 3], err >> 3);
}

/* NOTE: default trap handler to notify us; should be replaced with actual one */
void dflt_trap_handler(struct trapframe* f) {
	printk("%s: trap %d, error 0x%x\n", __func__, f->trapnr, f->err);
	debug_trap_frame(f);
}
