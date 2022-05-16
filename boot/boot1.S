/* martin */
	.set BUFADDR, 0x3000
	.set BUFSZ, 0x1000			/* how many bytes I've allocated to a buffer */
	.set STACK_OFFST, 0x4ffc

.section .text
	.code16
	.global _start

/* macro to print func/var addr */
.macro dbg_show_addr addr
	pushw $\addr
	pushw $(func_debug1)
	call printf16
	addw $8, %sp
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
	movw %ax, %ss				/* while stack was set in pmbr it's better to do it just in case */
	movw $STACK_OFFST, %sp

	movw %dx, (bootdrive)			/* save bootdrive */

	movw $(msg_boot1), %ax
	call puts16

	/* Attempt to enable the A20 gate */
	call enable_A20
	test %ax, %ax
	jz .Lgetmem

	pushw $(fatal_a20)			/* fatal error if we can't have A20 */
	call printf16
	jmp panic16

	/* Get the system memory map from BIOS */
.Lgetmem:
	// XXX: I should have more ways of detecting memory, starts with E820 and go down
	//	to older stuff
	movw $(smap), %ax			/* detect memory with E820 */
	call getmem_E820
	test %ax, %ax
	jz .Ldisk_ssize

	movw $(msg_mem_err), %ax
	call puts16
	jmp panic16

.Ldisk_ssize:
	/* get the disk sector size */
	movw $1, %cx
	movw (bootdrive), %dx
	movw $BUFADDR, %ax
	call disk_sector_size			/* disk_sector_size(char* buf, int16_t disk, char eddver) */
	test %ax,%ax
	jnz .Lssize_check2

	call print_err				/* print the error and panic */
	jmp panic16

.Lssize_check2:
	cmpw $BUFSZ, %ax
	jbe .Lread_gpthdr

	pushw %ax
	pushw $BUFSZ
	pushw $(fatal_bufsz)			/* buffer too small, panic */
	call printf16
	jmp panic16

.Lread_gpthdr:
	/* read the GPT header */
	movw %ax, (sector_size)			/* store for later */

	xorl %ebx, %ebx
	movl %ebx, (dap_start+4)		/* set upper 32b to 0 in start LBA */
	inc %bx
	movl %ebx, (dap_start)			/* set lower 32b to 1 */
	movw %bx, (dap_blocks)			/* reading one LBA */
	movw $BUFADDR,(dap_buf)			/* into BUFADDR */
	call do_read				/* do_read() */

        /* verify GPT signature */
	movw $8, %cx
	movw $(gpt_hdr_signature), %dx
	movw $BUFADDR, %ax
	call memcmp16				/* memcmp16(BUFADDR, gpt_hdr_signature, 8) */

	test %ax,%ax
        jz .Lread_part

	movw $(fatal_gpt_sig),%ax		/* panic if GPT header signature is not OK */
	call puts16				/* XXX: place for improvement? try the backup one */
	jmp panic16

.Lread_part:
	/* store the important GPT header vars */
	movw $BUFADDR, %di
	movl 72(%di), %eax			/* save 64b LBA of partition entry */
	movl %eax, (gpt_partition_entry_lba)
	movl 76(%di), %eax
	movl %eax, (gpt_partition_entry_lba+4)

	movl 80(%di), %eax			/* number of partitions */
	movl %eax, (gpt_nr_partitions)

	movl 84(%di), %eax			/* size of a partition entry */
	movl %eax, (gpt_size_partition_entry)

	/* Few articles mention primary partition header is most likely spread on 2-33 LBA.
	 * UEFI standard say to follow the header. Size may be uneven. Due to this I need to
	 * check what can I fit into my cache buffer.
	 *
	 * Read is done by sectors. I need to find out:
	 *	- how many sectors buffer has:	BUFSZ/SECTORSZ, adjust the usable size by that
	 *	- how many partitions can buffer hold:	ADJBUFSZ/gpt_size_partition_entry
	 *	- how many times do I need to read the whole partition header: full rounds (full buffer) + leftovers
	 *	- if there are leftovers I need to know how many sectors I need to read them all
	*/

	xorl %edx,%edx
	movzxw (sector_size), %ecx
	movl $BUFSZ, %eax			/* use BUFSZ first */
	div %ecx				/* sectors in buffer */
	movw %ax, (sectors_in_buf)
	mul %ecx
	movw %ax,(bufsize)			/* adjusted bufsize in case bufsz % sector_size != 0 */
	movzxw (gpt_size_partition_entry), %ecx
	div %ecx
	movw %ax, (part_in_buf)			/* partitions buffer can hold */

	test %ax,%ax				/* we need to be able to hold at least one partition */
	jnz .Lread_part.1

	movw $(fatal_bufsz2), %ax
	call puts16
	jmp panic16

