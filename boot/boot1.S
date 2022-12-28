/* martin */

/* NOTE:
/*	Any address that is used here has to be < 0x10000 as I opted for all segments to be 0.
	Additional checks should be done. Maybe all these checks can be in linker script.
	Linker script will complain if I cross it anyway.
*/

.include "gboot.inc"

.section .text
	.code16
	.global _start

/* macro to print func/var addr */
.macro dbg_show_addr addr
	pushw $\addr
	pushw $(func_debug1)
	call printf16
	addw $4, %sp
.endm

_start:
	jmp 1f

	.asciz "MIOS"

	// XXX: this is not needed. This bootcode is on GPT partition, there's no need to care about BPB ..
	// XXX: to be removed
	.= _start + 0x3e				/* offset to bootcode after BPB */
1:
	/* setup the segment registers */
	xorw %ax, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %fs
	movw %ax, %gs
	movw %ax, %ss
	movw $BOOT1_STACK_SP, %sp

	movw %dx, (w_bp_bootdrive)			/* save bootdrive */

	.ifdef SERIAL					/* serial port output was requested */
		call init_com0
		jmp .Lbootmsg
	.endif

	/* same as with pMBR force serial console if left shift is enabled. */

	// XXX: TODO: it's easy to add .ifdef in current printf implementation but it will mess up
	//	few things if i start to check if console is enabled ..
        movb $0x2, %ah					/* AH=02h, int 0x16: get shift flags */
        int $0x16

	testb $2, %al					/* bit2: left shift */
	jz .Lbootmsg

	movw $(msg_serial_rq), %ax
	call puts16
	call init_com0

