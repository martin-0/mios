/* martin */

	.set EXT2_MAGIC, 0xef53
	.set EXT2_SIZE_LOG_UNIT, 1024			/* block size: EXT2_SIZE_LOG_UNIT << s_log_block_size */

	.set EXT2_OFST_SUPERBLOCK, 2			/* offset from the beginning of the ext2 FS to superblock, in 512 sectors */
	.set EXT2_SB_OFST_ALLBLOCKS,4			/* s_blocks_count */
	.set EXT2_SB_OSFT_LOGBS, 0x18			/* s_log_block_size */
	.set EXT2_SB_OFST_BLOCK_PG, 0x20		/* s_blocks_per_group */
	.set EXT2_SB_OFST_INODES_PG, 0x28		/* s_inodes_per_group */
	.set EXT2_SB_OFST_MAGIC, 0x38			/* s_magic */
	.set EXT2_SB_OFST_STATE, 0x3a			/* s_state */
	.set EXT2_SB_OFST_ERR, 0x3c			/* s_error */
	.set EXT2_SB_OSFT_REV_LEVEL, 0x4c		/* s_rev_level */
	.set EXT2_SB_OFST_INODE_SZ, 0x58		/* s_inode_size */

	.set BUFADDR, 0x3000				/* it's buffer for ext2 module. it's expected nobody else is writting to it. */
	.set BUFSZ, 0x1000
	.set PAGE_SIZE, 0x1000
	.set SECTORS_IN_BUF, 8				/* 4096/512 = 8 */

	/* enums */
	.set ENOMAGIC, 2
	.set EBSUNSUPP, 3
	.set EFSPANIC, 4
	.set EINODESZ, 5

.section .text
	.code16

/* int16_t ext2_initmod(boot_partition *bp)
 *
*/
.global ext2_initmod
.func ext2_initmod
ext2_initmod:
	pushl %esi
	movl %eax, %esi

	/* init ext2_partition structure */
	movw $8, %cx					/* use memcpyw16 to copy lba_start and lba_end */
	movl %esi, %edx
	movl $(ext2_partition), %eax
	call memcpyw16
	movw 24(%esi), %ax				/* boot_partition->bp_bootdrive */
	movw %ax, (bp_disk)

	/* prepare the DAP for reading the superblock */
	movw $BUFADDR, (dap_buf)			/* set buffer */
	movw $BUFADDR, (bc_addr)			/* DAP and ext2 buffer are the same */
	movw $SECTORS_IN_BUF,(dap_sectors)		/* fill up the whole buffer */
	movl (bp_lba_start), %eax			/* set LBA 64b */
	movl %eax, (dap_start)
	movl (bp_lba_start+4), %eax
	movl %eax, (dap_start+4)			/* add offset to the superblock */
	addl $EXT2_OFST_SUPERBLOCK, (dap_start)
	adcl $0, (dap_start+4)

	.ifdef DEBUG_VERBOSE
		pushw (bp_disk)
		pushl (bp_lba_end)
		pushl (bp_lba_end+4)
		pushl (bp_lba_start)
		pushl (bp_lba_start+4)
		pushw $(ext2_dbg_bootpartition)
		call printf16
		addw $20, %sp
	.endif
	call ext2_read

	test %ax,%ax					/* ax is set to 1 along with errno16 in case of an error */
	jnz .Linitm_end

	movl $BUFADDR, %esi				/* buffer */
	cmpw $EXT2_MAGIC, EXT2_SB_OFST_MAGIC(%si)
	je .Lmagic_ok
	
	movw $(ext2_no_magic), %ax			/* partition doesn't have magic word, rejecting to continue */
	call puts16
	movw $ENOMAGIC, %ax				/* set error code */
	jmp .Linitm_end

.Lmagic_ok:
	movl EXT2_SB_OFST_STATE(%si), %eax		/* loads 2B s_state and 2B s_error at the same time */
	cmpw $1, %ax					/* 1: VALID_FS, 2: ERROR_DETECTED */
	je .Lbsize					/* OK to proceed with valid FS */

	pushl %eax					/* inform about the unclean FS */
	movl $(ext2_fs_state_unclean), %eax
	call puts16
	popl %eax

	shrl $16, %eax					/* shift error value to ax */
	cmpw $3, %ax					/* 3 = panic on error, refuse to continue */
	jne .Lstate_ok_enough				/* ok enough to continue reading the FS */

	movw $EFSPANIC, %ax				/* exit with error */
	jmp .Linitm_end

