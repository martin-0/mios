/* martin */

	.set ADDR_STACKSTART,	0x1ff00

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

	/* argument passed to entry used to initialize smap entries in mm.c */
	movl (%esp), %eax
	movl %eax, (smap)

	movl $ADDR_STACKSTART, %esp

	call clrscr

	call init_idt				/* setup the tables */
	lidt (IDT)

	call init_8259				/* PIC and PIT */
	call init_pit

	call debug_install_irq1

	sti 					/* enable interrupts */

	call kernel_main
	jmp off					/* in case of I return from kernel_main */

off:
	cli
	hlt
	jmp off

