
.section .text
	.code32

.global	irq_main_handler			// XXX: verify but cli-sti are done automatically for interrupt gate
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

	/* XXX
	  	Should I care about the error code here? Not all IRQs produce the error code .. 
	
		What about IMR ? Maybe I should mask the interrupt in IMR, send EOI and let the
		IRQ handler do the rest ?  
	*/
	
        movl 0x20(%esp), %eax                   /* keep irq stats */
	leal irq_stats(,%eax,8), %ebx
        addl $1, (%ebx)				/* 64b counters */
	adcl $0, 4(%ebx)

	movl $(irq_handlers), %ebx		/* dispatch to proper irq handler */
	call *(%ebx,%eax,4)

	pushl 0x20(%esp)
	call send_8259_EOI

	addl $4, %esp				/* revert back the stack */
	popal
	addl $4, %esp
	iret
.endfunc


.global trap_handler_dflt			/* just so we don't have empty IDT */
.func trap_handler_dflt
trap_handler_dflt:
	nop
	iret
.endfunc

.global irq_handler_dflt			/* IRQ handler goes through irq_main_handler */
.func irq_handler_dflt
irq_handler_dflt:
	xchg %eax, %eax
	ret
.endfunc
