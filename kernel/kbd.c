#include "kbd.h"
#include "asm.h"
#include "pic.h"
#include "libk.h"

#define	KBDE_DATA_READY(s)		(s & MASK_KBDC_STATUS_OUTBUF)
#define	KBDE_WRITE_READY(s)		(!(s & MASK_KBDC_STATUS_INBUF))			// input buffer is 0: ready

#define	KBD_POLL_TRIES			16384

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

struct kbdc atkbdc;
struct kbd atkbd;

// read port 0x60; used in ISR where we know there is data available
static inline uint8_t kbde_read() {
	return inb(KBDE_DATA_PORT);
}

// read port 0x64
static inline uint8_t kbdc_read_status() {
	return inb(KBDC_READ_STATUS_PORT);
}

/* poll-read port 0x60 when expecting answer to a cmd
 *
 * return:	contents of 0x60 port on success
 *		-1 on timeout
*/
int kbde_poll_read() {
	uint8_t r;
	int i;

	for (i =0; i < KBD_POLL_TRIES; i++) {
		r = kbdc_read_status();
		//printk("%s: i: %d: status: %x\n", __func__, i, r);

		if (KBDE_DATA_READY(r)) {
			r = inb(KBDE_DATA_PORT);
			//printk("%s: data read: %x\n", __func__, r);
			return r;
		}
		delay_p80();
	}

	#ifdef DEBUG
	printk("%s: timeout reached waiting for buffer.\n", __func__);
	#endif

	return -1;
}

