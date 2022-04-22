/* martin */

#include "asm.h"
#include "pic.h"

#ifdef DEBUG
	#include "libsa.h"
#endif

interrupt_desc_t idt_entries[IDT_ENTRIES];			// IDT entries

idt_t IDT = {	.size = sizeof(idt_entries)-1,
		.idt_desc = idt_entries
	};

uint64_t ticks;							// IRQ0 ticks

interrupt_handler_t irq_handlers[IRQ_ENTRIES];			// IRQ handlers
uint64_t irq_stats[IRQ_ENTRIES];				// IRQ stats

extern void trap_handler_dflt();
extern void irq_main_handler();
extern void irq_handler_dflt();

extern void irq_dispatch();

void init_8259(void) {
	// ICW1: send INIT to PICs
	outb(MASTER_PIC_COMMAND, 0x11);
	outb(SLAVE_PIC_COMMAND, 0x11);
	delay_out();

	// ICW2: actual remapping of IRQs
	outb(MASTER_PIC_DATA, 0x20);				// IRQ 0-7  0x20-0x27 
	outb(SLAVE_PIC_COMMAND, 0x28);				// IRQ 8-15 0x28-0x2f
	delay_out();

	// ICW3: set relationship between primary and secondary PIC 
	outb(MASTER_PIC_DATA, 4);				// 2nd bit - IRQ2 goes to slave 
	outb(SLAVE_PIC_COMMAND, 2);				// bit notation: 010: master IRQ to slave
	delay_out();
	
	// ICW4: x86 mode
	outb(MASTER_PIC_DATA, 1);
	outb(SLAVE_PIC_COMMAND, 1);
	delay_out();

	// on master enable IRQ2 only 
	//send_8259_cmd(MASTER_PIC_DATA, ~4);

	// on slave disable all IRQs
	//send_8259_cmd(SLAVE_PIC_DATA, ~0);

	debug_status_8259();
}

void send_8259_cmd(uint8_t ctrl, uint8_t cmd) {
	outb(ctrl, cmd);
	delay_out();
}

int8_t read_8259(uint8_t ctrl) {
	return inb(ctrl);
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

	// NOTE: PIT is enabled but still masked by init_8259()
}

void install_handler(interrupt_handler_t handler, uint16_t sel, uint8_t irq, uint8_t type) {
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

	printf("init_idt: irq_main_handler: %p, dispatch: %p\n", irq_main_handler, irq_dispatch);
	
	// set default trap handler
	for (i =0 ; i < 0x20 ; i++) { 
		install_handler(trap_handler_dflt, KERN_CS, i, IDT_GATE32_TRAP);
	}

	// NOTE: idt.S defines irq_main_handler
	ofst = 0;
	for (; i < 0x30; i++) {
		install_handler(irq_main_handler+ofst, KERN_CS, i, IDT_GATE32_IRQ);
		ofst+=4;
	}

	// XXX: makes sense to set it to something .. 
	for (; i < IDT_ENTRIES; i++) {
		install_handler(trap_handler_dflt, KERN_CS, i, IDT_GATE32_TRAP);
	}

	irq_handlers[0] = irq0_handler;
	irq_handlers[1] = irq1_handler;	

	// default IRQ handlers for the rest
	for (i =2 ; i < IRQ_ENTRIES ; i++) { 
		irq_handlers[i] = irq_handler_dflt;
	}

	for (i = 0; i < 2; i++) { 
		printf("init_idt: %d: %p\n", i, irq_handlers[i]);
	}

	// umask bit0 and bit1
	uint8_t imr;

	imr = read_8259(MASTER_PIC_DATA);
	printf("init_idt: current mask: %x\n", imr);
	imr &= ~( 1 | 2 );

	printf("init_idt: applying new mask: %x\n", imr);

	send_8259_cmd(MASTER_PIC_DATA, imr);
}

void irq0_handler(void) {
	ticks++;
}

void irq1_handler(void) { 
	uint8_t scancode = inb(0x60);
	printf("scan code: %x\n", scancode);
}

void debug_status_8259(void) {
	uint8_t r1,r2, r3;
	send_8259_cmd(MASTER_PIC_COMMAND, OCW3_RQ_IRR);	// IR
	r1 = read_8259(MASTER_PIC_COMMAND);
	r2 = read_8259(MASTER_PIC_DATA);

	send_8259_cmd(MASTER_PIC_COMMAND, OCW3_RQ_ISR);	// IS
	r3 = read_8259(MASTER_PIC_COMMAND);

	printf("master: IRR: %x (pending ACKs), IMR: %x (mask), ISR: %x (EOI waiting)\n", r1,r2,r3);

	send_8259_cmd(SLAVE_PIC_COMMAND, OCW3_RQ_IRR);	// IR
	r1 = read_8259(SLAVE_PIC_COMMAND);
	r2 = read_8259(SLAVE_PIC_DATA);

	send_8259_cmd(SLAVE_PIC_COMMAND, OCW3_RQ_ISR);	// IS
	r3 = read_8259(SLAVE_PIC_COMMAND);

	printf("slave: IRR: %x (pending ACKs), IMR: %x (mask), ISR: %x (EOI waiting)\n", r1,r2,r3);
}

void check_irq_stats(void) {
	uint32_t i;
	for (i =0 ; i < 16; i++) {
		printf("irq%d: %llx\n", i, irq_stats[i]);
	}
}

