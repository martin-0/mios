/* martin */

/* XXX: Idea here is to load the kernel and let it do all the work.
	As I'm learning though I'm abusing the gboot to test other stuff too.
*/

#include <stdint.h>
#include <stdarg.h>

#include "kernel.h"
#include "libsa.h"
#include "pic.h"
#include "mm.h"
#include "kbd.h"
#include "uart.h"

extern uint64_t ticks;
extern e820_map_t* smap;

uint16_t com1_console;	// init in entry.S

void kernel_main(struct kernel_args* kargs) {
	uint8_t key;
	uint32_t i =0;

	smap = (e820_map_t *)kargs->smap_ptr;

	printk("welcome to kernel_main\n");
	printk("console: 0x%x\n", com1_console);

	for (;; ) {
		key = getc();
		//printk("main: key: %x\n", key);
		// test
		switch(key) {
		// A
		case 0x1e:
				poll_uart_write('A', COM1_BASE);
				break;
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

	/*
		i++;
		asm("hlt");
		if ( i > 512 ) {
			i= 0;
			check_irq_stats();
		}
	*/
	}

}
