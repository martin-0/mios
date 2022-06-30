/* martin */

/* Assumptions and considerations:
	LBA limit:	DAP's starting block number is 64b number. Support for this complicates things.
			I'll treat this number as 32b. This means no support for partition beyond 2TB. 

	Sector size:	Due to BIOS limitations I'll use 512B sector size as constant.

	Cache size:	cache size is static - 4096 bytes. Supported block sizes are 1024,2048,4096.
			Therefore cache can hold 4,2,1 blocks respectively.

*/

	.set EXT2_MAGIC, 0xef53
	.set EXT2_SIZE_LOG_UNIT, 1024			/* block size: EXT2_SIZE_LOG_UNIT << s_log_block_size */
	.set EXT2_DEFAULT_INODE_SIZE, 0x80

	.set EXT2_OFST_SUPERBLOCK, 0x400		/* offset from the beginning of the ext2 FS to superblock (independent of the block size) */
	.set EXT2_SB_OFST_ALLBLOCKS,4			/* s_blocks_count */
	.set EXT2_SB_OSFT_LOGBS, 0x18			/* s_log_block_size */
	.set EXT2_SB_OFST_BLOCK_PG, 0x20		/* s_blocks_per_group */
	.set EXT2_SB_OFST_INODES_PG, 0x28		/* s_inodes_per_group */
	.set EXT2_SB_OFST_MAGIC, 0x38			/* s_magic */
	.set EXT2_SB_OFST_STATE, 0x3a			/* s_state */
	.set EXT2_SB_OFST_ERR, 0x3c			/* s_error */
	.set EXT2_SB_OSFT_REV_LEVEL, 0x4c		/* s_rev_level */
	.set EXT2_SB_OFST_INODE_SZ, 0x58		/* s_inode_size */

	.set EXT2_DENTRY_OFST_INODE, 0			/* offset to inode in directory entry */
	.set EXT2_DENTRY_OFST_SIZE, 4			/* size of the current directory entry */
	.set EXT2_DENTRY_OFST_NAMELEN, 6		/* len of the name entry */
	.set EXT2_DENTRY_OFST_NAME, 8			/* name of the entry being described */

	.set BUFADDR, 0x3000				/* it's buffer for ext2 module. it's expected nobody else is writting to it. */
	.set BUFSZ, 0x1000
	.set PAGE_SIZE, 0x1000
	.set SECTORS_IN_BUF, 8				/* 4096/512 = 8 */

	/* enums */
	.set ETOOBIG, 1
	.set ENOMAGIC, 2
	.set EBSUNSUPP, 3
	.set EFSPANIC, 4
	.set EINODESZ, 5
	.set ENOBLOCKS, 6
	.set ENOBLCPG, 7
	.set ENOINOPG, 8

.section .text
	.code16


/* int16_t ext2_initmod(boot_partition *bp)
 *
*/
.global ext2_initmod
.func ext2_initmod
ext2_initmod:
	pushl %esi
	pushl %edi

	movl %eax, %esi

	/* init ext2_partition structure */
	movw $8, %cx					/* use memcpyw16 to copy lba_start and lba_end */
	movl %esi, %edx
	movl $(ext2_partition), %eax
	call memcpyw16
	movw 24(%esi), %ax				/* boot_partition->bp_bootdrive */
	movw %ax, (w_bp_disk)

	/* partition's LBA has to be in 32B limit as stated in notes above */
	movl (q_bp_lba_end+4), %eax
	test %eax, %eax
	jz .Lprepdap

	movw $(ext2_partition_toobig), %ax
	call puts16
	.ifdef DEBUG_VERBOSE
		pushw (w_bp_disk)
		pushl (q_bp_lba_end)
		pushl (q_bp_lba_end+4)
		pushl (q_bp_lba_start)
		pushl (q_bp_lba_start+4)
		pushw $(ext2_dbg_bootpartition_llx)
		call printf16
		addw $20, %sp
	.endif

	movw $ETOOBIG, %ax
	jmp .Linitm_end

