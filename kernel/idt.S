/* martin */

// XXX: ss is not saved ! : need to fix this

.section .text
	.code32

.global	__irq_setframe_early
.func __irq_setframe_early
__irq_setframe_early:
	pushl $0				// IDT 0x20-0x2f will have entries to these, start at push instrucion
	jmp irq_dispatch
	pushl $1				// XXX:
	jmp irq_dispatch			// this works because pushl0/jmp to irq_dispatch is close enough for short jump
	pushl $2				// while there's no need for anything else here it is a problem for traps
	jmp irq_dispatch			// maybe I should use one generic approach here
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
	pushl (%esp)				/* irqnr;  paddding so trapframe and irqframe are the same */
	pushw	%gs
	pushw	%fs
	pushw	%es
	pushw	%ds
	pushal

	movl 0x2c(%esp), %esi			/* irq number */

	/* Our stack is now as follows:
		flags
		cs
		ip
		irqnr
		irqnr
		gs,fs,es,ds
		regs32
	*/
	movl %esp, %edi				/* edi: irqframe */

	leal irq_stats(,%esi,8), %ebx		/* update irq stats */
        addl $1, (%ebx)				/* 64b counters */
	adcl $0, 4(%ebx)

	movl %esi, %eax
	call mask_irq

	movl $(irq_handlers), %ebx		/* dispatch to proper irq handler */
	movl %edi, %eax				/* stackframe as an argument */
	call *(%ebx,%esi,4)			/* NOTE: handler sends EOI */

irq_cleanup:
	movl %esi, %eax
	call clear_irq

	popal
	popw %ds
	popw %es
	popw %fs
	popw %gs

	addl $8, %esp
	iret
.endfunc

/* handy macro to ease the setup */
.macro trap_set_frame_early n e
	.global trap_setframe_early\n
	trap_setframe_early\n:				/* trap_setframe_earlyN */

	.if \e == 0					/* if there's no error push 0 */
	pushl $0
	.else
		xchg %ax,%ax				/* 2-byte nop */
	.endif
	pushl $\n					/* push trapnr */

	pushl %eax					/* save eax */
	movl $(trap_dispatch), %eax
	//jmp trap_dispatch				/* continue with the trap handling */
	jmp *%eax

.endm

/*
	Is that 2-byte nop in trap_set_frame_early macro ideal? I don't know yet. For the time being I'd like to
	avoid creating separate table of pointers with the trap_setframe_earlyN that I'd use in init_idt() routine.
	This introduces indirect jump too. Maybe not ideal, but I'll stick with it for the time being.. I can always
	optimise. Each trap_set_frame_early stage is 12B apart.
*/
.global __trap_setframe_early
.func __trap_setframe_early
__trap_setframe_early:
	trap_set_frame_early 0,0
	trap_set_frame_early 1,0
	trap_set_frame_early 2,0
	trap_set_frame_early 3,0
	trap_set_frame_early 4,0
	trap_set_frame_early 5,0
	trap_set_frame_early 6,0
	trap_set_frame_early 7,0
	trap_set_frame_early 8,1
	trap_set_frame_early 9,0
	trap_set_frame_early 10,1
	trap_set_frame_early 11,1
	trap_set_frame_early 12,1
	trap_set_frame_early 13,1
	trap_set_frame_early 14,1
	trap_set_frame_early 15,0
	trap_set_frame_early 16,0
	trap_set_frame_early 17,1
	trap_set_frame_early 18,0
	trap_set_frame_early 19,0
	trap_set_frame_early 20,0
	trap_set_frame_early 21,1
	trap_set_frame_early 22,0
	trap_set_frame_early 23,0
	trap_set_frame_early 24,0
	trap_set_frame_early 25,0
	trap_set_frame_early 26,0
	trap_set_frame_early 27,0
	trap_set_frame_early 28,0
	trap_set_frame_early 29,1
	trap_set_frame_early 30,1
	trap_set_frame_early 31,0

.global trap_dispatch
trap_dispatch:
	popl %eax				// restore eax after jump
	pushw	%gs
	pushw	%fs
	pushw	%es
	pushw	%ds
	pushal

	/* Our stack is now as follows:
		flags
		cs
		ip
		errcode
		trapnr
		gs,fs,es,ds
		regs32
	*/

	movl %esp, %eax				// stack frame
	leal (trap_handlers), %ebx		// trap_handlers[]
        movl 0x28(%esp), %edx			// trapnr saved on stack
	call *(%ebx,%edx,4)

	// XXX: let's treat all traps 0-31 as fatal for now
	pushl $(debug_halted)
	call printk
	addl $4, %esp
	cli
	hlt

	popal
	popw %ds
	popw %es
	popw %fs
	popw %gs

	addl $8, %esp				/* error code and trapnr cleanup */
	iret
.endfunc

.global irq_handler_dflt			/* called by __irq_setframe_early */
.func irq_handler_dflt				/* NOTE: interrupts with this handler are masked */
irq_handler_dflt:
	pushl %eax
	movl $(debug_dflt_handler), %eax
	call puts

	popl %eax
	movl 0x2c(%eax), %eax
	call send_8259_EOI
	ret
.endfunc

.section .data
	debug_halted: 		.asciz "System debug_halted.\n"
	debug_dflt_handler:	.asciz	"default, unassigned IRQ handler called!\n"