.Lread_part.1:
	/* if gpt_nr_partitions < part_in_buf rounds will be 0 and we skip to leftovers */
	movzxw (gpt_nr_partitions), %ecx	/* rounds = gpt_nr_partitions / part_in_buf */
	xchgl %ecx, %eax			/* leftovers = gpt_nr_partitions % part_in_buf */
	div %ecx
	movw %ax, (rounds)
	movw %dx, (leftovers)

	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw (leftovers)
		pushw (rounds)
		pushw (part_in_buf)
		pushw (sectors_in_buf)
		pushw $(dbgmsg_buf_info)
		call printf16
		addw $10, %sp
		pop %ax

		xorw %di, %di			/* keep start-end partition values */
		xorw %si, %si
	.endif

	/* common setup even if we need to do leftovers only */
	movw $BUFADDR, (dap_buf)		/* buffer to read to */
	movl (gpt_partition_entry_lba), %edx	/* LBA to start with */
	movl %edx, (dap_start)
	movl (gpt_partition_entry_lba+4), %edx
	movl %edx, (dap_start+4)

	/* check if we need to do leftovers only */
	test %ax,%ax				/* ax still holds rounds from calculation above */
	jz .Ldo_leftovers

	movw (rounds),%cx			/* we need to read full buffer rounds times */
	movw (sectors_in_buf), %ax		/* LBAs to read, as much as we fit into buffer  */
	movw %ax,(dap_blocks)


.Lrounds:
	.ifdef DEBUG_VERBOSE
		push %cx
		addw (part_in_buf), %si
		pushw %si
		pushw %di
		pushw $(dbgmsg_part_range)
		call printf16
		addw $6, %sp
		pop %cx
	.endif

	xchg %cx, %bp				/* save cx */
	call do_read				/* do_read() */

	movw (part_in_buf), %ax
	call search_uuid_buf			/* search for the uuid */
	xchg %bp, %cx				/* restore cx */

	test %ax,%ax
	jnz .Lfound_part

	.ifdef DEBUG_VERBOSE
		mov %si, %di
	.endif

	movzxw (sectors_in_buf), %eax		/* prepare for next read */
	addl %eax, (dap_start)			/* start LBA is 64b, advance by sectors_in_buf */
	adcl $0, (dap_start+4)
	loop .Lrounds

.Ldo_leftovers:
	.ifdef DEBUG_VERBOSE
		movw $(dbgmsg_doleftovers), %ax
		call puts16
	.endif

	movzxw (leftovers), %ecx		/* if we don't have any leftovers */
	test %ecx,%ecx				/* we have nothing to do, panic */
	jz .Lnopart

	xorl %edx, %edx
	movl (gpt_size_partition_entry), %eax
	movzxw (sector_size), %ebx
	mul %ecx				/* (gpt_size_partition_entry * leftovers) / sector_size */
	div %ebx
	test %edx,%edx				/* if we have reminder we need to add one more sector to read */
	jz .Ldo_leftovers.1
	inc %eax

.Ldo_leftovers.1:
	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw %cx

		pushw (sector_size)
		pushw %ax
		pushw (leftovers)
		pushw $(dbgmsg_leftovers_stats)
		call printf16

		addw (leftovers), %si
		pushw %si
		pushw %di
		pushw $(dbgmsg_part_range)
		call printf16
		addw $14, %sp
		pop %cx
		pop %ax
	.endif

	/* buffer and start LBA were set before rounds were done. If we did rounds start LBA is pointing to */
	/* LBA that should be read next. */
	movw %ax, (dap_blocks)
	call do_read

	movw (leftovers), %ax
	call search_uuid_buf

	test %ax, %ax
	jz .Lnopart

.Lfound_part:
	movw %ax, %di					/* save the result into non-scratch reg */

	movw $8, %cx					/* copy start and end LBA to boot_partition */
	leaw 0x20(%di), %dx				/* it's probably faster to copy these two locations */
	movw $(boot_partition), %ax
	call memcpyw16

	.ifdef DEBUG_VERBOSE
		movw 0x20(%di), %ax
		pushw %ax
		pushw $(dbgmsg_bpart_lba)
		call printf16
	.endif

	/* Load the ext2 superblock */

	//jmp .Lto_be_removed_jump_to_pm

	cli
	hlt

.Lnopart:
	movw $(fatal_nopart), %ax
	call puts16
	jmp panic16


.Lto_be_removed_jump_to_pm:

	/* TODO: remove from boot1.S, migrate to a kernel part along with anything protected-mode related */

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

/* void* bufsearch(int16_t n)
 *
 * search for partition uuid in the cache; returns ptr to the partition header if found, NULL otherwise
*/
.func search_uuid_buf
search_uuid_buf:
	pushw %si
	pushw %di

	movw %ax, %cx				/* n */
	movw $BUFADDR, %si			/* si = start of the partition header */

.Lsearch:
	movw %cx, %di				/* save cx */

	movw $16, %cx
	movw $(linux_ext2_uuid), %dx
	movw %si, %ax
	call memcmp16				/* memcmp16(partuuid, linux_ext2_uuid, 16) */
	movw %di, %cx				/* restore cx */

	test %ax, %ax				/* partition found */
	jz .Lfound

	addw (gpt_size_partition_entry), %si	/* move to next entry */
	loop .Lsearch

	// not found
	xorw %ax, %ax				/* return NULL by default */
	jmp .Lsdone

