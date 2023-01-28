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

device_t devkbd = {
	.devname = "unknown",
	.dev = (struct kbd*)&atkbd
};


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
			outb_p(cmd, KBDE_DATA_PORT);
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
	int r;

	if ((r=kbdc_poll_write(cmd)) == -1) {
		printk("%s: failed to write ctrl command 0x%x\n", __func__, r);
		return -1;
	}

	/* 2-byte command */
	if (flags & SENDCMD_TWOBYTE) {
		if ((r=kbde_poll_write(nextbyte)) == -1) {
			printk("%s: failed to write next command byte 0x%x: 0x%x\n", __func__, nextbyte, r);
			return -1;
		}
	}

	if (flags & SENDCMD_RESPONSE_EXPECTED) {
		r = kbde_poll_read();
		return r;
	}
	return 0;
}

/* check if PS/2 controller exists, install the kbd handler and enable irq1 */
/* XXX: in the future we should check ACPI tables to see if we have PS/2 ctrl */
int __init_kbd_module() {
	uint16_t id;
	int i,r,cbyte,orig_cbyte;
	int exp_ctrl_response;
	int ps2_ports[2];

	memset((void*)&atkbdc, 0, sizeof(struct kbdc));
	memset((void*)&atkbd, 0, sizeof(struct kbd));
	memset((void*)&devkbd, 0, sizeof(devkbd));

	strcpy(atkbdc.devname, KBDC_NAME);

	// Test if system has PS/2 controller.

	// TODO:
	// 	pre-ACPI systems: assume PS/2 is there, the worst case scenario AT
	//	ACPI: check if PS/2 is there
	//	code assumes there is PS/2 controller
	//	allow to resend commands when failure occurs before giving up on controller
	//	resend command in case of an failure ?

	/* step 1:	Disable PS/2 ports.
		If PS/2 port 2 doesn't exist command is ignored.
		On PS/2 ctrl KBDC_CMD_DISABLE_PS2_P2 sets bit5 to 1(disable).
		On AT ctrl it does nothing, bit5 is 0.

		Initialization tries to disable both ports. If error occurs further down
		during initialization ports are kept disabled.
	*/

	if ((r = kbdc_send_cmd(KBDC_CMD_DISABLE_PS2_P1, 0, SENDCMD_NORESPONSE)) != 0) {
		#ifdef DEBUG
		printk("kbd: KBDC_CMD_DISABLE_PS2_P1 failed, error: 0x%x\n", r);
		#endif
		return -1;
	}

	if ((r = kbdc_send_cmd(KBDC_CMD_DISABLE_PS2_P2, 0, SENDCMD_NORESPONSE)) != 0) {
		#ifdef DEBUG
		printk("kbd: KBDC_CMD_DISABLE_PS2_P2 failed, error: 0x%x\n", r);
		#endif
		return -1;
	}

	/* step 2:	flush the output buffer */
	for (i =0 ; i < KBDC_INTERNAL_BUFSIZE ; i++) {
		r = kbde_read();
	}

	/* step 3:	read the control byte from controller and disable port interrupts and translation */
	if ((cbyte = kbdc_send_cmd(KBDC_CMD_READ_COMMAND_BYTE, 0, SENDCMD_RESPONSE_EXPECTED)) == -1) {
		printk("kbd: KBDC_CMD_READ_COMMAND_BYTE failed: 0x%x\n", cbyte);
		return -1;
	}

	// save for later
	orig_cbyte = cbyte;

	/* if bit5 was not toggled we are using AT controller */
	if ( (cbyte & KBDC_CONFBYTE_PS2_P1_DISABLED) == 0 ) {
		atkbdc.at_ctrl = 1;
		exp_ctrl_response = 0;
	}
	else {
		exp_ctrl_response = KBDC_CMD_RESPONSE_SELFTEST_OK;
	}

	/* disable port interrupts and translation, allow selftest even if this command fails */
	cbyte &= ~(KBDC_CONFBYTE_PS2_P1_INTERRUPT|KBDC_CONFBYTE_PS2_P2_INTERRUPT|KBDC_CONFBYTE_PS2_P1_TRANSLATION);

	if ((kbdc_send_cmd(KBDC_CMD_WRITE_COMMAND_BYTE, cbyte, SENDCMD_TWOBYTE|SENDCMD_NORESPONSE)) == -1) {
		printk("kbd: WARNING: KBDC_CMD_WRITE_COMMAND_BYTE failed, proceeding anyway.\n");
	}

	/* step 4:	initiate SELFTEST of the controller

		If there was a problem with keyboard POST test would probably catch it.
		Selftest is important enough to make an effort here and retry few times before giving up.
	*/
	for (i =0; i < KBD_RETRY_ATTEMPTS; i++) {
		if ((r = kbdc_send_cmd(KBDC_CMD_PS2_CTRL_SELFTEST, 0, SENDCMD_RESPONSE_EXPECTED)) == exp_ctrl_response) {
			break;
		}
		printk("kbd: PS/2 controller selftest failed (0x%x), %d of %d\n", r, i, KBD_RETRY_ATTEMPTS);
	}

	if (r != exp_ctrl_response) {
		printk("kbd: PS/2 controller selftest failed.\n");
		return -1;
	}

	/* prepare the configuration byte again */
	// cbyte = orig_cbyte & ~(KBDC_CONFBYTE_PS2_P1_INTERRUPT|KBDC_CONFBYTE_PS2_P2_INTERRUPT|KBDC_CONFBYTE_PS2_P1_TRANSLATION);
	cbyte = orig_cbyte & ~(KBDC_CONFBYTE_PS2_P1_INTERRUPT|KBDC_CONFBYTE_PS2_P2_INTERRUPT);

	/* step 6:	interface tests */
	// port1
	if ((r = kbdc_send_cmd(KBDC_CMD_PS2_P1_TEST, 0, SENDCMD_RESPONSE_EXPECTED)) == KBDC_CMD_RESPONSE_PORTTEST_OK) {
		ps2_ports[0] = 1;
		atkbdc.nports++;
		cbyte |= KBDC_CONFBYTE_PS2_P1_INTERRUPT;
		cbyte &= ~KBDC_CONFBYTE_PS2_P1_DISABLED;
	}
	else {
		#ifdef DEBUG
		printk("kbd: PS/2 port1 test failed, error: 0x%x\n", r);
		#endif
		cbyte |= KBDC_CONFBYTE_PS2_P1_DISABLED;
	}

	// port2
	if ((r = kbdc_send_cmd(KBDC_CMD_PS2_P2_TEST, 0, SENDCMD_RESPONSE_EXPECTED)) == KBDC_CMD_RESPONSE_PORTTEST_OK) {
		ps2_ports[1] = 1;
		atkbdc.nports++;
		cbyte |= KBDC_CONFBYTE_PS2_P2_INTERRUPT;
		cbyte &= ~KBDC_CONFBYTE_PS2_P2_DISABLED;
	}
	else {
		#ifdef DEBUG
		printk("kbd: PS/2 port1 test failed, error: 0x%x\n", r);
		#endif
		cbyte |= KBDC_CONFBYTE_PS2_P1_DISABLED;
	}

	/* It's expected that keyboard is behind port 1. Some BIOSes even throw error if they don't find
	   keyboard there. I'll do the same for now.
	*/
	if (!(ps2_ports[0])) {
		return -1;
	}

	if((r = kbde_poll_write_a(KBDE_CMD_IDENTIFY)) != KBDE_CMD_RESPONSE_ACK) {
		#ifdef DEBUG
		printk("kbd: failed to send KBDE_CMD_IDENTIFY\n");
		#endif
	}

	// the 2nd id can be timeout error
	id = kbde_poll_read();
	id = kbde_poll_read() << 8 | id;

	atkbd.kbd_device_id = id;

	// match the id against known device types
	for (i =0; i < KBD_DEVICE_TYPES; i++) {
		if (id == kbd_device_type[i].kbd_device_id) {
			strcpy(devkbd.devname, kbd_device_type[i].kbd_name);
			break;
		}
	}

	// assing to port
	atkbdc.ports[0] = &devkbd;
	devkbd.devtype = D_KEYBOARD;

	/* step 7:	enable devices */
	if ( ps2_ports[0] && ((r = kbdc_send_cmd(KBDC_CMD_ENABLE_PS2_P1, 0, SENDCMD_NORESPONSE)) != 0)) {
		#ifdef DEBUG
		printk("kbd: warning: KBDC_CMD_ENABLE_PS2_P1 failed, error: 0x%x\n", r);
		#endif
	}

	if ( ps2_ports[1] && ((r = kbdc_send_cmd(KBDC_CMD_ENABLE_PS2_P2, 0, SENDCMD_NORESPONSE)) != 0)) {
		#ifdef DEBUG
		printk("kbd: warning: KBDC_CMD_ENABLE_PS2_P2 failed, error: 0x%x\n", r);
		#endif
	}

	/* XXX: disabling translation can be a problem for some keyboards/devices. Should I stick
		to scancode1 then ? To be decided when driver does actual job of mapping it to ascii..
	*/
	//cbyte &= ~KBDC_CONFBYTE_PS2_P1_TRANSLATION;
	if ((kbdc_send_cmd(KBDC_CMD_WRITE_COMMAND_BYTE, cbyte, SENDCMD_TWOBYTE|SENDCMD_NORESPONSE)) == -1) {
		printk("warning: KBDC_CMD_WRITE_COMMAND_BYTE failed.\n");
	}

	/* step 8:	reset keyboard

		Keyboard reset command is put into queue and will be handled in queue.
		Command queue is irq1 driven.
	*/

/*
	atkbdc.cmd_q[atkbdc.cqi].cmd[0] = KBDE_CMD_RESET;
	atkbdc.cmd_q[atkbdc.cqi].flags = SENDCMD_RESPONSE_EXPECTED;
	atkbdc.cmd_q[atkbdc.cqi].dst_port = PS2_ENCODER;
	atkbdc.cmd_q[atkbdc.cqi].status = S_KCMD_READY;
	atkbdc.cq_idx++;
*/
	struct kbdc_command* nc = RING32_PEEK_FI(&atkbdc.cmd_q);

	// test of get current scancode command
	nc->cmd[0] = 0xf0;
	nc->cmd[1] = 0;
	nc->flags = KFLAG_WAIT_ACK|KFLAG_TWOBYTE_CMD|KFLAG_WAIT_DATA;
	nc->dst_port = PS2_ENCODER;
	nc->status = S_KCMD_READY;
	nc->retries = 0;
	RING32_STORE("cmdq", &atkbdc.cmd_q, *nc);

	set_interrupt_handler(kbd_isr_handler, 1);

	kbdc_handle_command();
	clear_irq(1);
	return 0;
}

