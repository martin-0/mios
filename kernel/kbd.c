#include "kbd.h"
#include "asm.h"
#include "pic.h"
#include "libsa.h"

/* I/O port

http://www-ug.eecg.toronto.edu/msl/nios_devices/datasheets/PS2%20Keyboard%20Protocol.htm

	0x60	write	data sent directly to keyboard/aux device
	0x60	read	data from 8042
	0x64	write	8042 commands
	0x64	read	8042 satus register

	0x60	R/W	data port		encoder
	0x64	R	status register		controller
	0x64	W	command register	controller


controller:
    A one-byte input buffer - contains byte read from keyboard; read-only		- read input buffer  0x60
    A one-byte output buffer - contains byte to-be-written to keyboard; write-only	- write output buffer 0x60
    A one-byte status register - 8 status flags; read-only				- read status reg 0x64
    A one-byte control register - 7 control flags; read/write 				- need to use cmd to do that


*/

#define	KBDE_DATA_PORT			0x60
#define	KBDC_READ_STATUS_PORT		0x64
#define	KBDC_WRITE_COMMAND_PORT		0x64

#define	MASK_KBDC_STATUS_OUTBUF		0x1		// from ctrl to CPU
#define	MASK_KBDC_STATUS_INBUF		0x2		// from CPU to ctrl
#define	MASK_KBDC_SYSTEM_FLAG		0x4
#define	MASK_KBDC_COMMAND_DATA		0x8
#define	MASK_KBDC_LOCKED		0x10
#define	MASK_KBDC_AUX_BUF_FULL		0x20
#define	MASK_KBDC_TIMEOUT		0x40
#define	MASK_KBDC_PARITY_ERR		0x80

#define	KBDC_CMD_PS2_CTRL_TEST		0xAA
#define	KBDC_CMD_PS2_PORT1_TEST		0xAB
#define	KBDC_CMD_READ_CTRL_OUTPUT	0xD0

#define	KBDE_CMD_ECHO			0xEE


#define	KBDE_DATA_READY(s)		(s & MASK_KBDC_STATUS_OUTBUF)
#define	KBDE_WRITE_READY(s)		(!(s & MASK_KBDC_STATUS_INBUF))			// input buffer is 0: ready

#define	KBD_POLL_TRIES	2048

/* let's try something simple first..*/
typedef struct kbd_state {
	unsigned char shift_flags;
	unsigned char led_state;
} kbd_state_t;

kbd_state_t kbd;

volatile int lastc;

// read port 0x60; used in ISR where we know there is data available
static inline int8_t kbde_read() {
	return inb(KBDE_DATA_PORT);
}

// read port 0x64
static inline int8_t kbdc_read_status() {
	return inb(KBDC_READ_STATUS_PORT);
}

// read port 0x60 when expecting answer to a cmd
int8_t kbde_read_data() {
	int i;
	uint8_t s;

	for (i =0; i < KBD_POLL_TRIES; i++) {
		s = kbdc_read_status();
		//printk("%s: i: %d: status: %x\n", __func__, i, s);

		if (KBDE_DATA_READY(s)) {
			s = inb(KBDE_DATA_PORT);
			//printk("%s: data read: %x\n", __func__, s);
			return s;
		}
		delay_p80();
	}

	#ifdef DEBUG
	printk("%s: timeout occured waiting for kbde output buffer.\n", __func__);
	#endif

	return -1;
}

// write port 0x60
int8_t kbde_write_command(uint8_t cmd) {
	int i;
	uint8_t s;

	for (i=0; i < KBD_POLL_TRIES; i++) {
		s = kbdc_read_status();
		//printk("%s: i: %d: cmd: %x, status: %x\n", __func__, i, cmd, s);

		if (KBDE_WRITE_READY(s)) {
			outb(cmd, KBDE_DATA_PORT);
			return 0;
		}
	}
	#ifdef DEBUG
	printk("%s: %x failed: %x\n", __func__, cmd, s);
	#endif
	return -1;
}

// write to port 0x64
int8_t kbdc_write_command(uint8_t cmd) {
	int i;
	uint8_t s;

	for (i=0; i < KBD_POLL_TRIES; i++) {
		s = kbdc_read_status();
		//printk("%s: i: %d: cmd: %x, status: %x\n", __func__, i, cmd, s);

		if (KBDE_WRITE_READY(s)) {
			outb(cmd, KBDC_WRITE_COMMAND_PORT);
			return 0;
		}
		//printk("%s: %x failed: %x\n", __func__, cmd, s);
	}
	#ifdef DEBUG
	printk("%s: %x failed: %x\n", __func__, cmd, s);
	#endif
	return -1;
}

/* installs the kbd handler and enable irq1 */
int __init_kbd_module() {
	uint8_t c, e;

	memset((char*)&kbd, 0, sizeof(struct kbd_state));

/*
	printk("test of PS/2 controller\n");

	// check for controller
	if ((kbdc_write_command(KBDC_CMD_PS2_CTRL_TEST)) == -1) {
		printk("failed to send KBDC_CMD_PS2_CTRL_TEST\n");
	}

	if ((c = kbde_read_data()) != 0x55) {
		printk("test failed: %x\n", c);
	} else {
		printk("test passed: %x\n", c);
	}

	// check for ps/2 port
	printk("testing PS/2 port\n");
	if ((kbdc_write_command(KBDC_CMD_PS2_PORT1_TEST)) == -1) {
		printk("%s: failed to send KBDC_CMD_PS2_PORT1_TEST\n", __func__);
	}

	if ((c = kbde_read_data()) != 0) {
		printk("PS/2 port test failed with err: %x\n", c);
	} else {
		printk("PS/2 port check passed.\n");
	}


	// check if keyboard replies to echo
	printk("%s: sending echo request to keyboard\n", __func__);
	if ((kbde_write_command(KBDE_CMD_ECHO)) == -1) {
		printk("%s: failed to send KBDE_CMD_ECHO\n", __func__);
	}
	if ((c = kbde_read_data()) != 0xEE) {
		printk("echo keyboard test failed.\n");
	} else {
		printk("echo keyboard test passed.\n");
	}

	if ((kbdc_write_command(0x20)) == -1) {
		printk("%s: failed to send command 0x20\n", __func__);
		return -1;
	}

	e = kbde_read_data();
	printk("%s: 0x20 reply: %x\n", __func__, e);

	if ((kbdc_write_command(0x60)) == -1) {
		printk("%s: failed to send command 0x60\n", __func__);
		return -1;
	}
	kbde_write_command(1);
*/

	#ifdef DEBUG
	printk("%s: about to enable irq1\n", __func__);
	#endif

	set_interrupt_handler(kbd_isr_handler, 1);
	clear_irq(1);
	return 0;
}

// handler exits to the irq_cleanup code
void kbd_isr_handler(__attribute__((unused)) struct trapframe* f) {
	//printk("%s: attempting to get data\n", __func__);

	uint8_t scancode = kbde_read();

	//printk("%s: scancode: %x\n", __func__, scancode);

	// XXX: I need to figure out how I'm going to deal with this. handler should only update kbd state machine, but that's it
	// 	Yes, main right now waits in loop for some key press but that should behave as a shell of sort..

	lastc = scancode;

	send_8259_EOI(1);
}

// XXX i know, i know .. but for the time being my focus is on uart, so i'll let it be
uint8_t getc() {
	int r = lastc;
	lastc = 0;
	return r;
}