/* poll-writes to port 0x60 */
int kbde_poll_write(uint8_t cmd) {
	uint8_t s;
	int i;

	for (i=0; i < KBD_POLL_TRIES; i++) {
		s = kbdc_read_status();
		//printk("%s: i: %d: cmd: %x, status: %x\n", __func__, i, cmd, s);

		// XXX: what about TOCTOU issue ? If I call these functions from isr handler it should be ok
		//	but what if something outside of isr tries to r/w to this port?
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

/* same as kbde_poll_write but checks for kbde response */
int kbde_poll_write_a(uint8_t cmd) {
	int r;

	if ((r = kbde_poll_write(cmd)) == -1) {
		printk("%s: failed to send command 0x%x\n", __func__, cmd);
		return -1;
	}

	// response readback
	delay_p80();
	r = kbde_poll_read();
	return r;
}

/* poll-write to port 0x64
 *
 * return: 0 on success, -1 on failure
*/
int kbdc_poll_write(uint8_t cmd) {
	uint8_t s;
	int i;

	for (i=0; i < KBD_POLL_TRIES; i++) {
		s = kbdc_read_status();
		//printk("%s: i: %d: cmd: %x, status: %x\n", __func__, i, cmd, s);

		// XXX: same as kbde_poll_write, TOCTOU issue maybe?
		if (KBDE_WRITE_READY(s)) {
			outb(cmd, KBDC_WRITE_COMMAND_PORT);
			return 0;
		}
		//printk("%s: %x failed: %x\n", __func__, cmd, s);
	}
	#ifdef DEBUG
	printk("%s: failed to send cmd 0x%x, status: 0x%x\n", __func__, cmd, s);
	#endif
	return -1;
}

/* Sends command to keyboard controller. Two-byte command is split and sent to port 0x64 and 0x60.
 * If response to command is expected port 0x60 is polled for returned value.
 *
 * return:	0 on success for commands that don't expect response, -1 otherwise
 *		value of 0x60 port when response is required, -1 if timeout occured
 *
*/
int kbdc_send_cmd(uint8_t cmd, uint8_t nextbyte, int flags) {
	int r, retries;

	if ((r=kbdc_poll_write(cmd)) == -1) {
		printk("%s: failed to write ctrl command 0x%x\n", __func__, r);
		return -1;
	}

	/* 2-byte command */
	if (flags & KBDC_TWOBYTE_CMD) {
		if ((r=kbde_poll_write(nextbyte)) == -1) {
			printk("%s: failed to write next command byte 0x%x: 0x%x\n", __func__, nextbyte, r);
			return -1;
		}
	}

	if (flags & KBDC_RESPONSE_EXPECTED) {
		r = kbde_poll_read();
		return r;
	}
	return 0;
}

/* check if PS/2 controller exists, install the kbd handler and enable irq1 */
/* XXX: in the future we should check ACPI tables to see if we have PS/2 ctrl */
int __init_kbd_module() {
	printk("%s: enter\n", __func__);

	uint16_t id;
	int i,r,cbyte;
	int exp_ctrl_response;
	int ps2_p1,ps2_p2;

	// XXX
	int is_dualport;
	int is_at = 0;

	memset((void*)&atkbdc, 0, sizeof(struct kbdc));
	memset((void*)&atkbd, 0, sizeof(struct kbd));

	strcpy(atkbdc.devname, NAME_KBDC);

	// Test if system has PS/2 controller.

	// TODO:
	// 	pre-ACPI systems: assume PS/2 is there, the worst case scenario AT
	//	ACPI: check if PS/2 is there
	//	code assumes there is PS/2 controller
	//	allow to resend commands when failure occurs before giving up on controller

	// XXX:	check for the reason why write fails ?

	/* step 1:	Disable PS/2 ports.
		If PS/2 port 2 doesn't exist command is ignored.
		On PS/2 ctrl KBDC_CMD_DISABLE_PS2_P2 sets bit5 to 1(disable)
		On AT ctrl it does nothing, bit5 is 0
	*/

	if ((r = kbdc_send_cmd(KBDC_CMD_DISABLE_PS2_P1, 0, KBDC_NORESPONSE)) != 0) {
		printk("KBDC_CMD_DISABLE_PS2_P1 failed, error: 0x%x\n", r);
		return -1;
	}

	if ((r = kbdc_send_cmd(KBDC_CMD_DISABLE_PS2_P2, 0, KBDC_NORESPONSE)) != 0) {
		printk("KBDC_CMD_DISABLE_PS2_P2 failed, error: 0x%x\n", r);
		return -1;
	}

	/* step 2:	flush the output buffer */
	// XXX: do I really need to do this up to 16 times?
	#define	i8042_BUFSZ	16
	for (i =0 ; i < i8042_BUFSZ; i++) {
		r = kbde_read();
	}

	/* step 3:	read the control byte from controller and disable port interrupts and translation */
	if ((cbyte = kbdc_send_cmd(KBDC_CMD_READ_COMMAND_BYTE, 0, KBDC_RESPONSE_EXPECTED)) == -1) {
		printk("KBDC_CMD_READ_COMMAND_BYTE failed: 0x%x\n", cbyte);
		return -1;
	}
	printk("read control byte: 0x%x\n", cbyte);

	/* if bit5 was not toggled we are using AT connector */
	if ( (cbyte & KBDC_CONFBYTE_PS2_P1_DISABLED) == 0 ) {
		is_at = 1;
		atkbdc.at_ctrl = 1;
		exp_ctrl_response = 0;
		printk("AT controller\n");
	} else {
		is_at = 0;
		exp_ctrl_response = KBDC_CMD_RESPONSE_SELFTEST_OK;
		printk("PS/2 controller\n");
	}

	/* disable port interrupts and translation */
	cbyte &= ~(KBDC_CONFBYTE_PS2_P1_INTERRUPT|KBDC_CONFBYTE_PS2_P2_INTERRUPT|KBDC_CONFBYTE_PS2_P1_TRANSLATION);
	printk("new control byte: 0x%x\n", cbyte);

	if ((kbdc_send_cmd(KBDC_CMD_WRITE_COMMAND_BYTE, cbyte, KBDC_TWOBYTE_CMD|KBDC_NORESPONSE)) == -1) {
		printk("warning: KBDC_CMD_WRITE_COMMAND_BYTE failed.\n");
		// allow to do the selftest, if that fails return with error
	}

	/* step 4:	initiate SELFTEST of the controller */
	if ((r = kbdc_send_cmd(KBDC_CMD_PS2_CTRL_SELFTEST, 0, KBDC_RESPONSE_EXPECTED)) != exp_ctrl_response) {
		printk("PS/2 controller selftest failed, error: 0x%x (expected 0x%x)\n", r, exp_ctrl_response);
		return -1;
	}

	/* step 5:	check for 2nd port on ps/2 controller */
	if (!atkbdc.at_ctrl) {
		printk("check for PS/2 ps2_p2\n");
		if ((r = kbdc_send_cmd(KBDC_CMD_ENABLE_PS2_P2, 0, KBDC_NORESPONSE)) != 0) {
			printk("KBDC_CMD_ENABLE_PS2_P2 failed, error: 0x%x\n", r);
		}

		if ((cbyte = kbdc_send_cmd(KBDC_CMD_READ_COMMAND_BYTE, 0, KBDC_RESPONSE_EXPECTED)) == -1) {
			printk("KBDC_CMD_READ_COMMAND_BYTE failed: 0x%x\n", cbyte);
		}
		printk("cbyte after ps2p2 enable: %x\n", cbyte);

		if ( (cbyte & KBDC_CONFBYTE_PS2_P2_DISABLED) == 0) {
			printk("PS/2 2nd port exists (cbyte 0x%x)\n", cbyte);
			is_dualport = 1;
			atkbdc.nrports = 2;

			// disable for now
			if ((r = kbdc_send_cmd(KBDC_CMD_DISABLE_PS2_P2, 0, KBDC_NORESPONSE)) != 0) {
				printk("KBDC_CMD_ENABLE_PS2_P2 failed, error: 0x%x\n", r);
			}
			if ((cbyte = kbdc_send_cmd(KBDC_CMD_READ_COMMAND_BYTE, 0, KBDC_RESPONSE_EXPECTED)) == -1) {
				printk("KBDC_CMD_READ_COMMAND_BYTE failed: 0x%x\n", cbyte);
			}
			printk("cbyte after ps2p2 disable: %x\n", cbyte);
		}
	}

	/* no PS/2 ports enabled by default */
	ps2_p1 = ps2_p2 = 0;

	/* prepare the configuration byte */
	cbyte = KBDC_CONFBYTE_PS2_P1_DISABLED|KBDC_CONFBYTE_PS2_P2_DISABLED|KBDC_CONFBYTE_SYSFLAG_BAT;

	/* step 6: interface tests */
	if ((r = kbdc_send_cmd(KBDC_CMD_PS2_P1_TEST, 0, KBDC_RESPONSE_EXPECTED)) != 0) {
		#ifdef DEBUG
		printk("PS/2 port1 test failed, error: 0x%x\n", r);
		#endif
	} else {
		ps2_p1 = 1;
		cbyte |= KBDC_CONFBYTE_PS2_P1_INTERRUPT;
		cbyte &= ~KBDC_CONFBYTE_PS2_P1_DISABLED;
	}

	if (is_dualport) {
		if ((r = kbdc_send_cmd(KBDC_CMD_PS2_P2_TEST, 0, KBDC_RESPONSE_EXPECTED)) != 0) {
			#ifdef DEBUG
			printk("PS/2 port2 test failed, error: 0x%x\n", r);
			#endif
		} else {
			ps2_p2 = 1;
			cbyte |= KBDC_CONFBYTE_PS2_P2_INTERRUPT;
			cbyte &= ~KBDC_CONFBYTE_PS2_P2_DISABLED;
		}
	}

	if ( (ps2_p1 || ps2_p2) == 0) {
		printk("no devices found..giving up.\n");
		return -1;
	}

	// XXX: Enable devices. For port send disable scanning, querry the kbd info, enable scanning
	//	disable scanning: f5 is basically reset 

	if ((r = kbde_poll_write_a(KBDE_CMD_RESPONSE_ECHO)) != KBDE_CMD_RESPONSE_ECHO) {
		printk("ps/2 keyboard echo failed, error: 0x%x, status: 0x%x", r, kbdc_read_status());
	}

	// keyboard: identify
	if(kbde_poll_write_a(KBDE_CMD_IDENTIFY) != KBDE_CMD_RESPONSE_ACK) {
		printk("failed to identify keyboard\n");
	}
	else {
		// the 2nd id can be timeout error
		id = kbde_poll_read();
		id = kbde_poll_read() << 8 | id;

		// match the id against known device types
		atkbd.devtype = kbd_device_type[0];
		for (i =0; i < KBD_DEVICE_TYPES; i++) {
			if (id == kbd_device_type[i].kbd_device_id) {
				atkbd.devtype = kbd_device_type[i];
				break;
			}
		}
		printk("keyboard: %s (%x)\n", atkbd.devtype.kbd_name, id);
	}

	if ( ps2_p1 && ((r = kbdc_send_cmd(KBDC_CMD_ENABLE_PS2_P1, 0, KBDC_NORESPONSE)) != 0)) {
		printk("KBDC_CMD_ENABLE_PS2_P1 failed, error: 0x%x\n", r);
		return -1;
	}

	if (ps2_p2 && ((r = kbdc_send_cmd(KBDC_CMD_ENABLE_PS2_P2, 0, KBDC_NORESPONSE)) != 0)) {
		printk("KBDC_CMD_ENABLE_PS2_P2 failed, error: 0x%x\n", r);
		return -1;
	}

	cbyte &= ~KBDC_CONFBYTE_PS2_P1_TRANSLATION;
	printk("final cbyte: %x\n", cbyte);

	/* step 7:	enable devices */
	if ((kbdc_send_cmd(KBDC_CMD_WRITE_COMMAND_BYTE, cbyte, KBDC_TWOBYTE_CMD|KBDC_NORESPONSE)) == -1) {
		printk("warning: KBDC_CMD_WRITE_COMMAND_BYTE failed.\n");
	}


	// Note: we'll assume keyboard even if the keyboard is unknown
	if(ps2_p1) {
		r = kbde_poll_write_a(0xff);
		printk("kbde response to 0xff command: %x\n", r);
		r = kbde_poll_read();
		printk("its result: %x\n", r);

	}


	/* to be removed
	// XXX: I need to expand flags and add support for 2nd port ; status port bit5 indicate data is ready
	//	from 2nd port

	printk("trying to send command to 2nd port:\n");
	if(ps2_p2) {
		//if ((r = kbdc_send_cmd(0xD4, 0xff, KBDC_TWOBYTE_CMD|KBDC_NORESPONSE)) == -1) {
		if ((r = kbdc_send_cmd(0xd4, 0xf4, KBDC_TWOBYTE_CMD|KBDC_RESPONSE_EXPECTED)) == -1) {
			printk("warning: 0xd4 command failed: 0x%x\n",r);
		}
		else {
			printk("ok: 0x%x\n", r);

		}
	}
	*/

	#ifdef DEBUG
	printk("about to enable irq1\n");
	#endif

	set_interrupt_handler(kbd_isr_handler, 1);
	clear_irq(1);

	// XXX: just to test
	//set_interrupt_handler(psm_isr_handler, 12);
	//clear_irq(12);

	printk("%s: exit\n", __func__);
	return 0;
}

// handler exits to the irq_cleanup code
void kbd_isr_handler(__attribute__((unused)) struct trapframe* f) {
	//printk("%s: attempting to get data\n", __func__);
	uint8_t scancode = kbde_read();

	printk("0x%x\n", scancode);

	atkbd.kbuf[atkbd.c_idx++] = scancode;
	atkbd.flags = 1;		// ready for input

	if (scancode == SCAN1_LSHIFT || scancode == SCAN1_RSHIFT) {
		atkbd.special_keys = 1;
	}
	send_8259_EOI(1);
}

/*
// XXX: this should be in its separate module ; using here just for tests
void psm_isr_handler(__attribute__((unused)) struct trapframe* f) {
	int r;
	if ((r = kbdc_send_cmd(0xd4, 0xeb, KBDC_TWOBYTE_CMD|KBDC_RESPONSE_EXPECTED)) == -1) {
		printk("warning: 0xd4/0xeb command failed: 0x%x\n",r);
	}

	r = kbde_read();
	printk("%s: %x\n", __func__, r);

	send_8259_EOI(12);
}
*/
