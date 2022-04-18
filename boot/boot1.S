/* martin */

.section .text
	.code16
	.global _start

_start:
	jmp 1f

	.asciz "MIOS"

	.= _start + 0x3e			/* offset to bootcode after BPB */
1:
	/* setup the segment registers */
	xorw %ax, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %fs
	movw %ax, %gs

	movb %dl, (bootdrive)
	leaw (msg_boot1), %si
	call puts16


	/* Attemp to enable the A20 gate */
	call enable_A20
	test %ax, %ax
	jz prepm32

	leaw (fatal_a20), %si			/* fatal error if we can't have A20 */
	call printf16
	jmp Lfatalerr

prepm32:
	pushw $(smap)				/* detect memory with E820 */
	call getmem_E820
	test %ax, %ax
	jnz Lfatalerr

	/* prepare to jump to protected mode */
	cli
	lgdt (gdt_desc)

	movl %cr0, %eax				/* enable protected mode */
	orl $1, %eax
	movl %eax, %cr0

	ljmp $8, $(pmode32)			/* flush instruction cache and set the proper cs selector */

	.code32
pmode32:	
	movl $0x10, %eax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	movl $0x7bfc, %esp			/* stack below the bootcode */

	call set_idt
	call install_dummyies	
	lidt (idt_desc)

	call init_8259
	call init_pit

	call parse_memmap

	sti

	int $1
	
foo:
	/*
	pushl (ticks)
	pushl $(strticks)
	call printf
	addl $8, %esp
	*/

	hlt
	jmp foo

Lfatalerr:
	leaw (fatal_error), %si
	call puts16

off:
	cli
	hlt
	jmp off


.global set_idt
.func set_idt
set_idt:
	pushl %esi
	pushl %ebx

	movl $(idt), %ebx				/* start of the IDT */
	leal (dummy_isr_handler), %edx			/* install the dummy ISR handler */
	movl %edx, %eax					/* base HI into eax */
	shr $16, %eax
	xor %ecx, %ecx
	dec %cl						/* 255 entries */
.Lset_default:

	movw %dx, (%ebx)				/* base LO */
	movw $8, 2(%ebx)				/* CS selector 0x8 */
	//movw $0x8e00, 4(%ebx)				/* interrupt, 32bit */
	movw $0x8f00, 4(%ebx)				/* trap, 32bit */
	movw %ax, 6(%ebx)				/* base HI  */
	
	addl $8, %ebx
	loop .Lset_default

	movl $(idt), %ebx				/* start of the IDT */
	movb $16, %cl

	leal (dummy_irq_handler), %edx			/* install the dummy IRQ handler */
	movl %edx, %eax					/* base HI into eax */
	shr $16, %eax

	/* start from 0x20 */
.Lset_irq_default:
	movw %dx, 0x100(%ebx)				/* base LO */
	movw $8, 0x102(%ebx)				/* CS selector 0x8 */
	movw $0x8e00, 0x104(%ebx)			/* interrupt, 32bit */
	movw %ax, 0x106(%ebx)				/* base HI  */
	
	addl $8, %ebx
	loop .Lset_irq_default

	popl %ebx	
	popl %esi	
	ret	
.endfunc

/* install handler */
.global install_handler

.global int20_dummy
.func int20_dummy
int20_dummy:
	incl (ticks)

	/* EOI */
	mov $0x20, %al
	out %al, $0x20
	iret
.endfunc

.global int21_dummy
.func int21_dummy
int21_dummy:
	nop
	nop
	movl $(int21), %eax
	push %eax
	call printf
	pop %eax

	inb $0x60			/* need to read data from kbd or next irq may not work */

	/* EOI */
	mov $0x20, %al
	out %al, $0x20

	nop
	iret
.endfunc

/* IRQ handler that does nothing */
.global dummy_irq_handler
.func dummy_irq_handler
dummy_irq_handler:
	push %eax

	mov $0x20, %al			/* EOI */
	out %al, $0x20
	pop %eax
	iret
.endfunc

/* ISR handler that does nothing */
.global dummy_isr_handler
.func dummy_isr_handler
dummy_isr_handler:
	iret
.endfunc


.section .data

	/* GDT table definiion */
	.align 16
	gdt_desc:	.word	end_gdt-gdt-1			/* size */
			.word	gdt,0				/* linear address, ptr to gdt */
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
		.byte 0x92		/* access: RTL: present, ring0, data segment, non-exec, grows up, rx, accessed=0 */
		.byte 0xf		/* RTL: flags-limit 16-19: , flags: 16b protected mode segment, byte granularity */
		.byte 0			/* base 24-31 */


		/* XXX: TSS segment should be defined ; I need to think of memory layout though, base should be the designated mem, limit
		 	is sizeof(tss), at least that's what i think
		*/
	end_gdt:

	/*
	struct InterruptDescriptor32 {
	   uint16_t offset_1;        // offset bits 0..15
	   uint16_t selector;        // a code segment selector in GDT or LDT
	   uint8_t  zero;            // unused, set to 0
	   uint8_t  type_attributes; // gate type, dpl, and p fields
	   uint16_t offset_2;        // offset bits 16..31
	};
		.word dummy_ir
		.word 0x8
		.byte 0, 0x8e
		.word 0
	*/

	idt_desc:
		.word end_idt-idt-1
		.word idt,0

	.global idt
	idt:
		.fill 256, 8, 0
	end_idt:

	ticks:		.quad	0

	bootdrive:	.byte	0

	/* ascii messages */
	msg_boot1:	.asciz	"MIOS boot1\r\n"

	fatal_error:	.asciz	"FATAL ERROR: system halted.\r\n"
	fatal_a20:	.asciz	"Failed to activate A20 gate, aborting.\r\n"

	int21:		.asciz "kbd event\n"
	strticks:	.asciz "ticks: %d\r"

	s_addr:		.asciz "addr: %p\n"
	err_unhandled:	.asciz	"unhandled interrupt.\n"
