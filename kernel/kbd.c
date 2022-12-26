#include "kbd.h"
#include "asm.h"
#include "pic.h"
#include "libsa.h"

/* I/O ports
	0x60	R/W	data port		encoder
	0x64	R	status register		controller
	0x64	W	command register	controller
*/

#define	KBD_DATA_PORT			0x60
#define	KBDC_READ_STATUS_PORT		0x64
#define	KBDC_WRITE_COMMAND_PORT		0x64

#define	KBD_MAX_READ_TRIES	255

#define	KBDC_MASK_STATUS_OUTBUF	1
#define	KBDC_MASK_STATUS_INBUF	2

#define	KBDC_CMD_READ_CTRL_OUTPUT	0xD0

#define	KBD_READY_FOR_CMD(s)	( (s) & KBDC_MASK_STATUS_INBUF )

/* let's try something simple first..*/
typedef struct kbd_state {
	#define	KBD_MAX_BUF	32
	#define	KBD_MAX_IDX	(KBD_MAX_BUF-1)
	uint8_t kbuf[KBD_MAX_BUF];
	uint8_t cursize;
} kbd_state_t;

kbd_state_t kbd;

volatile int lastc;

static inline int8_t kbdctrl_get_status() {
	return inb(KBDC_READ_STATUS_PORT);
}

static inline int8_t kbd_get_data() {
	return inb(KBD_DATA_PORT);
}

/* installs the kbd handler and enable irq1 */
void __init_kbd_module() {
	// set the proper ISR for irq1 and enable it
	memset((char*)&kbd, 0, sizeof(struct kbd_state));
	set_interrupt_handler(kbd_handler, 1);
	clear_irq(1);
}

// handler exits to the irq_cleanup code
void kbd_handler(__attribute__((unused)) struct trapframe* f) {

        uint8_t scancode = kbd_get_data();

	/*
	printk("%x ", scancode);

	printk("kbd: cursize: %d\n", kbd.cursize);
	if (kbd.cursize >= KBD_MAX_IDX) {
		printk("kbd: WARNING: buffer full, not buffering..\n");
	} else {
		kbd.kbuf[kbd.cursize++] = scancode;
	}
	*/

	lastc = scancode;

	send_8259_EOI(1);
}

// XXX i know, i know .. but for the time being my focus is on uart, so i'll let it be
uint8_t getc() {
	return lastc;
}