.Lstate_ok_enough:
	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw $(ext2_fs_state_okenough)
		call printf16
		addw $4, %sp
	.endif	
.Lbsize:
	movl $EXT2_SIZE_LOG_UNIT, %eax			/* blocksize = 1024 << s_log_block_size */
	movl EXT2_SB_OSFT_LOGBS(%si), %ecx		/* s_log_block_size */
	shll %ecx, %eax	

	cmpw $PAGE_SIZE, %ax				/* blocksize has to be <= PAGE_SIZE */
	jbe .Lbs_ok

	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw $(ext2_bs_unsupported)
		call printf16
		addw $4, %sp
	.endif

	movw $EBSUNSUPP, %ax
	jmp .Linitm_end

.Lbs_ok:
	movl %eax, (ext2_s_blocksize)			/* save the block size */

	movl $4, %edx					/* figure out the bc_capacity */
	shrl %cl, %edx					/* ecx still has s_log_block_size ; 4 >> s_log_block_size ; BUFSZ/1024 = 4 */
	movl %edx, (bc_capacity)

	movl EXT2_SB_OSFT_REV_LEVEL(%si), %eax		/* check the revision version, i.e. major version */
	movl %eax, ext2_s_rev_level

	testl %eax, %eax				/* handle version-dependent variables */
	jz .Lvers0

	movw EXT2_SB_OFST_INODE_SZ(%si), %ax		/* inode size can't be bigger than block size */
	cmpw %ax, (ext2_s_blocksize)
	jge .Linodesz_ok

	movw $EINODESZ, %ax
	jmp .Linitm_end

.Linodesz_ok:
	movw %ax, (ext2_s_node_size)			/* save inode size */
	jmp .Lsb_cont

.Lvers0:
	movw $0x80, (ext2_s_node_size)			/* default node size */

.Lsb_cont:
	movl EXT2_SB_OFST_ALLBLOCKS(%si), %eax
	movl %eax, (ext2_s_total_blocks)		/* save total blocks on fs */

	movl EXT2_SB_OFST_BLOCK_PG(%si), %eax
	movl %eax, (ext2_s_blocks_per_group)		/* save blocks per group */

	movl EXT2_SB_OFST_INODES_PG(%si), %eax
	movl %eax, (ext2_s_inodes_per_group)		/* save inodes per group */

	/* XXX: I should implement check on:
		- ext2_s_blocks_per_group, ext2_s_inodes_per_group can't be 0
		- version, to see if there are features that would block me reading the FS
		- size of the inode itself
	*/

	/* NOTE:
		Superblock starts 1024b from the partition start and is 1kB big.
		Depending on the block size following is in the buffer cache:

			1k block: [superblock][bgdt][block3][block4]	; block 0 was skipped by EXT2_OFST_SUPERBLOCK (1024, ie block size)
			2k block: [skipped 0x400|superblock][bgdt]	; block 1 is block group descriptor table
			4k block: [skipped 0x400|superblock|padding]	; gbdt is not in cache
	*/

	cmpl $1024, (ext2_s_blocksize)
	jne .Lbsnot1k
	movl $1, (bc_block_start)			/* our buffer started from block 1 */

.Lbsnot1k:
							/* for any other size it's block 0, i.e. default val */
	xorl %eax, %eax					/* return val */	
.Linitm_end:
	popl %esi	
	ret
.endfunc

/* int8_t ext2_read()
 *
 * function is almost the same as do_read() in boot1.S. difference is this function
 * doesn't panic and lets user deal with it.
*/
.func ext2_read
ext2_read:
	.ifdef DEBUG_VERBOSE
		.if DEBUG_VERBOSE > 1
			pushw (dap_sectors)
			pushl (dap_start)
			pushl (dap_start+4)
			pushw (dap_buf)
			pushw $(dbgmsg_ext2_readstats)
			call printf16
			addw $14, %sp
		.endif
	.endif
	leaw (lba_dap), %dx
	movw (bp_disk), %ax
	call read16				/* errno16 and ax set in case of an error */
	ret
