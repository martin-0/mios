/* martin */

#include "asm.h"
#include "pic.h"

#ifdef DEBUG
	#include "libsa.h"
#endif

extern interrupt_desc_t idt[];
extern uint32_t irq_stats[];

extern void int20_dummy(void);
extern void int21_dummy(void);

void init_8259(void) {
	// ICW1: send INIT to PICs
	outb(PRIMARY_PIC_COMMAND, 0x11);
	outb(SLAVE_PIC_COMMAND, 0x11);
	delay_out();

	// ICW2: actual remapping of IRQs
	outb(PRIMARY_PIC_DATA, 0x20);		// IRQ 0-7  0x20-0x27 
	outb(SLAVE_PIC_COMMAND, 0x28);		// IRQ 8-15 0x28-0x2f
	delay_out();

	// ICW3: set relationship between primary and secondary PIC 
	outb(PRIMARY_PIC_DATA, 4);		// 2nd bit - IRQ2 goes to slave 
	outb(SLAVE_PIC_COMMAND, 2);		// bit notation: 010: master IRQ to slave
	delay_out();
	
	// ICW4: x86 mode
	outb(PRIMARY_PIC_DATA, 1);
	outb(SLAVE_PIC_COMMAND, 1);
	delay_out();

	// on master enable IRQ2 only 
	send_8259_cmd(PRIMARY_PIC_DATA, ~4);

	// on slave disable all IRQs
	send_8259_cmd(SLAVE_PIC_COMMAND, ~0);

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
		outb(PRIMARY_PIC_COMMAND, OCW2_EOI);

	outb(SLAVE_PIC_COMMAND, OCW2_EOI);
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
	int32_t* hp = (int32_t*)&handler;
	struct interrupt_desc_t s = {
			.base_lo = *hp & 0xffff,
			.selector = sel,
			.reserved = 0,
			.type = type,
			.base_hi = ( *hp >> 16 ) & 0xffff
		};

	idt[irq] = s;
}

void install_dummies() {
	uint8_t imr;

	install_handler(int20_dummy, 0x8, 0x20, 0x8e);
	install_handler(int21_dummy, 0x8, 0x21, 0x8e);

	#ifdef DEBUG
		printf("install_dummies()\n");
		debug_status_8259();
	#endif

	// umask bit0 and bit1
	imr = read_8259(PRIMARY_PIC_DATA);
	imr &= ~( 1 | 2 );

	printf("install_dummies: imr: %x\n", imr);

	send_8259_cmd(PRIMARY_PIC_DATA, imr);
}

void debug_status_8259(void) {
	uint8_t r1,r2;
	send_8259_cmd(PRIMARY_PIC_COMMAND, OCW3_RQ_IRR);	// IR
	r1 = read_8259(PRIMARY_PIC_COMMAND);
	r2 = read_8259(PRIMARY_PIC_DATA);
	printf("IRR: %x (pending ACKs)\nIMR: %x (mask)\n", r1,r2);

	send_8259_cmd(PRIMARY_PIC_COMMAND, OCW3_RQ_ISR);	// IS
	r1 = read_8259(PRIMARY_PIC_COMMAND);
	printf("ISR: %x (EOI waiting)\n", r1);
}

void check_irq_stats(void) {
	uint32_t i;
	for (i =0 ; i < 16; i++) {
		printf("irq%d: %d\n", i, irq_stats[i]);
	}
}

