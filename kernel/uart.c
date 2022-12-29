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

#define	UART_COMMON_SPEED_VALS		13

uint32_t uart_common_speeds[UART_COMMON_SPEED_VALS] = { 50, 110, 220, 300, 600, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200 };

int poll_uart_write(char c, int16_t base) {
	int16_t i;
	uint8_t r;

	for (i =0 ; i < POLL_WRITE_RETRIES ; i++) {
		r = inb_p(base + UART_REG_LSR);
		if (r == 0xff) goto out;				// error

		if ( (r & MASK_LSR_EMPTY_THR ) ) {			// empty transmitter holding register
			outb_p(c, base + UART_REG_THR);
			return 0;
		}
		delay_p80();
	}
out:
	return 1;
}

// XXX	let's assume there is serial port at base right now
//	Disable FIFO, set 8N1 and try to negotiate as fast speed as possible
int early_uart_init(uint16_t base, uint32_t speed) {
	uart_id_t type;

	if ((type = uart_ident(base)) == unknown) {
		printk("early_uart_init: 0x%x: unknown uart type\n", base);
		return 1;
	}

	// no interrupts
	outb_p(0, base + UART_REG_IER);

	// 8N1
	outb_p(MASK_LCR_WORDSZ_8|MASK_LCR_ONE_STOPBIT|MASK_LCR_PARITY_NONE, base + UART_REG_LCR);

	// disable FIFO
	outb_p(0, base + UART_REG_FCR);

	if ((uart_set_baud(base, speed)) != 0) {
		return 1;
	}

	printk("early_uart_init: com0: %s,0x%x,%dbps,8N1\n", uart_types[type].desc, base, speed);
	return 0;
}

int uart_set_baud(uint16_t base, uint32_t speed) {
	uint16_t divisor;
	uint8_t lcr,r;

	// default speed to 9600
	speed = (speed == 0) ? 9600 : speed;

	divisor = 115200 / speed;

	lcr = inb_p(base + UART_REG_LCR) | MASK_LCR_DLAB;
	outb_p(lcr, base + UART_REG_LCR);

	outb_p(divisor & 0xff, base + UART_REG_DLL);
	outb_p( (divisor >> 8 ) & 0xff, base + UART_REG_DLH);

	r = inb_p(base + UART_REG_DLH) << 8 | inb(base + UART_REG_DLL);

	// disable DLAB
	lcr &= MASK_DISABLE_LCR_DLAB;
	outb_p(lcr, base + UART_REG_LCR);

	// check if ok
	if (r != divisor) {
		printk("uart_set_baud: %x: failed to set speed: %d\n", base,speed);
		return 1;
	}

	return 0;
}

uart_id_t uart_ident(uint16_t base) {
	uint8_t r;

	// test for FIFO support
	outb_p(0xE7, base + UART_REG_FCR);

	r = inb_p(base + UART_REG_IIR);

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
		outb_p(0x42, base + UART_REG_SR);
		r = inb_p(base + UART_REG_SR);

		if (r == 0x42) return i16450;

		// XXX: I should probably distinguish among 8250, 8250A/B versions too
		return i8250;
	}

	return unknown;
}
