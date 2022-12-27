#ifndef HAVE_UART_H
#define	HAVE_UART_H

#include <stdint.h>

#define	COM1_BASE	0x3f8

#define	UART_REG_DLL		0	// with DLAB: divisor latch low byte (read/write)
#define	UART_REG_DLH		1	// with DLAB: divisor latch high byte (read/write)

#define	UART_REG_RBR		0	// receiver buffer (read)
#define	UART_REG_THR		0	// transmitter holding buffer (write)

#define	UART_REG_IER		1	// interrupt enable register (read/write)

#define	UART_REG_IIR		2	// interrupt identification register (read)
#define	UART_REG_FCR		2	// FIFO control register (write)

#define	UART_REG_LCR		3	// line control register (read/write)

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
int early_uart_init(uint16_t base);
int uart_set_baud(uint16_t base, uint32_t speed);

void dbg_uart_write(char c, int16_t base);
void dbg_uart_show(uint16_t base);

#endif /* ifndef HAVE_UART_H */