.Lprepdap:
	/*
	 * Prepare the DAP for reading the superblock.
	 * These values then stay the same, only q_dap_start will change depending on blockid.
	*/
	movw $BUFADDR, (w_dap_buf)			/* set buffer */
	movw $BUFADDR, (w_bc_addr)			/* DAP and ext2 buffer are the same */
	movw $SECTORS_IN_BUF,(w_dap_sectors)		/* fill up the whole buffer */
	movl (q_bp_lba_start), %eax			/* set start LBA  */
	movl %eax, (q_dap_start)
	movl $0, (q_dap_start+4)			/* the only time when this is touched, it stays 0 always */

	.ifdef DEBUG_VERBOSE
		call dbg_ext2_show_partition
	.endif
	call ext2_read

	test %ax,%ax					/* ax is set to 1 along with errno16 in case of an error */
	jnz .Linitm_end

	movl $BUFADDR, %esi				/* buffer */
	addl $EXT2_OFST_SUPERBLOCK, %esi		/* offset to superblock */
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
	movl %eax, (l_ext2_s_blocksize)			/* save the block size */
	shrl $9, %eax					/* blocksize >> 9 = how many sectors is one block size; sector size is 512 */
	movw %ax, (w_ext2_blocksize_in_sectors)

	movl $4, %edx					/* figure out the l_bc_block_capacity */
	shrl %cl, %edx					/* edx: l_bc_block_capacity; ecx = s_log_block_size ; 4 >> s_log_block_size ; BUFSZ/1024 = 4 */

	/* unlikely but check */
	movl EXT2_SB_OFST_ALLBLOCKS(%si), %eax		/* l_ext2_s_total_blocks */
	testl %eax, %eax
	jnz .Lcheck_tb
	movw $ENOBLOCKS, %ax				/* it's expected to have some blocks on FS */
	jmp .Linitm_end	

.Lcheck_tb:
	movl %eax, (l_ext2_s_total_blocks)		/* save it */
	cmpl %eax, %edx					/* l_bc_block_capacity < l_ext2_s_total_blocks */
	jb .Lcapok
	movl %eax, (l_bc_block_capacity)		/* buffer can hold more than l_ext2_s_total_blocks, adjust it to this size then */
	jmp .Lnodesz

.Lcapok:
	movl %edx, (l_bc_block_capacity)

	/* precalculate offsets into cache */
	movl %edx, %ecx					/* block capacity */			
	movl $(w_bc_offsets), %edi			/* start of the offsets */
	xorl %eax,%eax
	movl (l_ext2_s_blocksize), %edx			/* block size */
.Lsetoffsts:
	stosw
	addw %dx, %ax
	loop .Lsetoffsts

.Lnodesz:
	movl EXT2_SB_OSFT_REV_LEVEL(%si), %eax		/* check the revision version, i.e. major version */
	movl %eax, l_ext2_s_rev_level

	testl %eax, %eax				/* handle version-dependent variables */
	jz .Lvers0

	movw EXT2_SB_OFST_INODE_SZ(%si), %ax		/* inode size can't be bigger than block size */
	cmpw %ax, (l_ext2_s_blocksize)
	jge .Linodesz.1

.Lbadinodesz:
	movw $EINODESZ, %ax
	jmp .Linitm_end

.Linodesz.1:
	testw %ax, %ax					/* return error if inode is 0 size */
	jz .Lbadinodesz

	movw %ax, (w_ext2_s_inode_size)			/* inode size ok, save it */
	jmp .Lsb_cont

.Lvers0:
	/* default inode size */
	movw $EXT2_DEFAULT_INODE_SIZE, (w_ext2_s_inode_size)

.Lsb_cont:
	movl EXT2_SB_OFST_BLOCK_PG(%si), %eax		/* l_ext2_s_blocks_per_group */
	testl %eax, %eax				/* can't be 0 */
	jnz .Lbpg_ok
	movw $ENOBLCPG, %ax
	jmp .Linitm_end

