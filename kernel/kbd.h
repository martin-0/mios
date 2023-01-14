#ifndef HAVE_KBD_H
#define	HAVE_KBD_H

#include <stdint.h>

#include "asm.h"

#define	SCAN1_LSHIFT		0x2a
#define	SCAN1_RSHIFT		0x36
#define	SCAN1_LCTRL		0x1d			// XXX: RCtrl is E0 1D, for our purposes _now_ it's ok
#define	SCAN1_LATLT		0x38			// XXX: LAlt is E0 38
#define	SCAN1_BACKSPACE		0x0e
#define	SCAN1_ESC		0x01
#define	SCAN1_ENTER		0x1c


/* identify keyboard by its ID */
struct kbd_devtype_name {
	uint16_t kbd_device_id;
	char* kbd_name;
};

/* let's try something simple first..*/
typedef struct kbd_state {
	struct kbd_devtype_name* devtype;
	struct kbd_map*	map;
	int kbd_active_scancode;			// XXX: do I need this?

	unsigned char shift_flags;
	unsigned char led_state;
	volatile int flags;

	#define	KBD_RBUF_MAX	256			// buffering up to 256 characters
	// XXX: we need to protect these with mutex
	volatile char kbuf[KBD_RBUF_MAX];
	volatile uint8_t c_idx;				// current idx
	volatile uint8_t r_idx;				// read idx
} kbd_state_t;

int __init_kbd_module();
void kbd_isr_handler(struct trapframe* f);

int kbde_write_command(uint8_t cmd);
int kbde_write_cmd_with_ack(uint8_t cmd);
int kbde_read_data();

int kbdc_write_command_2(uint8_t cmd, uint8_t nexbyte, int flags);


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
#define	KBDC_CONFBYTE_1ST_PS2_INTERRUPT		0x01		// bit0
#define	KBDC_CONFBYTE_2ND_PS2_INTERRUPT		0x02
#define	KBDC_CONFBYTE_1ST_PS2_PORT_DISABLED	0x10		// bit4: 1=disabled, 0=enabled
#define	KBDC_CONFBYTE_2ND_PS2_PORT_DISABLED	0x20		// bit5: 1=disabled, 0=enabled
#define	KBDC_CONFBYTE_1ST_PS2_TRANSLATION	0x40

// PS/2 commands
#define	KBDC_CMD_READ_COMMAND_BYTE		0x20
#define	KBDC_CMD_WRITE_COMMAND_BYTE		0x60
#define	KBDC_CMD_PS2_CTRL_TEST			0xaa
#define	KBDC_CMD_PS2_PORT1_TEST			0xab
#define	KBDC_CMD_READ_CTRL_OUTPUT		0xd0
#define	KBDC_CMD_RESPONSE_SELFTEST_OK		0x55

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