.Lbootmsg:
	movw $(msg_boot1), %ax
	call puts16

	.ifdef DEBUG_VERBOSE
		movw $(dbgmsg_verbose), %ax
		call puts16
	.endif

	/* Attempt to enable the A20 gate */
	call enable_A20
	test %ax, %ax
	jnz .Lb1_err_a20				/* fatal error if we can't activate A20 */

	/* Get the system memory map from BIOS */
	// TODO: fallback methods of detecting memory

	movw $(smap), %ax				/* detect memory with E820 */
	call getmem_E820
	test %ax, %ax
	jnz .Lb1_err_e820

	movw $1, %cx
	movw (w_bp_bootdrive), %dx
	movw $ADDR_SIBPBUF, %ax
	call diskinfo16					/* diskinfo16(char* buf, int16_t disk, char eddver) */
	test %ax,%ax
	jz .Lb1_err_errno_panic

	/* From what I've read it seems the 512 sector size is really a standard in BIOS services.
	 * Sector sizes such as 520 are problem for BIOS itself. 
	 * Assuming 512 sector size.
	*/
	movw %ax, %si
	movw 0x18(%si), %ax

	cmpw $0x200, %ax				/* sector size: 512 */
	jne .Lb1_err_unsupp_sectorsz

	movw %ax, (w_bp_sector_size)
	movw $8, (w_sectors_in_buf)			/* how many sectors can we load buffer with */
	movl 0x10(%si), %eax				/* total disk LBAs */
	movl %eax, (q_bp_sectors)
	movl 0x14(%si), %eax
	movl %eax, (q_bp_sectors+4)

	.ifdef DEBUG_VERBOSE
		pushl (q_bp_sectors)
		pushl (q_bp_sectors+4)
		pushw (w_bp_sector_size)
		pushw (w_bp_bootdrive)
		pushw $(dbgmsg_diskinfo)
		call printf16
		addw $14, %sp
	.endif

	/* read the GPT header */
	xorl %ebx, %ebx
	movl %ebx, (q_dap_start+4)			/* set upper 32b to 0 in start LBA */
	inc %bx
	movl %ebx, (q_dap_start)			/* set lower 32b to 1 */
	movw %bx, (w_dap_sectors)			/* reading one LBA */
	movw $ADDR_SIBPBUF,(w_dap_buf)			/* into ADDR_SIBPBUF */
	call do_read

        /* verify GPT signature */
	// NOTE: attempt to read a backup one in case of failure?
	movw $8, %cx
	movw $(gpt_hdr_signature), %dx
	movw $ADDR_SIBPBUF, %ax
	call memcmp16					/* memcmp16(ADDR_SIBPBUF, gpt_hdr_signature, 8) */
	test %ax,%ax
        jnz .Lb1_err_gptsig

	/* store the important GPT header vars */
	movw $ADDR_SIBPBUF, %di

	movl OFST_GPT_HDR_LBA_START(%di), %eax		/* save 64b LBA of partition entry */
	movl %eax, (q_gpt_partition_entry_lba)
	movl OFST_GPT_HDR_LBA_START+4(%di), %eax
	movl %eax, (q_gpt_partition_entry_lba+4)

	movl OFST_GPT_HDR_NR_ENTRIES(%di), %eax		/* number of partitions */
	movl %eax, (l_gpt_nr_partitions)

	movl OFST_GPT_HDR_ENTRY_SZ(%di), %eax		/* size of a partition entry */
	movl %eax, (l_gpt_size_partition_entry)

	/* Few articles mention primary partition header is most likely spread on 2-33 LBA.
	 * UEFI standard say to follow the header. Size may be uneven. Due to this I need to
	 * check what can I fit into my cache buffer.
	 *
	 * I'm assuming sector size 512. I need to find out:
	 *	- how many partitions can buffer hold: GENERIC_BUFSZ/l_gpt_size_partition_entry
	 *	- how many times do I need to read the whole partition header: full rounds (full buffer) + leftovers
	 *	- if there are leftovers I need to know how many sectors I need to read them all
	*/

	xorl %edx,%edx
	movl $GENERIC_BUFSZ, %eax
	movl (l_gpt_size_partition_entry), %ecx
	div %ecx
	movw %ax, (w_items_in_buf)			/* partitions buffer can hold */

	test %ax,%ax					/* we need to be able to hold at least one partition */
	jz .Lb1_err_bufsz

	/* if l_gpt_nr_partitions < w_items_in_buf w_rounds will be 0 and we skip to w_leftovers */
	movl (l_gpt_nr_partitions), %ecx		/* w_rounds = l_gpt_nr_partitions / w_items_in_buf */
	xchgl %ecx, %eax				/* w_leftovers = l_gpt_nr_partitions % w_items_in_buf */
	div %ecx
	movw %ax, (w_rounds)
	movw %dx, (w_leftovers)

	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw (w_leftovers)
		pushw (w_rounds)
		pushw (w_items_in_buf)
		pushw (w_sectors_in_buf)
		pushw $(dbgmsg_buf_info)
		call printf16
		addw $10, %sp
		pop %ax

		xorw %di, %di	/* keep start-end partition values */
		xorw %si, %si
	.endif

	/* common setup even if we need to do w_leftovers only */
	movw $ADDR_SIBPBUF, (w_dap_buf)			/* buffer to read to */
	movl (q_gpt_partition_entry_lba), %edx		/* LBA to start with */
	movl %edx, (q_dap_start)
	movl (q_gpt_partition_entry_lba+4), %edx
	movl %edx, (q_dap_start+4)

	/* check if we need to do leftovers only */
	test %ax,%ax					/* ax still holds w_rounds from calculation above */
	jz .Lb1_leftovers

	movw (w_rounds),%cx				/* we need to read full buffer w_rounds times */
	movw (w_sectors_in_buf), %ax			/* LBAs to read, as much as we fit into buffer  */
	movw %ax,(w_dap_sectors)

.Lb1_rounds:
	.ifdef DEBUG_VERBOSE
		push %cx
		addw (w_items_in_buf), %si
		pushw %si
		pushw %di
		pushw $(dbgmsg_part_range)
		call printf16
		addw $6, %sp
		pop %cx
	.endif

	xchg %cx, %bp					/* save cx */
	call do_read

	movw (w_items_in_buf), %ax
	call search_uuid_buf				/* search for the uuid */
	xchg %bp, %cx					/* restore cx */

	test %ax,%ax
	jnz .Lb1_partition_found

	.ifdef DEBUG_VERBOSE
		mov %si, %di
	.endif

	movzxw (w_sectors_in_buf), %eax			/* prepare for next read */
	addl %eax, (q_dap_start)			/* start LBA is 64b, advance by w_sectors_in_buf */
	adcl $0, (q_dap_start+4)
	loop .Lb1_rounds

