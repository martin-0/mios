/* martin */

.section .text
	.code32

.global _kernel_entry
_kernel_entry:
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
	.global smap
	smap:   .long   0               // XXX: WIP: just so I can compile it
