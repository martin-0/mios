/* martin */

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


// NOTE: userspace selectors to be defined here ..
struct gdt_entry gdt_entries[] = {
	{ 0,0,0,0,0,0 },		// NULL
	{ 0xffff,0,0,0x9a, 0xcf, 0 },	// kernel cs
	{ 0xffff,0,0,0x92, 0xcf, 0 },	// kernel data
};

struct gdt GDT = {
	.g_size = sizeof(gdt_entries)-1,
	.g_start = (struct gdt_entry*)&gdt_entries
};


void kernel_main(struct kernel_args* kargs) {
	uint8_t key;
	uint32_t i =0;

	smap = (e820_map_t *)kargs->smap_ptr;

	load_gdt();

	if ((uart_init(0x3f8, 9600)) != 0) {
		printk("failed to init com0\n");
	}

	printk("welcome to kernel_main\n");

	debug_status_8259("main");

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
		case 0x17:      debug_status_8259("main");
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

		i++;
		asm("hlt");
		if ( i > 2048 ) {
			i= 0;
			check_irq_stats();
			debug_status_8259("main");
		}
	}

}

void load_gdt() {
	disable_interrupts();

	asm volatile(
		"lgdt %0\n"
		"ljmp $0x8, $1f ; 1:\n"
		"movl $0x10, %%eax\n"
		"movw %%ax, %%ss\n"
		"movw %%ax, %%ds\n"
		"movw %%ax, %%es\n"
		"movw %%ax, %%fs\n"
		"movw %%ax, %%gs\n" : : "m"(GDT) : "eax" );

	enable_interrupts();
}