.Lb1_leftovers:
	.ifdef DEBUG_VERBOSE
		movw $(dbgmsg_dow_leftovers), %ax
		call puts16
	.endif

	movzxw (w_leftovers), %ecx			/* if we don't have any w_leftovers */
	test %ecx,%ecx					/* we have nothing to do, panic */
	jz .Lb1_err_nopart

	xorl %edx, %edx
	movl (l_gpt_size_partition_entry), %eax
	movzxw (w_bp_sector_size), %ebx
	mul %ecx					/* (l_gpt_size_partition_entry * w_leftovers) / w_bp_sector_size */
	div %ebx
	test %edx,%edx					/* if we have reminder we need to add one more sector to read */
	jz .Lb1_leftovers.1
	inc %eax

.Lb1_leftovers.1:
	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw %cx

		pushw (w_bp_sector_size)
		pushw %ax
		pushw (w_leftovers)
		pushw $(dbgmsg_leftovers_stats)
		call printf16

		addw (w_leftovers), %si
		pushw %si
		pushw %di
		pushw $(dbgmsg_part_range)
		call printf16
		addw $14, %sp
		pop %cx
		pop %ax
	.endif

	/* Buffer and start LBA were set before rounds were done.
	   If we did rounds start LBA is pointing to LBA that should be read next.
	*/
	movw %ax, (w_dap_sectors)
	call do_read

	movw (w_leftovers), %ax
	call search_uuid_buf
	test %ax, %ax
	jz .Lb1_err_nopart

.Lb1_partition_found:
	movw %ax, %di					/* di - buffer where partition was found */
	movw $8, %cx					/* copy start and end LBA to boot_partition */
	leaw OFST_GPT_PART_ENTRY_LBA_START(%di), %dx
	movw $(q_bp_lba_start), %ax
	call memcpyw16

	.ifdef DEBUG_VERBOSE
		pushw OFST_GPT_PART_ENTRY_LBA_START(%di)
		pushw $(dbgmsg_bpart_lba)
		call printf16
		addw $4, %sp
	.endif

	movl $(boot_partition), %eax			/* initialize ext2 module */
	call ext2_initmod				/* int16_t ext2_initmod(boot_partition *bp) */

/*
// XXX: keeping it here for now
	movw $(debugmefile), %ax
	call ext2_search_file
	testw %ax,%ax
	jz .Lb1_err_nokernel

	movl $0x16BF8, %ecx
	movw $ADDR_BLOCBUF, %dx
	movw $ADDR_INODE, %ax
	call ext2_inode_seek

	pushw %ax
	pushw $(cookiestr)
	call printf16

	jmp .Lb1_haltme
	debugmefile:	.asciz	"/debugme"
	cookiestr:	.asciz	"cookie: %s\r\n"
	//____________________________________________
*/

	movw $(strkernel), %ax
	call ext2_search_file				/* ext2_search_file("/boot/kernel") */
	testw %ax,%ax
	jz .Lb1_err_nokernel

	/* ax: inode structure */
	call elf32_load_file
	testw %ax,%ax
	jnz .Lb1_haltme

	pushl $ADDR_KERNEL_ENTRY			/* show where the kernel is being loaded */
	pushw $(msg_jmp_kern)
	call printf16
	addw $6, %sp

	/* prepare to jump */
        cli
        lgdt (gdt_desc)
        movl %cr0, %eax      				/* enable protected mode */
        orl $1, %eax
        movl %eax, %cr0

	pushl $(smap)					/* argument to entry */
        ljmpl $8, $ADDR_KERNEL_ENTRY			/* flush instruction cache and set the proper cs selector */

	jmp .Lb1_haltme

	/* Handle errors */
.Lb1_err_bufsz:
	movw $(fatal_bufsz), %ax
	call puts16
	jmp panic16

.Lb1_err_gptsig:
	movw $(fatal_gpt_sig),%ax
	call puts16
	jmp panic16

.Lb1_err_unsupp_sectorsz:
	pushw %ax
	pushw $(fatal_secsize)
	call printf16
	jmp panic16

.Lb1_err_errno_panic:
	call print_err
	jmp panic16

.Lb1_err_e820:
	movw $(msg_mem_err), %ax
	call puts16
	jmp panic16