// handler exits to the irq_cleanup code
void kbd_isr_handler(__attribute__((unused)) struct trapframe* f) {
	uint8_t scancode = kbde_read();

	printk("isr sc: 0x%x\n", scancode);

	/* XXX:
		I need to start simple. Maybe I should have focused on different
		parts of the kernel fist but I decided to go this way.
		There's no scheduling, no events yet. Even lack of memory management
		is bad as these structures should have been dynamically allocated.

		That being said I have kbd ISR that is reading scan codes. Here I can
		read and empty command queue and do the logic of the kbd driver - update
		keyboard state machine. Not ideal, but it's a start..

	   XXX:
		Current lack of kbd driver is problematic here. I can't buffer scancodes
		without doing anything with them if I want to service keyboard commands.
		Maybe I can keep two buffers - one for controller and one for driver. Anything
		that is not command-related will be sent to driver to deal with. 
	*/


	/*
		Bug in some qemu versions: keyboard sends scancode even when it should
		process command .. what now ?
	*/

	// buffer the scancode in controller's buffer
	RING32_STORE("sbuf", &atkbdc.sbuf, scancode);

	// if command was handled there's nothing for driver
	if (kbdc_handle_command() == 0) {
		goto out;
	}
	RING32_RI_ADD(&atkbdc.sbuf); // mark as read

	// Scancode is not command related, it's a make/break code
	atkbd.lc = atkbd.kbuf.buf[atkbd.kbuf.fi-1];
	printk("store @ kbuf\n");
	RING32_STORE("kbuf", &atkbd.kbuf, scancode);
	printk("isr: lastchar: 0x%x\n", atkbd.lc);

	// we have everything buffered at this point, we could send EOI and let the driver deal with its thing
	// XXX: locking required !

	// kbd_handle_event();

	// numlock
	if (scancode == 0x45 ) {
		printk("isr: numlock trigger\n");
		struct kbdc_command* nc = RING32_PEEK_FI(&atkbdc.cmd_q);

		atkbd.ledstate ^= KBDE_LED_NUMLOCK;	// flip the state of numlock

		nc->cmd[0] = KBDE_CMD_SETLED;
		nc->cmd[1] = atkbd.ledstate;
		nc->flags = KFLAG_TWOBYTE_CMD|KFLAG_WAIT_ACK;
		nc->dst_port = PS2_ENCODER;
		nc->status = S_KCMD_READY;
		RING32_STORE("cmdq", &atkbdc.cmd_q, *nc);

		kbdc_handle_command();
	}
out:
	send_8259_EOI(1);
}

