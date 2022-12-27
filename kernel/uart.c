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

// XXX: dummy write test
void dbg_uart_write(char c, int16_t base) {
	int16_t i;
	uint8_t r;

	// XXX: how much waiting is enough ? I certainly don't want to wait indefinitely..
	for (i =0 ; i < 2048; i++) {
		r = inb_p(base + UART_REG_LSR);
		if (r == 0xff) goto out;		// error

		if ( (r & 0x20) ) {			// Empty Transmitter Holding Register
			outb_p(c, base + UART_REG_THR);
			goto out;
		}
		delay_p80();
	}
out:
	asm volatile("nop");
}

void dbg_uart_show(uint16_t base) {
	printk("base: 0x%x: LSR: 0x%x\n", base, inb(base + UART_REG_LSR));
}

// XXX	let's assume there is serial port at base right now
//	Disable FIFO, set 8N1 and try to negotiate as fast speed as possible
int early_uart_init(uint16_t base) {
	uart_id_t type;
	int i,status;
	uint8_t	r;

	printk("early_uart_init: attempting to enable com1 at base: 0x%x\n", base);

	type = uart_ident(base);
	printk("early_uart_init: 0x%x: %s\n", base,uart_types[type].desc);

	if (type == unknown)
		return 1;

	// no interrupts
	outb_p(0, base + UART_REG_IER);

	// 8N1
	outb_p(3, base + UART_REG_LCR);

	// disable FIFO
	outb_p(0, base + UART_REG_FCR);

/*
	// speed
	i = UART_COMMON_SPEED_VALS;
	status = 0;
	while (--i >= 0) {
		if ( (uart_set_baud(base, uart_common_speeds[i])) == 0) {
			status = 1;
			break;
		return 1;
		}
	}

	// failed to set the speed
	if (!status) {
		return 1;
	}
	printk("early_uart_init: speed set to %d\n", uart_common_speeds[i]);
*/
	if ((uart_set_baud(base, 9600)) != 0) {
		return 1;
	}

	r = inb_p(base + UART_REG_LCR);

	printk("early_uart_init: LCR: 0x%x\n", r);

	r = inb_p(base + UART_REG_LSR);
	printk("early_uart_init: LSR: 0x%x\n", r);

	return 0;
}

int uart_set_baud(uint16_t base, uint32_t speed) {
	uint16_t divisor;
	uint8_t lcr,r;

	if (speed == 0)
		speed = 9600;				// defaults to 9600

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
