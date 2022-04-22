#include <stdint.h>

#include "libsa.h"
#include "pic.h"

extern uint64_t ticks;

void gboot_main() {
	uint32_t i;
	printf("welcome to gboot_main\n");

	for (;; ) {
		asm ("hlt");
		if (ticks % 256 == 0) 
			check_irq_stats();
	}

}
