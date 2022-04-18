#ifndef HAVE_PIC_H
#define HAVE_PIC_H 

/* PIC 8259 */
#define	PRIMARY_PIC_CMD_STAT_REG	0x20
#define	PRIMARY_PIC_IMR_DATA		0x21
#define	SLAVE_PIC_CMD_STAT_REG		0xa0
#define	SLAVE_PIC_IMR_DATA		0xa1
#define	CMD_EOI				0x20

/* PIT 825x */
#define	PIT_MODE_CMD_REG		0x43		/* write only */
#define	PIT_CHANNEL_0			0x40
#define	PIT_CHANNEL_1			0x41
#define	PIT_CHANNEL_2			0x42

/* IDT descriptor */
typedef struct interrupt_desc_t {
	uint16_t base_lo;
	uint16_t selector;
	uint8_t reserved;
	uint8_t type;
	uint16_t base_hi;
} __attribute__((packed)) interrupt_desc_t;

void init_8259(void);
void send_EOI(uint8_t irq);

void init_pit(void);

typedef void (*interrupt_handler_t)();

void install_handler(interrupt_handler_t handler, uint16_t sel, uint8_t irq, uint8_t type);

// debug
void install_dummyies();

#endif /* ifndef HAVE_PIC_H */
