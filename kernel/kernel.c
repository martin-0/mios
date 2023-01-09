/* martin */

#include <stdint.h>
#include <stdarg.h>

#include "kernel.h"
#include "libk.h"
#include "pic.h"
#include "mm.h"
#include "kbd.h"
#include "uart.h"
#include "gshell.h"

extern uint64_t ticks;
extern e820_map_t* smap;		// XXX: this map is still below 1M

uint16_t com1_console;	// init in entry.S

struct kernel_args kargs;

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

void kernel_main(struct kernel_args* __kargs) {
	uint8_t r,r2,key;
	uint32_t i =0;
	char buf[128];

	copy_kargs(__kargs);

	smap = (e820_map_t *)kargs.smap_ptr;
	load_gdt();

	for (i =0; i < BDA_COM_PORTS; i++) {
		printk("com%d: 0x%x\n", i, kargs.com_ports[i]);
	}

	if ((uart_init(COM1_BASE, 9600)) != 0) {
		printk("failed to init com0 @ %x\n", COM1_BASE);
	}

	printk("welcome to kernel_main\n");

	i = 0;
	for (;; ) {
		printk("mios> ");

		// XXX: kbd still needs to translate scan codes
		read_string(buf, 32);

		printk(": %s\n", buf);

	/*
		key = getc();
		switch(key) {
		// A
		case 0x1e:
				poll_uart_write('A', COM1_BASE);
				break;
		// S
		case 0x73:
		case 0x1f:      check_irq_stats();
				r = inb_p(COM1_BASE + UART_REG_MCR);
				r2 = inb_p(COM1_BASE + UART_REG_MSR);

				printk("0x%x: MCR: 0x%x, MSR: 0x%x\n", COM1_BASE, r, r2);
				break;

		// I
		case 0x69:
		case 0x17:      debug_status_8259("main");
				break;

		// K
		case 0x6b:
		case 0x25:      asm("int $0x80");
				break;
		// N
		case 0x6e:
		case 0x31:      __asm__ ("int $2");
				break;

		// M
		case 0x6d:
		case 0x32:      show_e820map();
				break;

		}
		i++;
		asm("hlt");
		if ( i > 2048 ) {
			i=0;
			check_irq_stats();
			debug_status_8259("main");
		}
	*/
	}

}

// copy kernel args from bootloader into kernel ones
static void copy_kargs(struct kernel_args* k) {
	memcpy(&kargs, k, sizeof(*k));
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
