/* martin */

/* XXX: Idea here is to load the kernel and let it do all the work.
	As I'm learning though I'm abusing the gboot to test other stuff too.
*/

#include <stdint.h>
#include <stdarg.h>

#include "libsa.h"
#include "pic.h"
#include "mm.h"

extern uint64_t ticks;

void kernel_main() {
	printf("welcome to kernel_main\n");

	show_e820map();
	init_pm();
	uint64_t old;

//	asm ("int $0x14");

	old = ticks;
	for (;; ) {
		asm ("hlt");
		if ( (ticks % 4096 == 0) && ( old != ticks)) {
			check_irq_stats();
			debug_status_8259("main");
			old = ticks;
		}
	}

}
