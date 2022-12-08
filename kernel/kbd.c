#include "kbd.h"
#include "asm.h"
#include "pic.h"
#include "libsa.h"

extern void show_e820map();

/* installs the kbd handler and enable irq1 */
void __init_kbd_module() {
	set_interrupt_handler(kbd_handler, 1);
	clear_irq(1);
}

void kbd_handler(struct trapframe* f) {

        uint8_t scancode = inb(0x60);
        printk("kbd_handler: frame: %p, scan code: %x\n", f, scancode);

        // XXX: debugging ; this really should not be part of the irq1 handler
        switch(scancode) {
        // S
        case 0x1f:      check_irq_stats();
                        break;

        // I
        case 0x17:      debug_status_8259("irq1_handler");
                        break;

        // D
        case 0x20:
                        debug_irq_frame(f);
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

	send_8259_EOI(1);
}
