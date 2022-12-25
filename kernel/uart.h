#ifndef HAVE_UART_H
#define	HAVE_UART_H

#include <stdint.h>

/* 

Line Control Register (LCR) +3
	7		Divisor Latch Access Bit
	----------------------------------------
	6		Set Break Enable
	----------------------------------------
		5 4 3	parity select
		-----------------------
	3,4,5	0 0 0	no parity
		0 0 1	odd parity
		0 1 1	even parity
		1 0 1	mark
		1 1 1	space
	----------------------------------------
	2	0	one stop bit
		1	1.5 stop bits or 2 stop bits
	----------------------------------------
	0,1	1 0
		------------------------
		0 0	5 bits
		0 1	6 bits
		1 0	7 bits
		1 1	8 bits
	-----------------------------------------


Line Status Register (LSR) +5
	7 	Error in Received FIFO
	----------------------------------------
	6 	Empty Data Holding Registers
	----------------------------------------
	5 	Empty Transmitter Holding Register
	----------------------------------------
	4 	Break Interrupt
	----------------------------------------
	3 	Framing Error
	----------------------------------------
	2 	Parity Error
	----------------------------------------
	1 	Overrun Error
	----------------------------------------
	0 	Data Ready
	
*/

#define	COM1_BASE	0x3f8

#define	UART_REG_DLL		0	// divisor latch low byte
#define	UART_REG_DLH		1	// divisor latch high byte
#define	UART_REG_LCR		3	// line control register
#define	UART_REG_LSR		5	// line status register


#define	UART_REG_IER		1	// interrupt enable register

#define	UART_REG_IIR		2	// interrupt identification register (read)
#define	UART_REG_FCR		2	// FIFO control register (write)

#define	UART_REG_LSR		5	// line status register (read)
					// NOTE: write is undef

#define	UART_REG_SR		7	// scratch register (read/write)

#define	MASK_LCR_DLAB		0x80
#define MASK_DISABLE_LCR_DLAB	~(MASK_LCR_DLAB)

typedef enum uart_id {
	unknown = 0,
	i8250,
	i8250A,
	i8250B = 3,
	i16450,
	i16550,
	i16550A,
	i16750 = 7
} uart_id_t;

typedef struct uart_type {
	uart_id_t id;
	char* desc;
} uart_type_t;

uart_id_t uart_ident(uint16_t base);
int init_uart(uint16_t base);

void dbg_uart_write(char c, int16_t base);

#endif /* ifndef HAVE_UART_H */
