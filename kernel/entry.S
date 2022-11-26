/* martin */


/* MAKE SURE all assembly code is obeying regparam! I chose that but didn't fix the code 6 months ago */



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

	// XXX: installes all handlers, sets to default (even irq0,1..)
	call init_idt				/* setup the tables */
	lidt (IDT)

	call init_8259				/* PIC and PIT */

	// NOTE: installed irq0 handler
	call init_pit

	call debug_install_irq1

	sti 					/* enable interrupts */

	call kernel_main
	jmp off					/* in case of I return from kernel_main */

off:
	cli
	hlt
	jmp off

