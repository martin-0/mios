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

	xorl %eax, %eax
	movw %ax, (com1_console)		/* default off */

	call clrscr

	/* XXX: problem with this approach is we don't have IDT set yet. init_uart can't set serial vectors here
		maybe I should rename it to early_init or something
	*/

	movl 9600, %edx				/* speed when testing on actual HW */
	movw $0x3f8, %ax
	call early_uart_init
	testw %ax, %ax
	jnz 1f					/* if init failed com1_console stays 0 */
	movw $0x3f8, (com1_console)

1:

	// XXX: installs all handlers, sets to default (even irq0,1..)
	call init_idt				/* setup the tables */
	lidt (IDT)

	call init_8259				/* PIC and PIT */

	// NOTE: installs irq0 handler
	call init_pit

	// install keyboard driver
	call __init_kbd_module

	sti 					/* enable interrupts */

	call kernel_main
	jmp off					/* in case of I return from kernel_main */

off:
	cli
	hlt
	jmp off