.Lb1_err_a20:
	pushw $(fatal_a20)
	call printf16
	jmp panic16

.Lb1_err_nopart:
	movw $(fatal_nopart), %ax
	call puts16
	jmp panic16

.Lb1_err_nokernel:
	pushw $(strkernel)
	pushw $(fatal_nokernel)
	call printf16
	/* fall through to halt */

.Lb1_haltme:
	movw $(msg_haltnow), %ax
	call puts16
.Lb1_haltme.1:	/* zicher loop */
	cli
	hlt
	jmp .Lb1_haltme.1


/* void* search_uuid_buf(int16_t n)
 *
 * search for partition uuid in the buf
 * returns ptr to the partition header if found, NULL otherwise
*/
.func search_uuid_buf
search_uuid_buf:
	pushw %si
	pushw %di

	movw %ax, %cx					/* n */
	movw $ADDR_SIBPBUF, %si				/* si = start of the partition header */

.Lb1_sbuf:
	movw %cx, %di					/* save cx */

	movw $16, %cx
	movw $(linux_ext2_uuid), %dx
	movw %si, %ax
	call memcmp16					/* memcmp16(partuuid, linux_ext2_uuid, 16) */
	movw %di, %cx					/* restore cx */

	test %ax, %ax					/* partition found */
	jz .Lb1_sbuf_found

	addw (l_gpt_size_partition_entry), %si		/* move to next entry */
	loop .Lb1_sbuf

	// not found
	xorw %ax, %ax					/* return NULL by default */
	jmp .Lb1_sbuf_done

.Lb1_sbuf_found:
	movw %si, %ax
.Lb1_sbuf_done:
	pop %di
	pop %si
	ret
.endfunc

/* do_read()
 *
 * wrapper func for diskread16
 * uses w_bp_bootdrive, local dap packet defined here in boot1.S. read failure means panic
*/
.func do_read
do_read:
	.ifdef DEBUG_VERBOSE
		.if DEBUG_VERBOSE > 1
		push %bx
		leaw (lba_dap), %bx
		pushw 2(%bx)

		pushl 8(%bx)		/* we are printing it as BE, or LTR */
		pushl 12(%bx)

		pushw 4(%bx)
		pushw $(dbgmsg_doread_stats)
		call printf16
		addw $14, %sp
		pop %bx
		.endif
	.endif

	leaw (lba_dap), %dx
	movw (w_bp_bootdrive), %ax
	call diskread16			/* diskread16(int16_t disk, struct lba_dap* dap) */

	test %ax,%ax
	jz .Lb1_doread_end

	movzxb (errno16), %ax
	push %ax
	pushw $(fatal_read)
	call printf16
	jmp panic16

.Lb1_doread_end:
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
.global panic16
.func panic16
panic16:
	cli
	call dump_regs

	movw $(panic_stack), %ax
	call puts16

	movw $0x10, %dx
	movw %sp, %ax
	call dump_mem16

	movw $(fatal_error), %ax
	call puts16

.Lpanic_loop:
	hlt
	jmp .Lpanic_loop
	ret					/* never returns */
.endfunc

