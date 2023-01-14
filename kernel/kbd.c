#include "kbd.h"
#include "asm.h"
#include "pic.h"
#include "libk.h"

#define	KBDE_DATA_READY(s)		(s & MASK_KBDC_STATUS_OUTBUF)
#define	KBDE_WRITE_READY(s)		(!(s & MASK_KBDC_STATUS_INBUF))			// input buffer is 0: ready

#define	KBD_POLL_TRIES			2048

/* known keyboard device types */
#define	KBD_DEVICE_TYPES		14
struct kbd_devtype_name	kbd_device_type[KBD_DEVICE_TYPES] = {
	{ 0x0000, "unknown keyboard" },
	{ 0xff00, "AT keyboard" },		// 1 byte id
	{ 0xff03, "Standard PS/2 mouse" },	// 1 byte id
	{ 0xff04, "5-button mouse"},		// 1 byte id
	{ 0x41ab, "MF2 keyboard" },
	{ 0x83ab, "MF2 keyboard" },
	{ 0xc1ab, "MF2 keyboard" },
	{ 0x84ab, "IBM ThinkPads or alike"},
	{ 0x85ab, "NCD N-97 keyboard/122-key host connected keyboard"},
	{ 0x86ab, "122-key keyboard" },
	{ 0x90ab, "Japanese \"G\" keyboards"},
	{ 0x91ab, "Japanese \"P\" keyboards"},
	{ 0x92ab, "Japanese \"A\" keyboards"},
	{ 0xa1ac, "NCD Sun layout keyboard"}
};

kbd_state_t kbd;

// read port 0x60; used in ISR where we know there is data available
static inline uint8_t kbde_read() {
	return inb(KBDE_DATA_PORT);
}

// read port 0x64
static inline uint8_t kbdc_read_status() {
	return inb(KBDC_READ_STATUS_PORT);
}

// read port 0x60 when expecting answer to a cmd
int kbde_read_data() {
	uint8_t s;
	int i;

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

// writes to port 0x60
int kbde_write_command(uint8_t cmd) {
	uint8_t s;
	int i;

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

/* same as kbde_write_command but checks for ACK */
int kbde_write_cmd_with_ack(uint8_t cmd) {
	int r;

	if ((r = kbde_write_command(cmd)) == -1) {
		printk("%s: failed to send command 0x%x\n", __func__, cmd);
		return -1;
	}

	r = kbde_read_data();
	return r;
}

// writes to port 0x64
int kbdc_write_command(uint8_t cmd) {
	uint8_t s;
	int i;

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

// writes to port 0x64. If command is 2-byte (next byte), next byte needs to be written to 0x60
// if response is expected read from 0x60 has to be done
int kbdc_write_command_2(uint8_t cmd, uint8_t nextbyte, int flags) {
	int r;

	if ((r=kbdc_write_command(cmd)) == -1) {
		printk("%s: failed to write ctrl command 0x%x\n", __func__, r);
		return 1;
	}

	/* 2-byte command */
	if (flags & KBDC_TWOBYTE_CMD) {
		if ((r=kbde_write_command(nextbyte)) == -1) {
			printk("%s: failed to write nextbyte: 0x%x\n", __func__, r);
			return -1;
		}
	}

	if (flags & KBDC_RESPONSE_EXPECTED) {
		r = kbde_read_data();
		return r;
	}
	return 0;
}

/* check if PS/2 controller exists, install the kbd handler and enable irq1 */
/* XXX: in the future we should check ACPI tables to see if we have PS/2 ctrl */
int __init_kbd_module() {
	uint16_t id;
	int i,r;

	memset((void*)&kbd, 0, sizeof(struct kbd_state));

	// Test if system has ps/2 controller.

	// TODO:
	// 	pre-ACPI systems: assume ps/2 is there
	//	ACPI: check if ps/2 is there

	// XXX: order is not ok. ctrl byte should be read and ports disabled sooner

	// check #1: do we have a ps/2 controller ?
	if ((r = kbdc_write_command_2(KBDC_CMD_PS2_CTRL_TEST, 0, KBDC_RESPONSE_EXPECTED)) != KBDC_CMD_RESPONSE_SELFTEST_OK) {
		printk("%s: ps/2 controller selftest failed, error: 0x%x\n", __func__, r);
		return -1;
	}

	// check #2: ps/2 port 1
	if ((r = kbdc_write_command_2(KBDC_CMD_PS2_PORT1_TEST, 0, KBDC_RESPONSE_EXPECTED)) != 0) {
		printk("%s: ps/2 port1 test failed, error: 0x%x\n", __func__, r);
		return -1;
	}

	// check #3: ps/2: echo keyboard
	if ((r = kbde_write_cmd_with_ack(KBDE_CMD_RESPONSE_ECHO)) != KBDE_CMD_RESPONSE_ECHO) {
		printk("%s: ps/2 keyboard echo failed, error: 0x%x\n", __func__, r);
		return -1;
	}

	// ps/2 keyboard responded. Disable it before issuing further commands
	if((r=kbde_write_cmd_with_ack(KBDE_CMD_DISABLE)) != KBDE_CMD_RESPONSE_ACK) {
		printk("%s: failed to disable keyboard, error: 0x%x\n", __func__, r);
		return -1;
	}

	/* PS/2 port 1 is now disabled, we should enable it before quiting function in case of an error */


	// keyboard: disable translation
	r = (KBDC_CONFBYTE_1ST_PS2_INTERRUPT & ~KBDC_CONFBYTE_1ST_PS2_TRANSLATION)|KBDC_CONFBYTE_2ND_PS2_PORT_DISABLED;

	if ((kbdc_write_command_2(KBDC_CMD_WRITE_COMMAND_BYTE, r, KBDC_TWOBYTE_CMD|KBDC_NORESPONSE)) == -1) {
		printk("%s: warning: disabling translation failed.\n", __func__);
	}

	// keyboard: identify
	if(kbde_write_cmd_with_ack(KBDE_CMD_IDENTIFY) != KBDE_CMD_RESPONSE_ACK) {
		printk("%s: failed to identify keyboard\n", __func__);
	}

	// the 2nd id can be timeout error
	id = kbde_read_data();
	id = kbde_read_data() << 8 | id;

	// match the id against known device types
	kbd.devtype = &kbd_device_type[0];
	for (i =0; i < KBD_DEVICE_TYPES; i++) {
		if (id == kbd_device_type[i].kbd_device_id) {
			kbd.devtype = &kbd_device_type[i];
			break;
		}
	}
	printk("%s: keyboard: %s (%x)\n", __func__, kbd.devtype->kbd_name, id);

	if(kbde_write_cmd_with_ack(KBDE_CMD_ENABLE) != KBDE_CMD_RESPONSE_ACK) {
		printk("%s: failed to enable keyboard\n",  __func__);
		return -1;
	}

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

	printk("0x%x\n", scancode);

	kbd.kbuf[kbd.c_idx++] = scancode;
	kbd.flags = 1;		// ready for input

	if (scancode == SCAN1_LSHIFT || scancode == SCAN1_RSHIFT) {
		kbd.shift_flags = 1;
	}

	send_8259_EOI(1);
}
