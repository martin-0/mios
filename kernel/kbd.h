#ifndef HAVE_KBD_H
#define	HAVE_KBD_H

#include <stdint.h>

#include "asm.h"
#include "device.h"

// XXX: this should be driver specific..
#define	SCAN1_LSHIFT		0x2a
#define	SCAN1_RSHIFT		0x36
#define	SCAN1_LCTRL		0x1d			// XXX: RCtrl is E0 1D, for our purposes _now_ it's ok
#define	SCAN1_LATLT		0x38			// XXX: LAlt is E0 38
#define	SCAN1_BACKSPACE		0x0e
#define	SCAN1_ESC		0x01
#define	SCAN1_ENTER		0x1c


#define	NAME_KBDC		"i8042c"
#define	MAX_COMMAND_QUEUE	32

typedef enum kbdc_port {
	PS2_PORT1 = 1,
	PS2_PORT2 = 2
} kbdc_port_e;

typedef struct kbdc_command {
	uint8_t cmd[2];
	int16_t response;
	uint8_t flags;
	kbdc_port_e dst_port;
} kbdc_command_t;

struct kbdc {
	char devname[DEVNAME_SIZE];
	uint8_t	nrports;
	uint8_t at_ctrl:1;					// AT compatible controller

	kbdc_command_t cmd_q[MAX_COMMAND_QUEUE];
	uint8_t qlen;

	device_t* p1;
	device_t* p2;
};


struct kbd {
	struct kbd_devtype_name {
		uint16_t kbd_device_id;
		char* kbd_name;
	} devtype;

	uint8_t special_keys;					// 1-shift, 2-ctrl, 3-alt
	uint8_t ledstate:3;
	int flags;

	#define	KBD_RBUF_MAX	128
	unsigned char kbuf[KBD_RBUF_MAX];
	uint8_t c_idx;
	uint8_t r_idx;
};

int __init_kbd_module();
void kbd_isr_handler(struct trapframe* f);

int kbde_poll_read();
int kbde_poll_write(uint8_t cmd);
int kbde_poll_write_a(uint8_t cmd);

int kbdc_poll_write(uint8_t cmd);
int kbdc_send_cmd(uint8_t cmd, uint8_t nexbyte, int flags);

// XXX: to be moved away
void psm_isr_handler(__attribute__((unused)) struct trapframe* f);

/* I/O port

http://www-ug.eecg.toronto.edu/msl/nios_devices/datasheets/PS2%20Keyboard%20Protocol.htm

	0x60	write	data sent directly to keyboard/aux device
	0x60	read	data from 8042
	0x64	write	8042 commands
	0x64	read	8042 satus register

	0x60	R/W	data port		encoder
	0x64	R	status register		controller
	0x64	W	command register	controller

encoder: i8048
controller: i8042

controller:
    A one-byte input buffer - contains byte read from keyboard; read-only		- read input buffer  0x60
    A one-byte output buffer - contains byte to-be-written to keyboard; write-only	- write output buffer 0x60
    A one-byte status register - 8 status flags; read-only				- read status reg 0x64
    A one-byte control register - 7 control flags; read/write 				- need to use cmd to do that

Note: while port 0x60 is used for direct communication with keyboard it still goes through controller.
	Encoder communicates back to this port as response to commnad but also sends make/brake codes.

*/

#define	KBDE_DATA_PORT				0x60
#define	KBDC_READ_STATUS_PORT			0x64
#define	KBDC_WRITE_COMMAND_PORT			0x64

#define	MASK_KBDC_STATUS_OUTBUF			0x1		// from ctrl to CPU
#define	MASK_KBDC_STATUS_INBUF			0x2		// from CPU to ctrl
#define	MASK_KBDC_SYSTEM_FLAG			0x4
#define	MASK_KBDC_COMMAND_DATA			0x8
#define	MASK_KBDC_LOCKED			0x10
#define	MASK_KBDC_AUX_BUF_FULL			0x20
#define	MASK_KBDC_TIMEOUT			0x40
#define	MASK_KBDC_PARITY_ERR			0x80

// PS/2 controller configuration byte
#define	KBDC_CONFBYTE_PS2_P1_INTERRUPT		0x01		// bit0
#define	KBDC_CONFBYTE_PS2_P2_INTERRUPT		0x02
#define	KBDC_CONFBYTE_SYSFLAG_BAT		0x04		// 1=BAT already done, 0=cold reboot
#define	KBDC_CONFBYTE_PS2_P1_DISABLED		0x10		// bit4: 1=disabled, 0=enabled
#define	KBDC_CONFBYTE_PS2_P2_DISABLED		0x20		// bit5: 1=disabled, 0=enabled
#define	KBDC_CONFBYTE_PS2_P1_TRANSLATION	0x40		// bit6: 1=enabled, 0=disabled

// PS/2 commands
#define	KBDC_CMD_READ_COMMAND_BYTE		0x20		// response:	ctrl conf byte
#define	KBDC_CMD_WRITE_COMMAND_BYTE		0x60		//		1st byte of internal RAM as standard, undefined

// These won't work on AT connector
#define KBDC_CMD_DISABLE_PS2_P2			0xa7		//		none
#define KBDC_CMD_ENABLE_PS2_P2			0xa8		//		none

#define	KBDC_CMD_PS2_P2_TEST			0xa9		//		0x00: ok, 1,2,3,4: lines stuck
#define	KBDC_CMD_PS2_CTRL_SELFTEST		0xaa		//		0x55: ok, 0xfc: failed
#define	KBDC_CMD_PS2_P1_TEST			0xab		//		0x00: ok, 1,2,3,4: lines stuck
#define	KBDC_CMD_DISABLE_PS2_P1			0xad		//		none
#define	KBDC_CMD_ENABLE_PS2_P1			0xae		//		none
#define	KBDC_CMD_READ_CTRL_OUTPUT		0xd0

#define	KBDC_CMD_RESPONSE_SELFTEST_OK		0x55
#define	KBDC_CMD_RESPONSE_SELFTEST_FAILED	0xfc

// kbdc_write_command_2() flags
#define	KBDC_ONEBYTE_CMD			0x0
#define	KBDC_TWOBYTE_CMD			0x1
#define	KBDC_NORESPONSE				0x0
#define	KBDC_RESPONSE_EXPECTED			0x2

// encoder commands
#define	KBDE_CMD_IDENTIFY			0xf2
#define	KBDE_CMD_ENABLE				0xf4
#define	KBDE_CMD_DISABLE			0xf5
#define	KBDE_CMD_RESPONSE_BAT_OK		0xaa
#define	KBDE_CMD_RESPONSE_ECHO			0xee
#define	KBDE_CMD_RESPONSE_ACK			0xfa
#define	KBDE_CMD_RESPONSE_BAT_ERR		0xfc
#define	KBDE_CMD_RESPONSE_RESEND		0xfe


#endif /* ifndef HAVE_KBD_H */
