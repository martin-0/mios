/* martin */
	.set BUFADDR, 0x5000
	.set PAGE_SIZE, 0x1000				//  \  intentionally set to the same size
	.set BUFSZ, 0x1000				//  /

	.set STACK_OFFST, 0x4ffc

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

	movw %dx, (bp_bootdrive)		/* save bootdrive */

	movw $(msg_boot1), %ax
	call puts16

	.ifdef DEBUG_VERBOSE
		movw $(dbgmsg_verbose), %ax
		call puts16
	.endif

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
	jz .Ldiskinfo

	movw $(msg_mem_err), %ax
	call puts16
	jmp panic16

.Ldiskinfo:
	movw $1, %cx
	movw (bp_bootdrive), %dx
	movw $BUFADDR, %ax
	call diskinfo16				/* diskinfo16(char* buf, int16_t disk, char eddver) */
	test %ax,%ax
	jnz .Ldiskinfok

	call print_err				/* print the error and panic */
	jmp panic16

.Ldiskinfok:
	/* From what I've read it seems the 512 sector size is really a standard in BIOS services. Sector sizes such as 520
	 * are problem for BIOS itself, at least so I was told.
	 *
	 * For now I'm assuming 512 sector size.
	 */
	movw %ax, %si
	movw 0x18(%si), %ax

	cmpw $0x200, %ax			/* sector size: 512 */
	je .Lsecsizeok

	pushw %ax				/* unsupported sector size */
	pushw $(fatal_secsize)
	call printf16
	jmp panic16

.Lsecsizeok:
	movw %ax, (bp_sector_size)
	movw $8, (sectors_in_buf)		/* how many sectors can we load buffer with */

	movl 0x10(%si), %eax			/* total disk LBAs */
	movl %eax, (bp_sectors)
	movl 0x14(%si), %eax
	movl %eax, (bp_sectors+4)

	.ifdef DEBUG_VERBOSE
		pushl (bp_sectors)
		pushl (bp_sectors+4)
		pushw (bp_sector_size)
		pushw (bp_bootdrive)
		pushw $(dbgmsg_diskinfo)
		call printf16
		addw $14, %sp
	.endif

.Lread_gpthdr:

	/* read the GPT header */
	xorl %ebx, %ebx
	movl %ebx, (dap_start+4)		/* set upper 32b to 0 in start LBA */
	inc %bx
	movl %ebx, (dap_start)			/* set lower 32b to 1 */
	movw %bx, (dap_sectors)			/* reading one LBA */
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
	 * I thought I'd support variable sector size but was told that with BIOS 512 is really the only practical option.
	 *
	 * I'm assuming sector size 512 so few things should be simplier. I need to find out:
	 *	- how many partitions can buffer hold: BUFSZ/gpt_size_partition_entry
	 *	- how many times do I need to read the whole partition header: full rounds (full buffer) + leftovers
	 *	- if there are leftovers I need to know how many sectors I need to read them all
	*/

	xorl %edx,%edx
	movl $BUFSZ, %eax
	movzxw (gpt_size_partition_entry), %ecx
	div %ecx
	movw %ax, (items_in_buf)		/* partitions buffer can hold */

	test %ax,%ax				/* we need to be able to hold at least one partition */
	jnz .Lread_part.1

	movw $(fatal_bufsz), %ax
	call puts16
	jmp panic16

.Lread_part.1:
	/* if gpt_nr_partitions < items_in_buf rounds will be 0 and we skip to leftovers */
	movzxw (gpt_nr_partitions), %ecx	/* rounds = gpt_nr_partitions / items_in_buf */
	xchgl %ecx, %eax			/* leftovers = gpt_nr_partitions % items_in_buf */
	div %ecx
	movw %ax, (rounds)
	movw %dx, (leftovers)

	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw (leftovers)
		pushw (rounds)
		pushw (items_in_buf)
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
	movw %ax,(dap_sectors)

.Lrounds:
	.ifdef DEBUG_VERBOSE
		push %cx
		addw (items_in_buf), %si
		pushw %si
		pushw %di
		pushw $(dbgmsg_part_range)
		call printf16
		addw $6, %sp
		pop %cx
	.endif

	xchg %cx, %bp				/* save cx */
	call do_read				/* do_read() */

	movw (items_in_buf), %ax
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
	movzxw (bp_sector_size), %ebx
	mul %ecx				/* (gpt_size_partition_entry * leftovers) / bp_sector_size */
	div %ebx
	test %edx,%edx				/* if we have reminder we need to add one more sector to read */
	jz .Ldo_leftovers.1
	inc %eax

.Ldo_leftovers.1:
	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw %cx

		pushw (bp_sector_size)
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
	movw %ax, (dap_sectors)
	call do_read

	movw (leftovers), %ax
	call search_uuid_buf

	test %ax, %ax
	jz .Lnopart

