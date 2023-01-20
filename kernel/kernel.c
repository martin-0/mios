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
	uint8_t r,r2;
	uint32_t i =0;
	char buf[128];

	copy_kargs(__kargs);

	smap = (e820_map_t *)kargs.smap_ptr;
	load_gdt();

/*
	for (i =0; i < BDA_COM_PORTS; i++) {
		printk("com%d: 0x%x\n", i, kargs.com_ports[i]);
	}
*/
	printk("welcome to kernel_main\n");

	if ((uart_init(COM1_BASE, 9600)) != 0) {
		printk("failed to init com0 @ %x\n", COM1_BASE);
	} else {
		printk("serial console: 0x%x\n", com1_console);
	}


	i = 0;
	for (;; ) {
		printk("mios> ");

		// XXX: kbd still needs to translate scan codes
		read_string(buf, 32);
		printk("\n%d: >%s<\n", i,buf);
		printk("len: %d\n", strlen(buf));

		if ((strncmp(buf, "stat", 4)) == 0) {
			check_irq_stats();
			r = inb_p(COM1_BASE + UART_REG_MCR);
			r2 = inb_p(COM1_BASE + UART_REG_MSR);
			printk("0x%x: MCR: 0x%x, MSR: 0x%x\n", COM1_BASE, r, r2);
			goto mainloop;
		}

		if ((strncmp(buf, "irq", 3)) == 0) {
			debug_status_8259("main");
			goto mainloop;
		}

		if ((strncmp(buf, "kill", 3)) == 0) {
			asm volatile("int $0x80");
			goto mainloop;
		}

		if ((strncmp(buf, "nmi", 3)) == 0) {
			asm volatile("int $2");
		}

		if ((strncmp(buf, "map", 3)) == 0) {
			show_e820map();
			goto mainloop;
		}

		if ((strncmp(buf, "buf", 3)) == 0 ) {
			dbg_kbd_dumpbuf();
			goto mainloop;
		}

	mainloop:
		i++;
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
