#ifndef HAVE_KBD_H
#define	HAVE_KBD_H

#include <stdint.h>

#include "asm.h"
#include "device.h"
#include "types.h"

#define	KBDC_NAME		"kbdc"
#define	KBDC_INTERNAL_BUFSIZE	16

/* to define list of known keyboards and its ids */
struct kbd_devtype_name {
	uint16_t kbd_device_id;
	char* kbd_name;
};

struct kbdc_command {
	uint8_t cmd[2];				// LSB order
	uint8_t active_cmd_idx:1;		// active command
	int16_t response;			// last command response
	uint8_t flags;				// expect response
	int8_t retries;				// current retries
	enum e_kbd_cmd_status {
		S_KCMD_INQUEUE = 0,		// in queue to be picked up by command queue handler
		S_KCMD_AWAITING_ACK,		// command sent, ACK is expected
		S_KCMD_AWAITING_DATA,		// waiting for data from command
		S_KCMD_DONE,
		S_KCMD_FAILED,
		S_KCMD_RETRYING,
	} status;
	enum e_kbdc_port {
		PS2_CONTROLELR = 0,
		PS2_PORT1,
		PS2_PORT2,
		PS2_ENCODER
	} dst_port;
};


struct kbdc {
	char devname[DEVNAME_SIZE];
	uint8_t	nports;
	unsigned int at_ctrl:1;					// AT compatible controller
	int8_t cmd_in_progress;
	device_t* ports[2];

	DEFINE_RING32(cmd_q, struct kbdc_command);		// command queue
	DEFINE_RING32(cmd_rep, unsigned char);			// NOTE: for debugging purposes
};

struct kbd {
	uint16_t kbd_device_id;
	uint8_t special_keys;					// 1-shift, 2-ctrl, 3-alt
	uint8_t ledstate:3;					// numlock, capslock, screnlock
	int flags;						// XXX: translated scancodes; ? something else? separate vars ?
	unsigned char lc;

	DEFINE_RING32(kbuf, unsigned char);
};

int __init_kbd_module();
void kbd_isr_handler(struct trapframe* f);


#define	SENDCMD_NORESPONSE			0x0
#define	SENDCMD_RESPONSE_EXPECTED		0x1
#define	SENDCMD_TWOBYTE				0x2

int kbde_poll_read();
int kbde_poll_write(uint8_t cmd);
int kbde_poll_write_a(uint8_t cmd);

int kbdc_poll_write(uint8_t cmd);
int kbdc_send_cmd(uint8_t cmd, uint8_t nexbyte, int flags);
int kbdc_handle_command();

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

#define	KBD_RETRY_ATTEMPTS			3

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

// PS/2 controller commands
#define	KBDC_CMD_READ_COMMAND_BYTE		0x20		// response:	ctrl conf byte
#define	KBDC_CMD_WRITE_COMMAND_BYTE		0x60		//		1st byte of internal RAM as standard, undefined
#define KBDC_CMD_DISABLE_PS2_P2			0xa7		//		none
#define KBDC_CMD_ENABLE_PS2_P2			0xa8		//		none
#define	KBDC_CMD_PS2_P2_TEST			0xa9		//		0x00: ok, 1,2,3,4: lines stuck
#define	KBDC_CMD_PS2_CTRL_SELFTEST		0xaa		//		0x55: ok, 0xfc: failed
#define	KBDC_CMD_PS2_P1_TEST			0xab		//		0x00: ok, 1,2,3,4: lines stuck
#define	KBDC_CMD_DISABLE_PS2_P1			0xad		//		none
#define	KBDC_CMD_ENABLE_PS2_P1			0xae		//		none
#define	KBDC_CMD_READ_CTRL_OUTPUT		0xd0

#define	KBDC_CMD_RESPONSE_PORTTEST_OK		0x00
#define	KBDC_CMD_RESPONSE_SELFTEST_OK		0x55
#define	KBDC_CMD_RESPONSE_SELFTEST_FAILED	0xfc

#define	KFLAG_WAIT_ACK				0x1		// command to be ACKed by controller
#define	KFLAG_WAIT_DATA				0x2		// controller should send data
#define	KFLAG_TWOBYTE_CMD			0x4

#define	KCMD_AWAITING_ACK(cmd)			(cmd->flags & KFLAG_WAIT_ACK)
#define	KCMD_AWAITING_DATA(cmd)			(cmd->flags & KFLAG_WAIT_DATA)
#define	KCMD_IS_TWOBYTE(cmd)			(cmd->flags & KFLAG_TWOBYTE_CMD)

// encoder commands
#define	KBDE_CMD_IDENTIFY			0xf2
#define	KBDE_CMD_ENABLE				0xf4
#define	KBDE_CMD_DISABLE			0xf5
#define	KBDE_CMD_RESPONSE_BAT_OK		0xaa
#define	KBDE_CMD_SETLED				0xed
#define	KBDE_CMD_ECHO				0xee
#define	KBDE_CMD_RESPONSE_ECHO			0xee
#define	KBDE_CMD_RESPONSE_ACK			0xfa
#define	KBDE_CMD_RESPONSE_BAT_ERR		0xfc
#define	KBDE_CMD_RESPONSE_RESEND		0xfe
#define	KBDE_CMD_RESET				0xff

#define	KBDE_LED_SCROLLLOCK			0x1
#define	KBDE_LED_NUMLOCK			0x2
#define	KBDE_LED_CAPSLOCK			0x4

// debug
void dbg_kbd_dumpbuf();

#endif /* ifndef HAVE_KBD_H */
