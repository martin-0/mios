/* martin */

/* XXX: Idea here is to load the kernel and let it do all the work.
	As I'm learning though I'm abusing the gboot to test other stuff too.
*/

#include <stdint.h>
#include <stdarg.h>

#include "libsa.h"
#include "pic.h"
#include "mm.h"
#include "kbd.h"
#include "uart.h"

extern uint64_t ticks;

uint16_t com1_console;

void kernel_main() {
	uint32_t i =0;
	com1_console = 0;	// default

	if ( (init_uart(COM1_BASE)) == 0 )
		com1_console = COM1_BASE;

	printk("welcome to kernel_main\n");

	uint8_t key;
	for (;; ) {
	/*
		key = getc(); // blocking on halt here!
		//printk("main: key: %x\n", key);
		// test
		switch(key) {
		// S
		case 0x1f:      check_irq_stats();
				break;

		// I
		case 0x17:      debug_status_8259("irq1_handler");
				break;

		// K
		case 0x25:      asm("int $0x80");
				break;
		// N
		case 0x31:      __asm__ ("int $2");
				break;

		// M
		case 0x32:      show_e820map();
				break;

		}
	*/
		i++;
		asm("hlt");
		if ( i > 512 ) {
			i= 0;
			check_irq_stats();
		}
	}

}
