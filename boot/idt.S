/* martin */

/* NOTE: using regparm=3, eax,edx,ecx are used to pass args to function */

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

	/* XXX: there still is a problem with interrupt that does push error code, it's up to
		this routine to clear this up. 
	
		One way of this would be to fake push 0 in irq_main_handler for those interrupts that don't push anything.
		I need to manually adjust offsets in pic.c:init_idt()

		This is also true for trap/exceptions. Different handler should be usd though..
	*/
		
	
        movl 0x20(%esp), %esi                   /* irq number saved on stack */
	leal irq_stats(,%esi,8), %ebx		/* update irq stats */
        addl $1, (%ebx)				/* 64b counters */
	adcl $0, 4(%ebx)

	movl %esi, %eax				/* regparm(3), eax: irq */
	call mask_irq

	leal (%esp), %eax			/* irqframe, stack: [ pusha | irq ] */

	movl $(irq_handlers), %ebx		/* dispatch to proper irq handler */
	call *(%ebx,%esi,4)			/* NOTE: handler sends EOI */

	movl %esi, %eax				/* regparm(3), eax: irq */
	call clear_irq

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

/* XXX: testing*/
.global nmi_trap
.func nmi_trap
nmi_trap:
	pushl $2
	pusha

	inb $0x61				/* try to get the reason of NMI from port B */
	movb %al, %dh

	inb $0x92				/* try to get the reason of NMI from port A */
	mov %al, %dl

	movl %esp, %eax
	call handle_nmi

	popa
	addl $4, %esp
	iret
.endfunc

