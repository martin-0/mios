/* martin */

.section .text
	.code32

.global	irq_main_handler
.func irq_main_handler
irq_main_handler:
	pushl $0				// IDT 0x20-0x2f will have entries to these push entries
	jmp irq_dispatch
	pushl $1
	jmp irq_dispatch
	pushl $2
	jmp irq_dispatch
	pushl $3
	jmp irq_dispatch
	pushl $4
	jmp irq_dispatch
	pushl $5
	jmp irq_dispatch
	pushl $6
	jmp irq_dispatch
	pushl $7
	jmp irq_dispatch
	pushl $8
	jmp irq_dispatch
	pushl $9
	jmp irq_dispatch
	pushl $0xa
	jmp irq_dispatch
	pushl $0xb
	jmp irq_dispatch
	pushl $0xc
	jmp irq_dispatch
	pushl $0xd
	jmp irq_dispatch
	pushl $0xe
	jmp irq_dispatch
	pushl $0xf
	jmp irq_dispatch

.global irq_dispatch
irq_dispatch:
	pushal

	/* XXX: Are there any IRQs that push err code ? If so I need to modify it the same way as
		default traps are done.  */

	subl $4, %esp				/* cleanup will be done by popl %esi */

	leal 4(%esp), %edi			/* irqframe */
        movl 0x24(%esp), %esi                   /* irq number saved on stack */
	leal irq_stats(,%esi,8), %ebx		/* update irq stats */
        addl $1, (%ebx)				/* 64b counters */
	adcl $0, 4(%ebx)

	movl %esi, (%esp)
	call mask_irq

	movl $(irq_handlers), %ebx		/* dispatch to proper irq handler */
	movl %edi, (%esp)
	call *(%ebx,%esi,4)			/* NOTE: handler sends EOI */

	movl %esi, (%esp)
	call clear_irq
	popl %esi				/* stack cleanup */

	popal
	addl $4, %esp
	iret
.endfunc

/* handy macro to ease the setup */
.macro trap_set_stack n e
	.global start_trap\n
	start_trap\n:				/* start_trapN */

	.if \e == 0				/* if there's no error push 0 */
	pushl $0
	.endif
	pushl $\n				/* push trapno */
	jmp trap_dispatch			/* continue with the trap handling */

.endm

/* NOTE: using as temporary solution so that IDT is not empty */
.global trap_handler_dflt
.func trap_handler_dflt
trap_handler_dflt:
	trap_set_stack 0,0
	trap_set_stack 1,0
	trap_set_stack 2,0
	trap_set_stack 3,0
	trap_set_stack 4,0
	trap_set_stack 5,0
	trap_set_stack 6,0
	trap_set_stack 7,0
	trap_set_stack 8,1
	trap_set_stack 9,0
	trap_set_stack 10,1
	trap_set_stack 11,1
	trap_set_stack 12,1
	trap_set_stack 13,1
	trap_set_stack 14,1
	trap_set_stack 15,0
	trap_set_stack 16,0
	trap_set_stack 17,1
	trap_set_stack 18,0
	trap_set_stack 19,0
	trap_set_stack 20,0
	trap_set_stack 21,1
	trap_set_stack 22,0
	trap_set_stack 23,0
	trap_set_stack 24,0
	trap_set_stack 25,0
	trap_set_stack 26,0
	trap_set_stack 27,0
	trap_set_stack 28,0
	trap_set_stack 29,1
	trap_set_stack 30,1
	trap_set_stack 31,0

.global trap_dispatch
trap_dispatch:
	pushw	%gs
	pushw	%fs
	pushw	%es
	pushw	%ds
	pushal

	/* Our stack is now as follows:
		flags
		cs
		ip
		trapno				well, technically exception no, right ?
		errcode
		gs,fs,es,ds
		regs32
	*/


	pushl %esp				// trapframe
	leal (trap_handlers), %ebx		// trap_handlers[]
        movl 0x2c(%esp), %esi                   /* trapno saved on stack */
	call *(%ebx,%esi,4)
	popl %esi				/* stack cleanup */

	/* XXX: let's treat all traps 0-31 as fatal for now  */
	cli
	hlt

	popal
	popw %ds
	popw %es
	popw %fs
	popw %gs

	addl $8, %esp				/* error code and trapno cleanup */
	iret
.endfunc

.global irq_handler_dflt			/* called by irq_main_handler */
.func irq_handler_dflt				/* NOTE: no EOI sent but IRQs with this handler are masked */
irq_handler_dflt:
	xchg %eax, %eax
	ret
.endfunc

// Segment Not Present NP, with error code
.global int11_handler
.func int11_handler
int11_handler:
	cli
	pushl $11		// trapno
	pushw	%gs
	pushw	%fs
	pushw	%es
	pushw	%ds
	pushal

	pushl %esp
	call debug_dump_trapframe
	popl %eax

	addl $2, 0x30(%esp)			// XXX: dummy fix for int 0x11
	popal
	popw %ds
	popw %es
	popw %fs
	popw %gs
	addl $8, %esp
	sti
	iret
.endfunc


/* XXX: fake handler ; used with P-field set to 0 in IDT to test the int11 */
.global int80_handler
.func int80_handler
int80_handler:
	pushal
	pop %eax

	inc %ebx
	dec %ebx

	popal
	iret
.endfunc

.global trap_bad_dummy
.func trap_bad_dummy
trap_bad_dummy:
	nop
	nop
	inc %eax	// dummy
	dec %eax
	pop %eax
	iret
.endfunc

/* XXX: any exception handler that is not defined goes through this routine. this way i can see
	which trap/exception i hit */
.section .data
	.align 8
	.global trap_idt_entry

	trap_idt_entry:
			.long start_trap0, start_trap1, start_trap2, start_trap3, start_trap4, start_trap5, start_trap6, start_trap7, start_trap8, start_trap9, start_trap10, start_trap11
			.long start_trap12, start_trap13, start_trap14, start_trap15, start_trap16, start_trap17, start_trap18, start_trap19, start_trap20, start_trap21
			.long start_trap22, start_trap23, start_trap24, start_trap25, start_trap26, start_trap27, start_trap28, start_trap29, start_trap30, start_trap31