.Lbpg_ok:
	movl %eax, (l_ext2_s_blocks_per_group)		/* save l_ext2_s_blocks_per_group */
	movl EXT2_SB_OFST_INODES_PG(%si), %eax
	test %eax, %eax					/* can't be 0 */
	jnz .Lipg_ok
	movw $ENOINOPG, %ax
	jmp .Linitm_end

.Lipg_ok:
	movl %eax, (l_ext2_s_inodes_per_group)		/* save inodes per group */

	/* XXX: I should implement check on version, to see if there are features that would block me reading the FS */

	/* NOTE:
		Superblock starts 1024b from the partition start and is 1kB big.
		Depending on the block size following is in the buffer cache:

			1k block: [block 0][superblock][bgdt][block3][block4]	; block 0 was skipped by EXT2_OFST_SUPERBLOCK (1024, ie block size)
			2k block: [padding 0x400|superblock][bgdt]		; block 1 is block group descriptor table
			4k block: [padding 0x400|superblock|padding]		; gbdt is not in cache
	*/

	xorl %eax, %eax
	movl %eax, (l_bc_block_start)			/* our buffer starts at block 0 */

	cmpl $1024, (l_ext2_s_blocksize)
	jne .Lbsnot1k

	movl $2, (l_ext2_bgdt_bstart)			/* block group descriptor table starts at block id 2 */
	jmp .Lext2_clrstat

.Lbsnot1k:
	movl $1, (l_ext2_bgdt_bstart)			/* block group descriptor table starts at block id 1 */

.Lext2_clrstat:
	/* eax 0 from previous section */
	movl %eax, (l_bc_hits)				/* 0 down the statistics */
	movl %eax, (l_bc_total)

	/* fall through, eax set to 0 */
.Linitm_end:
	popl %edi
	popl %esi	
	ret
.endfunc

/* int16_t ext2_search_file(char* fname, fixme: maybe structure as 2nd param to a file ?
 *
 * CF set: error
 * return 0 - ok
*/
.global ext2_search_file
.func ext2_search_file
ext2_search_file:
	pushl %esi
	pushl %edi
	pushl %ebx


/* FIXME issues:
	Too many variables are in this function. I need to set proper stack and save it there. 
	I need to compute block_group/index for every inode i found along the path. 
	What if block group for inode table I loaded is not in cache? I need to load the next block then.. 

	I should really do this first on paper or in C to see what I should actually do .. 
*/
	


	// fixme: should be done differently
	pushl %eax					/* save fname on stack for now */

	movl $(w_bc_offsets), %ebx			/* offsets */

	/*
		block group = (inode-1)/l_ext2_s_inodes_per_group
		index = (inode-1)%l_ext2_s_inodes_per_group
	*/

	xorl %edx, %edx
	movl $1, %eax
	movl (l_ext2_s_inodes_per_group), %ecx
	div %ecx					/* block group = (inode-1)/l_ext2_s_inodes_per_group */
							/* index = (inode-1)%l_ext2_s_inodes_per_group */
	movl %eax, %esi					/* esi: block group */	
	movl %edx, %edi					/* edi: index */

	movl (l_ext2_bgdt_bstart), %eax
	call ext2_access_block
	jc .Lsf_err

	movl %eax, %edx					/* blockid addr in cache */
	movl $(ext2_group_desc), %eax			/* cache block group data */
	movl $10, %ecx
	call memcpyw16

	call dbg_ext2_show_bgt_cache	// xxx: dbg

	movl (l_bg_inode_table), %eax
	call ext2_access_block
	jc .Lsf_err

	movl %eax, %esi					/* points to the inode table */

	/* fixme: let's try this manually first */
	
	/* under inode 2 try to find "boot" */	
	movzxw (w_ext2_s_inode_size), %ecx
	leal (%esi,%ecx,1), %edi			/* index: inode -1 */

	movw (%edi), %ax				/* inode2 has to be dir */
	testw $0x4000, %ax
	jz .Lsf_err

	/* go through the 12 direct pointers */
	movl 0x28(%edi), %eax
	call ext2_access_block
	jc .Lsf_err
	movl %eax, %edi				/* edi: directory inode */

	movl $(debug_bootstr), %edx
	call ext2_search_in_dbp
	test %eax, %eax
	jz .Lsf_err

	pushl %eax	/* save eax */
	movl (l_bg_inode_table), %eax
        call ext2_access_block
	pop %eax
        jc .Lsf_err

	

	cli
	hlt


