/* martin */

.section .text
	.code32

.global _kernel_entry
_kernel_entry:

	/* XXX: WIP: right now this is just a split from boot1.S, I've not worked on this yet. */

	/* prepare to jump to protected mode */
	cli
	lgdt (gdt_desc)

	movl %cr0, %eax				/* enable protected mode */
	orl $1, %eax
	movl %eax, %cr0

//	ljmpl $8, $(pmode32)			/* flush instruction cache and set the proper cs selector */

pmode32:	
	movl $0x10, %eax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	movw %ax, %fs
	movw %ax, %gs

	// XXX: now needs to be set elsewhere
	movl $0x7bfc, %esp			/* stack below the bootcode */

	call clrscr

	call init_idt				/* setup the tables */
	lidt (IDT)

	call init_8259				/* PIC and PIT */
	call init_pit

	call debug_install_irq1

	sti 					/* enable interrupts */

	call gboot_main
	jmp off					/* in case of I return from gboot_main */

off:
	cli
	hlt
	jmp off

.section .data
	/* GDT table definiion */
	.align 16
	gdt_desc:	.word end_gdt-gdt-1			/* size */
			.long gdt				/* linear address, ptr to gdt */
	.align 16
	gdt:
		/* base:	32b value, linear address where the segment begins
		 * limit:	20b value, maximum addressable unit, either 1B units or 4k pages 
		 * access:	description of segment: P | DPL  | S | E | DC | RW | A
		 * flags:	granularity, db (size flag, 1B or 4k pages), long mode flag, reserved (0)
		 */
		.space	8		/* NULL desc */

		/* %cs in kernel mode */
		.word 0xffff		/* limit bits 0-15 */
		.word 0			/* base 0-15 */
		.byte 0x0		/* base 16-23 */
		.byte 0x9a		/* access: RTL: present, ring0, code segment, executable, grows up, rx, accessed=0 */
		.byte 0xcf		/* RTL: flags-limit 16-19: , flags: 32b protected mode segment, page granularity */
		.byte 0			/* base 24-31 */

		/* data in kernel mode */
		.word 0xffff		/* limit bits 0-15 */
		.word 0			/* base 0-15 */
		.byte 0x0		/* base 16-23 */
		.byte 0x92		/* access: RTL: present, ring0, data segment, non-exec, grows up, rw, accessed=0 */
		.byte 0xcf		/* RTL: flags-limit 16-19: , flags: 32b protected mode segment, page granularity */
		.byte 0			/* base 24-31 */

		/* %cs in real mode */	
		.word 0xffff		/* limit bits 0-15 */
		.word 0			/* base 0-15 */
		.byte 0x0		/* base 16-23 */
		.byte 0x9a		/* access: RTL: present, ring0, code segment, executable, grows up, rx, accessed=0 */
		.byte 0xf		/* RTL: flags-limit 16-19: , flags: 16b protected mode segment, byte granularity */
		.byte 0			/* base 24-31 */

		/* data in real mode */
		.word 0xffff		/* limit bits 0-15 */
		.word 0			/* base 0-15 */
		.byte 0x0		/* base 16-23 */
		.byte 0x92		/* access: RTL: present, ring0, data segment, non-exec, grows up, rw, accessed=0 */
		.byte 0xf		/* RTL: flags-limit 16-19: , flags: 16b protected mode segment, byte granularity */
		.byte 0			/* base 24-31 */


		/* XXX: TSS segment should be defined ; I need to think of memory layout though, base should be the designated mem, limit
		 	is sizeof(tss), at least that's what i think
		*/
	end_gdt:

	.global smap
	smap:	.long	0		// XXX: WIP: just so I can compile it
					// I need to either pass the proper structures via multiboot or have some custom arg passing