.Lfound_part:
	movw %ax, %di					/* di - buffer where partition was found */

	movw $8, %cx					/* copy start and end LBA to boot_partition */
	leaw 0x20(%di), %dx				/* it's probably faster to copy these two locations */
	movw $(bp_lba_start), %ax
	call memcpyw16

	.ifdef DEBUG_VERBOSE
		movw 0x20(%di), %ax
		pushw %ax
		pushw $(dbgmsg_bpart_lba)
		call printf16
	.endif

	movl $(boot_partition), %eax			/* initialize ext2 module */
	call ext2_initmod				/* int16_t ext2_initmod(boot_partition *bp) */

	dbg_show_addr .Lhint1
	nop
	nop

	movw $(strkernel), %ax
	call ext2_search_file				/* ext2_search_file("/boot/kernel") */

haltme:
	movw $(debug_info_halt), %ax
	call puts16
	cli
	hlt

.Lnopart:
	movw $(fatal_nopart), %ax
	call puts16
	jmp panic16

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
 * wrapper func to diskread16, uses bp_bootdrive,dap defined here in boot1.S. read failure means panic
*/
.func do_read
do_read:
	.ifdef DEBUG_VERBOSE			/* verbose logging only */
		.if DEBUG_VERBOSE > 1
		push %bx
		leaw (lba_dap), %bx
		pushw 2(%bx)

		pushl 8(%bx)			/* we are printing it as BE, or LTR */
		pushl 12(%bx)

		pushw 4(%bx)
		pushw $(dbgmsg_doread_stats)
		call printf16
		addw $14, %sp
		pop %bx
		.endif
	.endif

	leaw (lba_dap), %dx
	movw (bp_bootdrive), %ax
	call diskread16				/* read16(int16_t disk, struct lba_dap* dap) */

	test %ax,%ax
	jz .Lend_do_read

	movzxb (errno16), %ax
	push %ax
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
		dap_sectors:	.word 0		/* how many LBAs to read */
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


	// struct boot_partition {
	//	uint64_t	bp_lba_start;
	//	uint64_t	bp_lba_end;
	//	uint64_t	bp_sectors
	//	uint16_t	bp_bootdrive;
	//	uint16_t	bp_sector_size;
	// }

	boot_partition:
		bp_lba_start:	.quad 0			/* start LBA of the partition */
		bp_lba_end:	.quad 0			/* end LBA of the partition */
		bp_sectors:	.quad 0			/* total disk capacity */
		bp_bootdrive:	.word 0			/* bp_bootdrive as reported by BIOS */
		bp_sector_size:	.word 0			/* sector size of the disk */

	bufsize:			.word 0		/* actual buffer size, adjusted to hold n sector-size blocks */

	/* GPT hdr vars */
	gpt_partition_entry_lba:	.quad 0
	gpt_nr_partitions:		.long 0
	gpt_size_partition_entry:	.long 0

	items_in_buf:			.word 0		/* amount of partitions we can hold in buf */
	sectors_in_buf:			.word 0		/* buffer size in sectors ; XXX: used when I thought I do support for different sector sizes.. */
	rounds:				.word 0		/* how many full passes i can make when reading partitions */
	leftovers:			.word 0		/* leftover partitons to read */

	msg_boot1:	.asciz	">MIOS boot1\r\n"
	strkernel:	.asciz	"/boot/kernel"

	fatal_error:	.asciz	"FATAL ERROR: system halted.\r\n"
	fatal_a20:	.asciz	"Failed to activate A20 gate, aborting.\r\n"
	fatal_read:	.asciz	"disk read failed with error 0x%x\r\n"
	fatal_gpt_sig:	.asciz	"GPT signature verification failed.\r\n"
	fatal_secsize:	.asciz	"Unsupported sector size detected: %d\r\n"
	fatal_bufsz:	.asciz	"Buffer too small, unable to cache partition data.\r\n"
	fatal_nopart:	.asciz	"Failed to find MIOS partition, aborting.\r\n"
	msg_bios_err:	.asciz	"BIOS function failed, error code: %x\r\n"
	msg_mem_err:	.asciz	"Failed to get memory map from BIOS.\r\n"

	panic_stack:	.asciz	"stack:\r\n"

	func_debug1:	.asciz	"debug: 0x%x\r\n"

	initmsg:	.asciz	"ext2_initmod returned %d, errno: %d\r\n"

	.ifdef DEBUG_VERBOSE
		dbgmsg_verbose:		.asciz	"verbose boot enabled.\r\n"
		dbgmsg_diskinfo:	.asciz	"bootdisk: 0x%x, sector size: %d, total LBAs: 0x%lx%lx\r\n"
		dbgmsg_buf_info:	.asciz	"bufsize: %d sectors, %d partitions. rounds: %d, leftovers: %d\r\n"
		dbgmsg_part_range:	.asciz	"partition range: <%d,%d)\r\n"
		dbgmsg_doread_stats:	.asciz	"do_read: buf: 0x%x, start lba: 0x%lx%lx, sectors: %d\r\n"
		dbgmsg_bpart_lba:	.asciz	"boot partition LBA start: 0x%x\r\n"
		dbgmsg_doleftovers:	.asciz	"doing leftovers\r\n"
		dbgmsg_leftovers_stats:	.asciz	"%d leftovers need %d %d-sectors to read\r\n"
	.endif

	debug_info_halt:	.asciz	"info: system halted for now.\r\n"