.endfunc

.global dbg_ext2_dumpvars
.func dbg_ext2_dumpvars
dbg_ext2_dumpvars:
	movw $(ext2_dbg_msg_start), %ax
	call puts16

	pushl (dap_start)
	pushl (dap_start+4)
	pushw (dap_buf)
	pushw (dap_buf+2)
	pushw (dap_sectors)
	movzxb (lba_dap), %ax
	pushw %ax
	pushw $(ext2_dbg_dap)
	call printf16
	addw $18, %sp

	pushl (bc_capacity)
	pushl (bc_block_start)
	pushw (bc_addr)
	pushw $(ext2_dbg_blockcache)
	call printf16
	addw $12, %sp

	pushw (bp_disk)
	pushl (bp_lba_end)
	pushl (bp_lba_end+4)
	pushl (bp_lba_start)
	pushl (bp_lba_start+4)
	pushw $(ext2_dbg_bootpartition)
	call printf16
	addw $20, %sp

	pushw (ext2_s_node_size)
	pushl (ext2_s_rev_level)
	pushl (ext2_s_inodes_per_group)
	pushl (ext2_s_blocks_per_group)
	pushl (ext2_s_total_blocks)
	pushl (ext2_s_blocksize)
	pushw $(ext2_dbg_superblock)
	call printf16
	addw $24, %sp

	movw $(ext2_dbg_msg_end), %ax
	call puts16
	ret
.endfunc

.section .data
        .align 8
		lba_dap:
				.byte 0x10	/* size of the packet */
				.byte 0		/* reserved */
		dap_sectors:	.word 0		/* how many LBAs to read */
		dap_buf:	.word 0,0	/* adress to read into */
		dap_start:	.quad 0		/* LBA */

	ext2_blockcache:
		bc_addr:	.word 0
		bc_block_start:	.long 0
		bc_capacity:	.long 0

	ext2_partition:
		bp_lba_start:	.quad 0
		bp_lba_end:	.quad 0
		bp_disk:	.word 0

	/* superblock variables */
	ext2_s_blocksize:		.long 0	
	ext2_s_total_blocks:		.long 0
	ext2_s_blocks_per_group:	.long 0
	ext2_s_inodes_per_group:	.long 0
	ext2_s_rev_level:		.long 0
	ext2_s_node_size:		.word 0

	ext2_read_failed:	.asciz	"ext2_read: read failure: %x\r\n"
	ext2_no_magic:		.asciz	"ext2: no magic signature found.\r\n"
	ext2_bs_unsupported:	.asciz	"ext2: unsupported block size: %d\r\n"

	ext2_fs_state_unclean:	.asciz	"ext2: warning: filesystem was not unmounted properly.\r\n" 
	ext2_fs_state_okenough:	.asciz	"ext2: ok to proceed anyway, error handling code: %d\r\n"

	/* debug strings */
	ext2_dbg_msg_start:	.asciz	"\r\n-- ext2 dump of variables --\r\n"
	ext2_dbg_dap:		.asciz	"dap packet: size: %d, sectors: %d, buf: %x:%x, lba: 0x%lx%lx\r\n"
	ext2_dbg_blockcache:	.asciz	"cache: addr: 0x%x, start block: 0x%lx, capacity: 0x%lx\r\n"
	ext2_dbg_bootpartition:	.asciz	"partition: 0x%lx%lx - 0x%lx%lx, disk: 0x%x\r\n"
	ext2_dbg_superblock:	.ascii	"superblock:\r\n"
				.ascii	"  blocksize:\t\t0x%lx\r\n"
				.ascii	"  total blocks:\t\t0x%lx\r\n"
				.ascii	"  blocks per group:\t0x%lx\r\n"
				.ascii	"  inodes per group:\t0x%lx\r\n"
				.ascii	"  revision level:\t0x%lx\r\n"
				.asciz	"  node size:\t\t0x%x\r\n"
	ext2_dbg_msg_end:	.asciz	"-- end of dump --\r\n"

	.ifdef DEBUG_VERBOSE
		dbgmsg_ext2_readstats:	.asciz	"ext2_read: buf: 0x%x, LBA: 0x%lx%lx, sectors: %d\r\n"
	.endif