.Lsf_err:
	movw (debug_sf_err), %ax
	call puts16
	stc

.Lsf_end:

	popl %eax // fixme

	popl %ebx
	popl %edi
	popl %esi
	ret
.endfunc

/* int32_t ext2_search_in_dbp(uint32_t dbp, char* str)
 *
 * return inode location if found, 0 otherwise
*/
.global ext2_search_in_dbp
.func ext2_search_in_dbp
ext2_search_in_dbp:
	pushl %esi
	pushl %edi
	pushl %ebx
	pushl %ebp

	movl %eax,%edi					/* dbp block */
	movl %edx,%esi					/* string to find */

	movl %edx, %eax					/* do strlen(str) */
	call strlen16
	test %eax, %eax
	movzxw %ax, %ecx
	jz .Lnotfound					/* don't bother looking for empty strings */

	xorl %ebx,%ebx					/* cur position within block */

.Lld_loop:
	cmpl (l_ext2_s_blocksize), %ebx
	jge .Lnotfound

	movzxw EXT2_DENTRY_OFST_SIZE(%edi), %ebp	/* size of current entry */
	movzxb EXT2_DENTRY_OFST_NAMELEN(%edi), %edx	/* namelen of the node entry */
	cmpl %edx, %ecx					/* don't bother to compare if they are not the same len */
	jne .Ld_loop_next

	leal EXT2_DENTRY_OFST_NAME(%edi), %edx		/* s2: inode entry name */
	movl %esi, %eax					/* s1: string to find */
	push %ecx		/* save ecx */
	call strncmp16
	pop %ecx		/* restore */
	test %ax,%ax
	jz .Lfound

.Ld_loop_next:
	addl %ebp, %edi
	addl %ebp, %ebx
	jmp .Lld_loop

.Lnotfound:
	/* not found section */
	movl $(debug_notfound), %eax
	call puts16
	xorl %eax,%eax					/* return 0 */
	jmp .Lend

.Lfound:
	movl EXT2_DENTRY_OFST_INODE(%edi), %eax		/* inode val */
.Lend:
	popl %ebp
	popl %ebx
	popl %edi
	popl %esi
	ret
.endfunc

/* int16_t ext2_access_block(uint32_t blockid)
 *
 * check if blockid is in cache. if not block is read from disk. 
 *
 * CF: set: not in cache
 * otherwise: block address of the block within buffer
*/
.func ext2_access_block
ext2_access_block:
	pushl %esi
	movl %eax, %esi					/* save blockid */

	pushl %eax
	pushw $(debug_blkid)
	call printf16
	addw $6, %sp
	movl %esi, %eax

	call ext2_block_in_cache			/* check cache first */
	jnc .Lab_end

	/* cache miss */
	.ifdef DEBUG_VERBOSE
		pushl %esi
		pushw $(debug_notincache)
		call printf16
		addw $6, %sp
	.endif

	movl %esi, %eax					/* read the block */
	call ext2_readblock
	jnz .Lab_end					/* eax has address of the block if CF is not set */

	stc						/* set CF to indicate error */
.Lab_end:
	pop %esi
	ret
.endfunc



/* void* ext2_block_in_cache(uint32_t blockid)
 *
 * checks if blockid is in blockcache. 
 *
 * CF: set: not in cache
 * otherwise: block address of the block within buffer
*/
.global ext2_block_in_cache
.func ext2_block_in_cache
ext2_block_in_cache:
	pushl %esi
	pushl %edi

	incl (l_bc_total)				/* statistics update */

	movl %eax, %esi					/* blockid */
	movl (l_bc_block_start), %edi
	subl %edi, %eax					/* prepare offset to buffer: blockid-l_bc_block_start */
							/* valid only if CF is not set in the end */
	cmpl %edi, %esi					/* cache miss if blockid < l_bc_block_start */
	jb .Lbic_err

	addl (l_bc_block_capacity), %edi
	cmpl %edi, %esi
	jge .Lbic_err					/* cache miss if blockid >= l_bc_block_start+l_bc_block_capacity */

	/* we have index within block cache in eax */
	movl $(w_bc_offsets), %edx			/* offsets in buffer cache */
	leal (%edx,%eax,2), %edx			/* index into the cache */
	movzxw (%edx), %eax				/* read the offset */
	addw (w_bc_addr), %ax				/* and add to the start of the buffer; address can't be >1MB so this is ok */

	incl (l_bc_hits)				/* update cache hit */
	clc						/* clear CF */
	jmp .Lbic_end 