.section .data
	/* basic information about the boot disk */
	.align 8

	gpt_hdr_signature:      .quad 0x5452415020494645
	linux_ext2_uuid:	.byte 0xaf, 0x3d, 0xc6, 0x0f, 0x83, 0x84, 0x72, 0x47, 0x8e, 0x79, 0x3d, 0x69, 0xd8, 0x47, 0x7d, 0xe4

	.align 8
        lba_dap:
				.byte 0x10	/* size of the packet */
				.byte 0		/* reserved */
		w_dap_sectors:	.word 0		/* how many LBAs to read */
                w_dap_buf:	.word 0,0	/* adress to read into */
                q_dap_start:	.quad 0		/* LBA */

	/* smap entry is:
		.quad base, length
		.long type, xattr (acpi 3)
	*/
	// XXX: does it make sense to put in bss ?
	.align 8
	.global smap, smap_data
	smap:
		.long 0, 0                              /* entries ; entry size */
	smap_data:
		.zero 1536                              /* actual data, 24*64 = 1536 */

	boot_partition:
		q_bp_lba_start:		.quad 0		/* start LBA of the partition */
		q_bp_lba_end:		.quad 0		/* end LBA of the partition */
		q_bp_sectors:		.quad 0		/* total disk capacity */
		w_bp_bootdrive:		.word 0		/* w_bp_bootdrive as reported by BIOS */
		w_bp_sector_size:	.word 0		/* disk sector size */

	/* GPT hdr vars */
	q_gpt_partition_entry_lba:	.quad 0
	l_gpt_nr_partitions:		.long 0
	l_gpt_size_partition_entry:	.long 0

	w_items_in_buf:			.word 0		/* amount of partitions we can hold in buf */
	w_sectors_in_buf:		.word 0		/* buffer size in sectors */
	w_rounds:			.word 0		/* how many full passes i can make when reading partitions */
	w_leftovers:			.word 0		/* leftover partitons to read */

	/* GDT table definiion */
	.align 16
	gdt_desc:	.word end_gdt-gdt-1			/* size */
			.word gdt,0				/* linear address, ptr to gdt */
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
		.byte 0x0		/* RTL: flags-limit 16-19: , flags: 16b protected mode segment, byte granularity */
		.byte 0			/* base 24-31 */

		/* data in real mode */
		.word 0xffff		/* limit bits 0-15 */
		.word 0			/* base 0-15 */
		.byte 0x0		/* base 16-23 */
		.byte 0x92		/* access: RTL: present, ring0, data segment, non-exec, grows up, rw, accessed=0 */
		.byte 0x0		/* RTL: flags-limit 16-19: , flags: 16b protected mode segment, byte granularity */
		.byte 0			/* base 24-31 */

		/* XXX: TSS segment should be defined ; I need to think of memory layout though, base should be the designated mem, limit
			is sizeof(tss), at least that's what i think.
		*/
	end_gdt:

	msg_boot1:	.asciz	">MIOS boot1\r\n"
	msg_serial_rq:	.asciz	"On demand request to enable serial port\r\n"
	strkernel:	.asciz	"/boot/kernel"

	fatal_error:	.asciz	"FATAL ERROR: system halted.\r\n"
	fatal_a20:	.asciz	"Failed to activate A20 gate, aborting.\r\n"
	fatal_read:	.asciz	"disk read failed with error 0x%x\r\n"
	fatal_gpt_sig:	.asciz	"GPT signature verification failed.\r\n"
	fatal_secsize:	.asciz	"Unsupported sector size detected: %d\r\n"
	fatal_bufsz:	.asciz	"Buffer too small, unable to cache partition data.\r\n"
	fatal_nopart:	.asciz	"Failed to find MIOS partition, aborting.\r\n"
	fatal_nokernel:	.asciz	"%s not found.\r\n"
	msg_bios_err:	.asciz	"BIOS function failed, error code: %x\r\n"
	msg_mem_err:	.asciz	"Failed to get memory map from BIOS.\r\n"
	msg_haltnow:	.asciz	"boot1: system halted for now.\r\n"

	msg_jmp_kern:	.asciz	"\r\nkernel @ 0x%lx\r\n"

	panic_stack:	.asciz	"stack:\r\n"
	func_debug1:	.asciz	"debug: 0x%x\r\n"

	.ifdef DEBUG_VERBOSE
		dbgmsg_verbose:		.asciz	"verbose boot enabled.\r\n"
		dbgmsg_diskinfo:	.asciz	"bootdisk: 0x%x, sector size: %d, total LBAs: 0x%lx%lx\r\n"
		dbgmsg_buf_info:	.asciz	"bufsize: %d sectors, %d partitions. rounds: %d, leftovers: %d\r\n"
		dbgmsg_part_range:	.asciz	"partition range: <%d,%d)\r\n"
		dbgmsg_doread_stats:	.asciz	"do_read: buf: 0x%x, start lba: 0x%lx%lx, sectors: %d\r\n"
		dbgmsg_bpart_lba:	.asciz	"boot partition LBA start: 0x%x\r\n"
		dbgmsg_dow_leftovers:	.asciz	"doing w_leftovers\r\n"
		dbgmsg_leftovers_stats:	.asciz	"%d leftovers need %d %d-sectors to read\r\n"
	.endif
