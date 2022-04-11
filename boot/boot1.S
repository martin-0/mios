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

	leaw (msg), %si
	call puts16

	call detect_low_mem

	test %ax, %ax
	jz Lfatalerr

	/* print the memory */
	inc %ax
	push %ax
	leaw (msg_memlow), %si
	call printf16

	/* Attemp to enable the A20 gate */
	pushw $(printf)
	leaw (msg_debug6), %si
	call printf16

	call enable_A20
	test %ax, %ax
	jz prepm32

	leaw (fatal_a20), %si
	call printf16
	jmp Lfatalerr



prepm32:
	leaw (ok_a20), %si
	call printf16

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

	call do_dump

	cld
	movl $0xB8f00, %edi
	movl $(msg_hello_mi), %esi
	movb $0x02, %ah
.Ldummy_print:
	lodsb 
	test %al, %al
	jz .Ldummy_print_end
	stosw
	jmp .Ldummy_print

.Ldummy_print_end:	

	/* cursor update 
	xorl %eax, %eax
	movb $0xf, %al
	movw $0x3d4, %dx
	outw %ax, %dx
	movb $2, %al
	movw $0x3d5, %dx
	outb %al, %dx

	movb $0xe, %al
	movw $0x3d4, %dx
	outw %ax, %dx
	movb $0, %al
	movw $0x3d5, %dx
	outb %al, %dx
	*/

	nop
	ljmp $0x18, $(pm2rm)
pm2rm:

	movl $0x20, %eax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	movw %ax, %fs
	movw %ax, %bx

	movl %cr0, %eax
	dec %ax
	//andl 0xfffffffe, %eax
	movl %eax, %cr0
	xorl %eax, %eax

	
	ljmp $0, $(rm1)
	/* XXX: this is a way to go back to realmode .. i should stick to vm86 though */
rm1:
	.code16
	nop
	nop
	xorw %ax, %ax
	movw %ax, %es
	movw %ax, %ds
	movw %ax, %ss
	movw %ax, %fs
	movw $0x7bfc, %sp

rm16:
	sti

	leaw (msg_debug3), %si
	call puts16

	nop
	call show_cur_ip

	leaw (msg_debug4), %si
	call puts16

	movw $0x1000, %ax
	int $0x16

	leaw (msg_debug5), %si
	call puts16

keys:
	movw $0x1000, %ax
	int $0x16

	xor %bx, %bx
	movb $0x0e, %ah
	int $0x10

	cmpb $0x71, %al
	je off
	jmp keys

	jmp off

	/* NOTE:
	 *
	 *	Next: create and test interface for BIOS calls - the VM86 mode. 
	 */

Lfatalerr:
	leaw (fatal_error), %si
	call puts16

off:
	leaw (msg_end), %si
	call puts16
	cli
	hlt
	jmp off

/* temporary things i test */
show_cur_ip:
	push %bp
	movw %sp, %bp
	pushw 2(%bp)
	push %cs
	leaw (msg_debug1), %si
	call printf16	
	addw $4, %sp
	
	pop %bp
	ret

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

	bios_ivt:
		.word 0x3ff
		.word 0,0

	bootdrive:	.byte	0
	lowmem:		.word	0

	msg:	.asciz	"boot1\r\n"
	debug:	.asciz	"DBEUG"
	debug1:	.asciz	"debug1: %s\r\nhex tripplet: %x %x %x\r\npointer: %p\r\nunsigned val: %u\r\nsigned val: %d\r\nchars: %c %c %c\r\n"

	msg_memlow:	.asciz	"low memory: %uKB\r\n"

	fatal_error:	.asciz	"FATAL ERROR: system halted.\r\n"
	fatal_a20:	.asciz	"Failed to activate A20 gate, aborting.\r\n"
	ok_a20:		.asciz	"A20 gate enabled.\r\n"

	msg_hello_mi:	.asciz	"Hello from MIOS protected mode."

	msg_debug1:	.asciz	"current cs:ip: %x:%x\r\n"	
	msg_debug2:	.asciz	"gdt size: 0x%x\r\n"
	msg_debug3:	.asciz	"back to realmode\r\n"
	msg_debug4:	.asciz	"press any key to continue..\r\n"
	msg_debug5:	.asciz	"infinite loop..\r\n"

	msg_end:	.asciz	"\r\nEND.\r\n"

	dummy_str:	.asciz	"main: %p:%p\r\n"

	msg_debug6:	.asciz	"val: %p\r\n"
