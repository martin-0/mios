#ifndef HAVE_KERNEL_H
#define	HAVE_KERNEL_H

#include <stdint.h>

// information coming from bootloader
struct boot_partition {
	uint64_t lba_start;
	uint64_t lba_end;
	uint64_t sectors;
	uint16_t bootdrive;
	uint16_t sector_size;
} __attribute__((packed));

struct kernel_args {
	uint32_t* smap_ptr;
	struct boot_part* bootp;
	uint16_t comconsole;
} __attribute__((packed));

#endif /* ifndef HAVE_KERNEL_H */
