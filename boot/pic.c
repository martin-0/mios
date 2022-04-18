/* martin */

#include "asm.h"
#include "pic.h"


extern interrupt_desc_t idt[];

extern void int20_dummy(void);
extern void int21_dummy(void);

void init_8259(void) {
	/* ICW1: send INIT to PICs */
	outb(PRIMARY_PIC_CMD_STAT_REG, 0x11);
	outb(SLAVE_PIC_CMD_STAT_REG, 0x11);
	delay_out();

	/* ICW2: actual remapping of IRQs */
	outb(PRIMARY_PIC_IMR_DATA, 0x20);	/* IRQ 0-7  0x20-0x27 */
	outb(SLAVE_PIC_IMR_DATA, 0x28);		/* IRQ 8-15 0x28 - 2f */
	delay_out();

	/* ICW3: set relationship between primary and secondary PIC */
	outb(PRIMARY_PIC_IMR_DATA, 4);		/* 2nd bit - IRQ2 goes to slave */
	outb(SLAVE_PIC_IMR_DATA, 2);		/* bit notation: 010: master IRQ to slave */
	delay_out();
	
	/* ICW4: x86 mode */	
	outb(PRIMARY_PIC_IMR_DATA, 1);
	outb(SLAVE_PIC_IMR_DATA, 1);
	delay_out();
}

void send_EOI(uint8_t irq) {
	if (irq > 7)
		outb(SLAVE_PIC_CMD_STAT_REG, CMD_EOI);

	outb(PRIMARY_PIC_CMD_STAT_REG, CMD_EOI);
}

void init_pit(void) {
	outb(PIT_MODE_CMD_REG, 0x36);		/* ch0, lo/hi access, square wave gen, count in 16bit binary */
	
	/* XXX: using static FQ - 100hz, 0x2a9b- for channel 0 */
	outb(PIT_CHANNEL_0, 0x9b);
	outb(PIT_CHANNEL_0, 0x2e);
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

void install_dummyies() {
	install_handler(&int20_dummy, 0x8, 0x20, 0x8e);
	install_handler(&int21_dummy, 0x8, 0x21, 0x8e);
}
