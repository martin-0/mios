/* martin */

/* XXX: Idea here is to load the kernel and let it do all the work.
	As I'm learning though I'm abusing the gboot to test other stuff too.
*/

#include <stdint.h>

#include "libsa.h"
#include "pic.h"

extern uint64_t ticks;

void gboot_main() {
	uint64_t old;
	//asm("cli;hlt");
	debug_status_8259("gboot_main");

	printf("welcome to gboot_main\n");

	//asm ("xorl %ecx, %ecx ; div %ecx");
	//asm ("int $3");

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
