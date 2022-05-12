/* martin */

	.set BUFADDR, 0x3000
	.set STACK_OFFST, 0x4ffc

.section .text
	.code16
	.global _start

.macro set_minidap n, buf, s_low, s_high
	leaw (mini_dap), %bx
	movw $\n, (%bx)
	movw $\buf, 2(%bx)
	movl $\s_low, 4(%bx)
	movl $\s_high, 8(%bx) 
.endm

.macro dbg_show_addr addr
	pushw $\addr
	pushw $(func_debug1)
	call printf16
	addw $4, %sp
.endm

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
	movw %ax, %ss
	movw $STACK_OFFST, %sp

	movw %dx, (bootdrive)			/* save bootdrive */

	pushw $(msg_boot1)
	call puts16
	popw %ax				/* stack cleanup */

	/* Attemp to enable the A20 gate */
	call enable_A20
	test %ax, %ax
	jz .Ldisk_ss

	pushw $(fatal_a20)			/* fatal error if we can't have A20 */
	call printf16
	jmp panic16

.Ldisk_ss:

	/* get the disk sector size */
	pushw $1
	pushw (bootdrive)
	pushw $BUFADDR
	call disk_sector_size			/* int16_t disk_sector_size(char* buf, int16_t disk, char eddver) */
	test %ax,%ax
	jnz .Lread_gpt_hdr

	call print_err				/* print the error and panic */
	jmp panic16

.Lread_gpt_hdr:
	addw $6, %sp				/* cleanup after disk_sector_size() */
	movw %ax, (sectorsize)			/* store for later */

	set_minidap 1, BUFADDR, 1, 0		/* read LBA1, GPT header */
	call do_read

	/* TODO */ 
	cli
	hlt

	pushw $(smap)				/* detect memory with E820 */
	call getmem_E820
	test %ax, %ax
	jnz panic16

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
	movw %ax, %fs
	movw %ax, %gs
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

	.code16

off:
	cli
	hlt
	jmp off


/* wrapper to check the read. any failure means fatal error */
.func do_read
do_read:
	push %bx
	leaw (mini_dap), %bx

	pushw (%bx)
	pushl 8(%bx)
	pushl 4(%bx)
	pushw 2(%bx)
	pushw (bootdrive)
	call read16

	test %ax,%ax
	jz .Lend_do_read

	pushw (errno16)
	pushw $(fatal_read)
	call printf16

	jmp panic16

.Lend_do_read:
	addw $14, %sp
	pop %bx	
	ret	
.endfunc

/* print the error message along with the errno16 code */
.func print_err
print_err:
	xor %ax,%ax
	movb (errno16), %al
	push %ax
	pushw $(errno_msg)
	call printf16
	addw $4, %sp
	ret
.endfunc

/* panic function for 16b */
.func panic16
panic16:
	cli
	call dump_regs
	pushw $(fatal_error)
	call puts16
.Lpanic_loop:
	hlt
	jmp .Lpanic_loop
	ret					/* never returns */
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
		.byte 0x92		/* access: RTL: present, ring0, data segment, non-exec, grows up, rw, accessed=0 */
		.byte 0xf		/* RTL: flags-limit 16-19: , flags: 16b protected mode segment, byte granularity */
		.byte 0			/* base 24-31 */


		/* XXX: TSS segment should be defined ; I need to think of memory layout though, base should be the designated mem, limit
		 	is sizeof(tss), at least that's what i think
		*/
	end_gdt:

	bootdrive:	.word	0
	sectorsize:	.word	0

	.align 4
		gpt_hdr_signature:      .quad 0x5452415020494645

	/* this structure is passed to do_read() wrapper that calls read16 */
        mini_dap:
                .word 0			/* blocks to read */
                .word 0			/* offset part of the read buffer */
                .quad 0			/* LBA */	
		

	msg_boot1:	.asciz	">MIOS boot1\r\n"
	fatal_error:	.asciz	"FATAL ERROR: system halted.\r\n"
	fatal_a20:	.asciz	"Failed to activate A20 gate, aborting.\r\n"
	fatal_read:	.asciz	"disk read failed with error 0x%x\r\n"

	errno_msg:	.asciz	"BIOS function failed, error code: %x\r\n"	

	func_debug1:		.asciz	"address: %p\r\n"
	debug2_secsize:		.asciz	"sector size: %x\r\n"