int kbdc_handle_command() {
	struct kbdc_command* kc = RING32_PEEK_RI(&atkbdc.cmd_q);
	unsigned char sc = RING32_FETCH("sbuf", &atkbdc.sbuf);

	// Do we have triggered command in queue ?
	if (kc->status == S_KCMD_TRIGGERED) {
		switch(sc) {
		case KBDE_CMD_RESPONSE_ACK:
			printk("triggered, got ack, now confirmed\n");
			kc->status = S_KCMD_CONFIRMED;
			atkbdc.cmd_in_progress = 1;
			break;

		case KBDE_CMD_RESPONSE_RESEND:
			kc->status = S_KCMD_READY;
			break;

		case KBDE_CMD_RESPONSE_ECHO:
			#ifdef DEBUG
			printk("response to echo command, we are done\n");
			#endif
			goto success;
			break;

		case 0:
			#ifdef DEBUG
			printk("Internal buffer overrun, abort command.\n");
			#endif
			goto fail;

		// command was triggered but we got unrecognizable output
		// leave for kbd driver, wait for another response
		default:
			#ifdef DEBUG
			printk("handle_command: triggered command 0x%x got response 0x%x\n", kc->cmd[0], sc);
			#endif
			RING32_RI_SUB(&atkbdc.sbuf);
			goto out;
		}
	}

	//if (!atkbdc.cmd_in_progress && kc->status != S_KCMD_READY) {
	if (!atkbdc.cmd_in_progress && !RING32_DATA_READY(&atkbdc.cmd_q)) {
		RING32_RI_SUB(&atkbdc.sbuf);	// not using sc
		goto out;
	}

	switch(kc->status) {
	case S_KCMD_READY:
		printk("S_KCMD_READY\n");
		RING32_RI_SUB(&atkbdc.sbuf);	// sc was not for us
		kc->response = kbde_poll_write(kc->cmd[0]);
		if (kc->response == -1) {
			if (kc->retries++ > KBD_RETRY_ATTEMPTS) {
				#ifdef DEBUG
				printk("command 0x%x failed\n", kc->cmd[0]);
				#endif
				goto fail;
			}
			printk("S_KCMD_READY: command failed: 0x%x, will retry\n", kc->cmd[0]);
			goto out;
		}
		printk("S_KCMD_READY: triggered\n");
		kc->status = S_KCMD_TRIGGERED;
		break;

	case S_KCMD_CONFIRMED:
		printk("S_KCMD_CONFIRMED\n");

		// handle two-byte command
		if (KCMD_IS_TWOBYTE(kc)) {
			printk("twobyte command: 0x%x\n", kc->cmd[1]);
			kc->response = kbde_poll_write(kc->cmd[1]);

			if (kc->response == -1) {
				if (kc->retries++ > KBD_RETRY_ATTEMPTS) {
					#ifdef DEBUG
					printk("command 0x%x failed\n", kc->cmd[1]);
					#endif
					goto fail;
				}
				printk("S_KCMD_CONFIRMED:: command failed: 0x%x, will retry\n", kc->cmd[1]);
				goto out;
			}

			// we are still awaiting ACK
			kc->flags &= ~(KFLAG_TWOBYTE_CMD);
			kc->status = S_KCMD_AWAITING_ACK;
			printk("2nd command result(0 expected): %x\n", kc->response);
			break;
		}

		// not a twobyte commnad, are we expecting response ?
		if (KCMD_AWAITING_DATA(kc)) {
			printk("S_KCMD_CONFIRMED: awaiting data\n");
			kc->status = S_KCMD_AWAITING_DATA;
			break;
		}

		// simple command with one ACK, we are done
		goto success;
		break;

	case S_KCMD_AWAITING_ACK:
		printk("S_KCMD_AWAITING_ACK\n");

		if (sc != KBDE_CMD_RESPONSE_ACK) {
			printk("S_KCMD_AWAITING_ACK: non-ACK response: 0x%x\n", sc);
			goto fail;
		}

		if (KCMD_AWAITING_DATA(kc)) {
			printk("S_KCMD_AWAITING_ACK: awaiting data\n");
			kc->status = S_KCMD_AWAITING_DATA;
			break;
		}

		printk("S_KCMD_AWAITING_ACK: we are done\n");

		// nothing more to process
		goto success;
		break;

	case S_KCMD_AWAITING_DATA:
		printk("S_KCMD_AWAITING_DATA\n");
		kc->response = sc;
		goto success;
		break;

	default:
		#ifdef DEBUG
		printk("handle_command: command 0x%x in unknown state: %d\n", kc->cmd[0], kc->status);
		#endif
		goto fail;
	}

	return 0;

success:
	kc->status = S_KCMD_DONE;
	atkbdc.cmd_in_progress = 0;
	RING32_RI_ADD(&atkbdc.cmd_q);
	return 0;

fail:
	kc->status = S_KCMD_FAILED;
	atkbdc.cmd_in_progress = 0;
	RING32_RI_ADD(&atkbdc.cmd_q);

out:
	return -1;
}

void ps2c_info() {
	int i;
	printk("%s: %d ports\n", atkbdc.devname, atkbdc.nports);

	for (i =0; i < 2; i++) {
		if (atkbdc.ports[i] != NULL ) {
			printk("kbd: port %d: %s: type: %d\n", i+1, atkbdc.ports[i]->devname, atkbdc.ports[i]->devtype);
		}
	}
}

// just to see what's happening
void dbg_kbd_dumpbuf() {
	int i;

	printk("sbuf: fi: %d, ri: %d\n", atkbdc.sbuf.fi, atkbdc.sbuf.ri);
	for (i =0; i < 32; i++) {
		printk("%x ", atkbdc.sbuf.buf[i]);
	}

	printk("\nkbuf: fi: %d, ri: %d\n", atkbd.kbuf.fi, atkbd.kbuf.ri);
	for (i =0; i < 32; i++) {
		printk("%x ", atkbd.kbuf.buf[i]);
	}
	printk("\n");
}
