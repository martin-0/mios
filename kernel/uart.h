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

#define	UART_REG_MCR		4	// modem control register (read/write)

#define	UART_REG_LSR		5	// line status register (read)
					// NOTE: write is undef

#define	UART_REG_MSR		6	// modem status register (read)
					// NOTE: write is undef

#define	UART_REG_SR		7	// scratch register (read/write)


#define	UART_MCR_OUT2		8	// aux output 2, needs to be toggled to enable interrupts

// XXX: I should not call these "MASK", they are toggles .. I'd expect mask to be ~OPTION..
//	need to rewrite this

#define	MASK_LSR_DATA_READY		0x1
#define	MASK_LSR_OVERRUN_ERR		0x2
#define	MASK_LSR_PARITY_ERR		0x4
#define	MASK_LSR_FRAMING_ERR		0x8
#define	MASK_LSR_BREAK_IRQ		0x10
#define	MASK_LSR_EMPTY_THR		0x20
#define	MASK_LSR_EMPTY_DHR		0x40
#define	MASK_LSR_ERROR_RCV_FIFO		0x80

// Line Control Register settings
#define	MASK_LCR_PARITY_NONE		0x0
#define	MASK_LCR_PARITY_ODD		0x8
#define	MASK_LCR_PARITY_EVEN		0x18
#define	MASK_LCR_PARITY_MARK		0x28
#define	MASK_LCR_PARITY_SPACE		0x38
#define	MASK_LCR_ONE_STOPBIT		0
#define	MASK_LCR_ONEHALF_TWO		4
#define	MASK_LCR_WORDSZ_5		0
#define	MASK_LCR_WORDSZ_6		1
#define	MASK_LCR_WORDSZ_7		2
#define	MASK_LCR_WORDSZ_8		3

#define	MASK_LCR_BREAK_ENABLE		0x40
#define	MASK_LCR_DLAB			0x80
#define MASK_DISABLE_LCR_DLAB		~(MASK_LCR_DLAB)

#define	POLL_WRITE_RETRIES	2048	// assume write failed after these attempts

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

// XXX: I should maybe thing about common device descriptors .. but it's probably way to soon for this
// XXX: unused right now
typedef struct uart_port {
	uart_id_t id;
	uint16_t base;
	uint32_t speed;
	char irq;
	int flags;
} uart_port_t;

uart_id_t uart_ident(uint16_t base);
int early_uart_init(uint16_t base, uint32_t speed);
int uart_set_baud(uint16_t base, uint32_t speed);
uint8_t uart_get_lsr(uint16_t base);

int poll_uart_write(char c, int16_t base);

int uart_init(uint16_t base, uint32_t speed);

#include "pic.h"
void uart_isr_handler(struct trapframe* f);

#endif /* ifndef HAVE_UART_H */