.Lfound:
	movw %si, %ax
.Lsdone:
	pop %di
	pop %si
	ret
.endfunc


/* do_read()
 *
 * wrapper func to read16, uses bootdrive,dap defined here in boot1.S. read failure means panic
*/
.func do_read
do_read:
	.ifdef DEBUG_VERBOSE			/* verbose logging only */
		.if DEBUG_VERBOSE > 1
		push %bx
		leaw (lba_dap), %bx
		pushw 2(%bx)

		pushw 8(%bx)			/* we are printing it as BE, or LTR */
		pushw 10(%bx)
		pushw 12(%bx)
		pushw 14(%bx)

		pushw 4(%bx)
		pushw $(dbgmsg_doread_stats)
		call printf16
		addw $14, %sp
		pop %bx
		.endif
	.endif

	leaw (lba_dap), %dx
	movw (bootdrive), %ax
	call read16				/* read16(int16_t disk, struct lba_dap* dap) */

	test %ax,%ax
	jz .Lend_do_read

	pushw (errno16)
	pushw $(fatal_read)
	call printf16
	jmp panic16

.Lend_do_read:
	ret	
.endfunc

/* print the error message along with the errno16 code */
.func print_err
print_err:
	xor %ax,%ax
	movb (errno16), %al
	push %ax
	pushw $(msg_bios_err)
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
	sector_size:	.word	0

	.align 4
		gpt_hdr_signature:      .quad 0x5452415020494645
		linux_ext2_uuid:	.byte 0xaf, 0x3d, 0xc6, 0x0f, 0x83, 0x84, 0x72, 0x47, 0x8e, 0x79, 0x3d, 0x69, 0xd8, 0x47, 0x7d, 0xe4

	.align 8
        lba_dap:
				.byte 0x10	/* size of the packet */
				.byte 0		/* reserved */
		dap_blocks:	.word 0		/* how many LBAs to read */
                dap_buf:	.word 0,0	/* adress to read into */
                dap_start:	.quad 0		/* LBA */

	/* smap entry is:
		.quad base, length
		.long type, xattr (acpi 3)
	*/
	.align 8
	.global smap, smap_data
	smap:
		.long 0, 0                              /* entries ; entry size */
	smap_data:
		.zero 1536                              /* actual data, 24*64 = 1536 */

	boot_partition:		.quad 0,0		/* start-end LBA of the boot partition */

	bufsize:			.word 0		/* actual buffer size, adjusted to hold n sector-size blocks */

	/* GPT hdr vars */
	gpt_partition_entry_lba:	.quad 0
	gpt_nr_partitions:		.long 0
	gpt_size_partition_entry:	.long 0

	part_in_buf:			.word 0		/* amount of partitions we can hold in buf */
	sectors_in_buf:			.word 0		/* buffer size in sectors */
	rounds:				.word 0		/* how many full passes i can make when reading partitions */
	leftovers:			.word 0		/* leftover partitons to read */

	msg_boot1:	.asciz	">MIOS boot1\r\n"
	fatal_error:	.asciz	"FATAL ERROR: system halted.\r\n"
	fatal_a20:	.asciz	"Failed to activate A20 gate, aborting.\r\n"
	fatal_read:	.asciz	"disk read failed with error 0x%x\r\n"
	fatal_gpt_sig:	.asciz	"GPT signature verification failed.\r\n"
	fatal_bufsz:	.asciz	"Buffer too small (%d), sector size: %d\r\n"
	fatal_bufsz2:	.asciz	"Buffer too small, unable to cache partition data.\r\n"
	fatal_nopart:	.asciz	"Failed to find MIOS partition, aborting.\r\n"
	msg_bios_err:	.asciz	"BIOS function failed, error code: %x\r\n"
	msg_mem_err:	.asciz	"Failed to get memory map from BIOS.\r\n"

	func_debug1:	.asciz	"address: 0x%x\r\n"

	.ifdef DEBUG_VERBOSE
		dbgmsg_buf_info:	.asciz	"bufsize: %d sectors, %d partitions. rounds: %d, leftovers: %d\r\n"
		dbgmsg_part_range:	.asciz	"partition range: <%d,%d)\r\n"
		dbgmsg_doread_stats:	.asciz	"do_read: buf: 0x%x, start lba: 0x%x%x%x%x, blocks: %d\r\n"
		dbgmsg_bpart_lba:	.asciz	"boot partition LBA start: 0x%x\r\n"
		dbgmsg_doleftovers:	.asciz	"doing leftovers\r\n"
		dbgmsg_leftovers_stats:	.asciz	"%d leftovers need %d %d-sectors to read\r\n"
	.endif

	deb1:	.asciz	"this is string: %s, this is dec: %d, this is hex: %x, string: %s, hex: %x\r\n"