.Lbic_err:
	stc						/* set CF on error */
.Lbic_end:
	popl %edi
	popl %esi
	ret
.endfunc

/* void* ext2_readblock(uint32_t blockid)
 *
 * Reads blockid into buffer cache. Buffer is filled from blockid if possible.
 * It's always possible to fill up a buffer cache with blocks.
 *
 * CF set in case of an error
 * otherwise: block address of the block within buffer
*/
.func ext2_readblock
ext2_readblock:
	pushl %esi
	pushl %edi
	movl %eax,%esi					/* save blockid */
	movl %eax,%edi

	/* blockid range checks */
	movl (l_ext2_s_total_blocks), %edx
	cmpl %edx, %eax
	jge .Lrb_err					/* blockid < l_ext2_s_total_blocks */

	addl (l_bc_block_capacity), %eax		/* blockid + l_bc_block_capacity  < l_ext2_s_total_blocks */
	cmpl %edx, %eax
	jb .Lrb_calcsec

	movl %edx, %esi
	subl (l_bc_block_capacity), %esi		/* startblock: l_ext2_s_total_blocks - l_bc_block_capacity */

.Lrb_calcsec:
	subl %esi, %edi					/* position in buffer */
	movl %esi, %eax					/* start blockid */
	movzxw (w_ext2_blocksize_in_sectors), %ecx
	mul %ecx					/* offset, sectors within partition */

	addl (q_bp_lba_start), %eax			/* lba_start + blockid * w_ext2_blocksize_in_sectors */
	movl %eax, (q_dap_start)
	call ext2_read	

	test %ax,%ax					/* return in case of an error */
	jnz .Lrb_end

	pushl %esi
	pushw $(debug_rblock)
	call printf16
	addw $6, %sp

	movl %esi, (l_bc_block_start)			/* update the cache information */

	/* calculate the buffer addr of the blockid */
	movl $(w_bc_offsets), %edx			/* offsets in buffer cache */
	leal (%edx,%edi,2), %edx			/* index into the cache */
	movzxw (%edx), %eax				/* read the offset */
	addw (w_bc_addr), %ax				/* and add to the start of the buffer; address can't be >1MB so this is ok */

	clc
	jmp .Lrb_end

.Lrb_err:
	xorl %eax,%eax
	stc						/* indicate error with CF */
.Lrb_end:
	pop %edi
	pop %esi
	ret
.endfunc

/* int8_t ext2_read()
 *
 * Wrapper function around read16() from libsa16. Expects dap to be set already.
 * CF indicates error, errno16 is set. Otherwise returns 0.
*/
.func ext2_read
ext2_read:
	.ifdef DEBUG_VERBOSE
		.if DEBUG_VERBOSE > 1
			pushw (w_dap_sectors)
			pushl (q_dap_start)
			pushw (w_dap_buf)
			pushw $(dbgmsg_ext2_readstats)
			call printf16
			addw $10, %sp
		.endif
	.endif
	leaw (lba_dap), %dx
	movw (w_bp_disk), %ax
	call read16					/* errno16 and ax set in case of an error */
	ret
.endfunc

.global dbg_ext2_dumpvars
.func dbg_ext2_dumpvars
dbg_ext2_dumpvars:
	movw $(ext2_dbg_msg_start), %ax
	call puts16

	call dbg_ext2_show_dap
	call dbg_ext2_show_blockcache
	call dbg_ext2_show_partition
	call dbg_ext2_show_superblock

	movw $(ext2_dbg_msg_end), %ax
	call puts16
	ret
