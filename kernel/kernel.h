#ifndef HAVE_KERNEL_H
#define	HAVE_KERNEL_H

#include <stdint.h>

#define	BDA_COM_PORTS		4			// BDA: 40:00h - 40:08h

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
	uint16_t com_ports[BDA_COM_PORTS];
} __attribute__((packed));


// GDT table
struct gdt_entry {
	uint16_t	ge_limit_low;
	uint16_t	ge_base_low;
	uint8_t		ge_base_mid;
	uint8_t		ge_access;
	uint8_t		ge_rtl;
	uint8_t		ge_base_hi;
} __attribute__((packed)) __attribute__((aligned (4)));

struct gdt {
	uint16_t g_size;
	struct gdt_entry* g_start;
} __attribute__((packed));

static void load_gdt();
static void copy_kargs(struct kernel_args* k);

#endif /* ifndef HAVE_KERNEL_H */
