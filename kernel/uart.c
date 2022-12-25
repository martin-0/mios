#include "uart.h"
#include "asm.h"
#include "libsa.h"

uart_type_t uart_types[] = {
	{ unknown, "unknown" },
	{ i8250, "8250" },
	{ i8250A, "8250A" },
	{ i8250B, "8250B" },
	{ i16450, "16450" },
	{ i16550, "16550" },
	{ i16550A, "16550A" },
	{ i16750, "16750" }
};

// XXX: dummy write test
void dbg_uart_write(char c, int16_t base) {
	outb(c, base + 0);
}

// XXX	let's assume there is serial port at COM1_BASE right now
int init_uart(uint16_t base) {
	uart_id_t type;
	uint8_t	r;

	printk("init_uart: attempting to enable com1\n");

	type = uart_ident(base);
	printk("uart: com1: %s\n", uart_types[type].desc);

	if (type == unknown)
		return 1;

	r = inb(base + UART_REG_LCR) | MASK_LCR_DLAB;
	outb(r, base + UART_REG_LCR);

	// speed: 115200/1 = 115200
	outb(1, base + UART_REG_DLL);
	outb(0, base + UART_REG_DLH);

	r &= MASK_DISABLE_LCR_DLAB;
	outb(r, base + UART_REG_LCR);

	return 0;
}

uart_id_t uart_ident(uint16_t base) {
	uint8_t r;

	// test for FIFO support
	outb(0xE7, base + UART_REG_FCR);
	r = inb(base + UART_REG_IIR);

	if (r & 0x40) {
		if (r & 0x80) {
			if (r & 0x20)
				return i16750;
			else
				return i16550A;
		}
		else {
			return i16550;
		}
	}
	// no FIFO support
	else {
		// scratch reg check
		outb(0x42, base + UART_REG_SR);
		r = inb(base + UART_REG_SR);

		if (r == 0x42) return i16450;

		// XXX: I should probably distinguish among 8250, 8250A/B versions too
		return i8250;
	}

	return unknown;
}