.endfunc

.global dbg_ext2_show_dap
.func dbg_ext2_show_dap
dbg_ext2_show_dap:
	pushl (q_dap_start)
	pushl (q_dap_start+4)
	pushw (w_dap_buf)
	pushw (w_dap_buf+2)
	pushw (w_dap_sectors)
	movzxb (lba_dap), %ax
	pushw %ax
	pushw $(ext2_dbg_dap)
	call printf16
	addw $18, %sp
	ret
.endfunc

.global dbg_ext2_show_blockcache
.func dbg_ext2_show_blockcache
dbg_ext2_show_blockcache:
	pushl (l_bc_block_capacity)
	pushl (l_bc_block_start)
	pushw (w_bc_addr)
	pushw $(ext2_dbg_blockcache)
	call printf16
	addw $12, %sp
	ret
.endfunc

.global dbg_ext2_show_partition
.func dbg_ext2_show_partition
dbg_ext2_show_partition:
	pushw (w_bp_disk)
	pushl (q_bp_lba_end)
	pushl (q_bp_lba_start)
	pushw $(ext2_dbg_bootpartition)
	call printf16
	addw $12, %sp
	ret
.endfunc

.global dbg_ext2_show_superblock
.func dbg_ext2_show_superblock
dbg_ext2_show_superblock:
	pushl (l_ext2_bgdt_bstart)
	pushw (w_ext2_s_inode_size)
	pushl (l_ext2_s_rev_level)
	pushl (l_ext2_s_inodes_per_group)
	pushl (l_ext2_s_blocks_per_group)
	pushl (l_ext2_s_total_blocks)
	pushw (w_ext2_blocksize_in_sectors)
	pushl (l_ext2_s_blocksize)
	pushw $(ext2_dbg_superblock)
	call printf16
	addw $30, %sp
	ret
.endfunc

.global dbg_ext2_show_bgt_cache
.func dbg_ext2_show_bgt_cache
dbg_ext2_show_bgt_cache:
	pushw (w_bg_used_dirs_count)
	pushw (w_bg_free_inodes_count)
	pushw (w_bg_free_blocks_count)
	pushl (l_bg_inode_table)
	pushl (l_bg_inode_bitmap)
	pushl (l_bg_block_bitmap)
	pushw $(dbg_show_bgtcache)
	call printf16
	addw $20, %sp
	ret
.endfunc

.section .data

        .align 8
		lba_dap:
				.byte 0x10	/* size of the packet */
				.byte 0		/* reserved */
		w_dap_sectors:	.word 0		/* how many LBAs to read */
		w_dap_buf:	.word 0,0	/* adress to read into */
		q_dap_start:	.quad 0		/* LBA */

	ext2_blockcache:
		l_bc_block_start:	.long 0		/* blockid start in buf */
		l_bc_block_capacity:	.long 0		/* buffer capacity in blocks */
		w_bc_addr:		.word 0		/* buf addr */
		w_bc_offsets:		.word 0,0,0,0	/* precalculated offsets */
		l_bc_hits:		.long 0		/* cache hits */
		l_bc_total:		.long 0		/* total rq */
		

	.align 4
	ext2_group_desc:				/* cache for block group descriptor entry */
		l_bg_block_bitmap:	.long 0
		l_bg_inode_bitmap:	.long 0
		l_bg_inode_table:	.long 0
		w_bg_free_blocks_count:	.word 0
		w_bg_free_inodes_count:	.word 0
		w_bg_used_dirs_count:	.word 0
		w_bg_flags:		.word 0
		.gd_pad:		.long 0,0,0	/* not used here but space kept so the struct is 32B */


	ext2_partition:
		q_bp_lba_start:	.quad 0
		q_bp_lba_end:	.quad 0
		w_bp_disk:	.word 0

	w_ext2_blocksize_in_sectors:	.word 0		/* how many sectors blocksize spreads on */

	/* superblock variables */
	.align 4
	l_ext2_bgdt_bstart:		.long 0		/* block group descriptor start */

	l_ext2_s_blocksize:		.long 0	
	l_ext2_s_total_blocks:		.long 0
	l_ext2_s_blocks_per_group:	.long 0
	l_ext2_s_inodes_per_group:	.long 0
	l_ext2_s_rev_level:		.long 0
	w_ext2_s_inode_size:		.word 0

	ext2_partition_toobig:	.asciz	"ext2: partition spreads beyond 32b lba, unsupported by this driver.\r\n"
	ext2_read_failed:	.asciz	"ext2_read: read failure: %x\r\n"
	ext2_no_magic:		.asciz	"ext2: no magic signature found.\r\n"
	ext2_bs_unsupported:	.asciz	"ext2: unsupported block size: %d\r\n"

	ext2_fs_state_unclean:	.asciz	"ext2: warning: filesystem was not unmounted properly.\r\n" 
	ext2_fs_state_okenough:	.asciz	"ext2: ok to proceed anyway, error handling code: %d\r\n"

	/* debug strings */
	ext2_dbg_msg_start:		.asciz	"\r\n-- ext2 dump of variables --\r\n"
	ext2_dbg_dap:			.asciz	"dap packet: size: %d, sectors: %d, buf: %x:%x, lba: 0x%lx%lx\r\n"
	ext2_dbg_blockcache:		.asciz	"bcache: addr: 0x%x, start block: 0x%lx, capacity: 0x%lx\r\n"
	ext2_dbg_bootpartition:		.asciz	"partition: 0x%lx - 0x%lx, disk: 0x%x\r\n"
	ext2_dbg_bootpartition_llx:	.asciz	"partition: 0x%lx%lx - 0x%lx%lx, disk: 0x%x\r\n"
	ext2_dbg_superblock:		.ascii	"superblock:\r\n"
					.ascii	"  blocksize:\t\t0x%lx\r\n"
					.ascii	"  bsize in sectors: %d\r\n"
					.ascii	"  total blocks:\t\t0x%lx\r\n"
					.ascii	"  blocks per group:\t0x%lx\r\n"
					.ascii	"  inodes per group:\t0x%lx\r\n"
					.ascii	"  revision level:\t0x%lx\r\n"
					.ascii	"  node size:\t\t0x%x\r\n"
					.asciz	"  block GDT:\t\t0x%lx\r\n"
	ext2_dbg_msg_end:		.asciz	"-- end of ext2 dump --\r\n"

	dbg_show_bgtcache:	.ascii	"gdt cache:\r\n"
				.ascii	"  block bitmap: 0x%lx\r\n"
				.ascii	"  inode bitmap: 0x%lx\r\n"
				.ascii	"  inode table: 0x%lx\r\n"
				.ascii	"  free blocks: %d\r\n"
				.ascii	"  free inodes: %d\r\n"
				.asciz	"  used dirs: %d\r\n"

	debug_delim:	.asciz "/"
	debug_strtok:	.asciz	"str: >%s<\r\n"
	debug_done:	.asciz	"out of loop\r\n"
	debug_notincache:	.asciz	"block %d not in cache.\r\n"
	debug_sf_err:	.asciz	"search_file: error\r\n"
	debug_blkid:	.asciz	"access_block: blockid: 0x%lx\r\n"
	debug_rblock:	.asciz	"ext2_readblock: start cache: 0x%lx\r\n"
	debug_bic:	.asciz	"ext2_block_in_cache: hello\r\n"

	debug_inode_entry:	.asciz	"inode: 0x%lx\t"
	debug_nl:	.asciz "\r\n"	
	debug_valx:	.asciz	"val: %x\r\n"

	.ifdef DEBUG_VERBOSE
		dbgmsg_ext2_readstats:	.asciz	"ext2_read: buf: 0x%x, LBA: 0x%lx, sectors: %d\r\n"
	.endif


	debug_bootstr:		.asciz	"boot"
	debug_kernelstr:	.asciz	"kernel"
	debug_notfound:		.asciz	"not found.\r\n"
