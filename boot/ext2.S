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

	.set SECTORSZ, 512				/* disk sector size */
	.set BUFSZ, 0x1000
	.set PAGE_SIZE, 0x1000
	.set SECTORS_IN_BUF, 8				/* statically computed from BUFSZ/512 = 8 */

	/* enums */
	.set ETOOBIG, 1
	.set ENOMAGIC, 2
	.set EBSUNSUPP, 3
	.set EFSPANIC, 4
	.set EINODESZ, 5
	.set ENOBLOCKS, 6
	.set ENOBLCPG, 7
	.set ENOINOPG, 8
	.set EBLKINODE, 9

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
	movl (q_part_lba_end+4), %eax
	test %eax, %eax
	jz .Lprepdap

	movw $(ext2_init_part_toobig), %ax
	call puts16
	.ifdef DEBUG_VERBOSE
		pushw (w_bp_disk)
		pushl (q_part_lba_end)
		pushl (q_part_lba_end+4)
		pushl (q_part_lba_start)
		pushl (q_part_lba_start+4)
		pushw $(ext2_dbg_bootpartition_llx)
		call printf16
		addw $20, %sp
	.endif

	movw $ETOOBIG, %ax
	jmp .Linitm_end

.Lprepdap:
	/* we can't use access_block yet, we need superblock first */
	movl $(readbuf), %ecx
	movl $SECTORS_IN_BUF, %edx
	movl (q_part_lba_start), %eax			/* set start LBA of partition */

	.ifdef DEBUG_VERBOSE
		call dbg_ext2_show_partition
	.endif
	call ext2_readdisk

	test %ax,%ax					/* ax is set to 1 along with errno16 in case of an error */
	jnz .Linitm_end

	/* check the ext2 signature first */
	movl $(readbuf), %esi
	addl $EXT2_OFST_SUPERBLOCK, %esi		/* offset to superblock */
	cmpw $EXT2_MAGIC, EXT2_SB_OFST_MAGIC(%si)
	je .Lmagic_ok
	
	movw $(ext2_init_nomagic), %ax			/* partition doesn't have magic word, rejecting to continue */
	call puts16
	movw $ENOMAGIC, %ax				/* set error code */
	jmp .Linitm_end

.Lmagic_ok:
	/* check the ext2 fs state */
	movl EXT2_SB_OFST_STATE(%si), %eax		/* loads 2B s_state and 2B s_error at the same time */
	cmpw $1, %ax					/* 1: VALID_FS, 2: ERROR_DETECTED */
	je .Lbsize					/* OK to proceed with valid FS */

	pushl %eax					/* inform about the unclean FS */
	movl $(ext2_init_fs_state_unclean), %eax
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
		pushw $(ext2_init_fs_state_okenough)
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
		pushw $(ext2_init_bsize_unsupported)
		call printf16
		addw $4, %sp
	.endif

	movw $EBSUNSUPP, %ax
	jmp .Linitm_end

.Lbs_ok:
	movl %eax, (l_ext2_sb_blocksize)		/* save the block size */
	shrl $9, %eax					/* blocksize >> 9 = how many sectors is one block size; sector size is 512 */
	movw %ax, (w_ext2_blocksize_in_sectors)

	movl $4, %edx					/* figure out the l_bc_block_capacity */
	shrl %cl, %edx					/* edx: l_bc_block_capacity; ecx = s_log_block_size ; 4 >> s_log_block_size ; BUFSZ/1024 = 4 */

	/* unlikely but check */
	movl EXT2_SB_OFST_ALLBLOCKS(%si), %eax		/* l_ext2_sb_blocks_count */
	testl %eax, %eax
	jnz .Lcheck_tb
	movw $ENOBLOCKS, %ax				/* it's expected to have some blocks on FS */
	jmp .Linitm_end	

.Lcheck_tb:
	movl %eax, (l_ext2_sb_blocks_count)		/* save it */
	cmpl %eax, %edx					/* l_bc_block_capacity < l_ext2_sb_blocks_count */
	jb .Lcapok
	movl %eax, (l_bc_block_capacity)		/* buffer can hold more than l_ext2_sb_blocks_count, adjust it to this size then */
	jmp .Lnodesz

.Lcapok:
	movl %edx, (l_bc_block_capacity)

	// TODO: drop this maybe

	/* precalculate offsets into cache */
	movl %edx, %ecx					/* block capacity */			
	movl $(w_bc_offsets), %edi			/* start of the offsets */
	xorl %eax,%eax
	movl (l_ext2_sb_blocksize), %edx		/* block size */
.Lsetoffsts:
	stosw
	addw %dx, %ax
	loop .Lsetoffsts

.Lnodesz:
	movl EXT2_SB_OSFT_REV_LEVEL(%si), %eax		/* check the revision version, i.e. major version */
	movl %eax, (l_ext2_sb_rev_level)
	testl %eax, %eax				/* handle version-dependent variables */
	jz .Lvers0

	movw EXT2_SB_OFST_INODE_SZ(%si), %ax		/* inode size can't be bigger than block size */
	cmpw %ax, (l_ext2_sb_blocksize)
	jge .Linodesz.1

.Lbadinodesz:
	movw $EINODESZ, %ax
	jmp .Linitm_end

.Linodesz.1:
	testw %ax, %ax					/* return error if inode is 0 size */
	jz .Lbadinodesz
	movw %ax, (w_ext2_sb_inode_size)		/* inode size ok, save it */
	jmp .Lsb_cont

.Lvers0:
	/* default inode size */
	movw $EXT2_DEFAULT_INODE_SIZE, (w_ext2_sb_inode_size)

.Lsb_cont:
	/* compute inodes_per_block */
	movl (l_ext2_sb_blocksize), %eax		/* inodes_per_block = l_ext2_sb_blocksize/w_ext2_sb_inode_size */
	movzxw (w_ext2_sb_inode_size), %ecx
	xorl %edx,%edx
	div %ecx
	test %edx, %edx					/* we should not have any leftover by this division */
	jz .Lipb_ok
	movl $EBLKINODE, %eax
	jmp .Linitm_end

.Lipb_ok:
	movl %eax, (l_ext2_inodes_per_block)
	movl EXT2_SB_OFST_BLOCK_PG(%si), %eax		/* l_ext2_sb_blocks_per_group */
	testl %eax, %eax				/* can't be 0 */
	jnz .Lbpg_ok
	movw $ENOBLCPG, %ax
	jmp .Linitm_end

.Lbpg_ok:
	movl %eax, (l_ext2_sb_blocks_per_group)		/* save l_ext2_sb_blocks_per_group */
	movl EXT2_SB_OFST_INODES_PG(%si), %eax
	test %eax, %eax					/* can't be 0 */
	jnz .Lipg_ok
	movw $ENOINOPG, %ax
	jmp .Linitm_end

.Lipg_ok:
	movl %eax, (l_ext2_sb_inodes_per_group)		/* save inodes per group */

	/* precompute floor of the inode_size to speed up lookups in access_inode */
.global .Lhint1
.Lhint1:
	movl (w_ext2_sb_inode_size), %eax
	bsr %ax, %cx
	movw %cx, (w_ext2_inode_size_floor)

	/* XXX: I should implement check on version, to see if there are features that would block me reading the FS */

	/* NOTE:
		Superblock starts 1024b from the partition start and is 1kB big.
		Depending on the block size following is in the buffer cache:

			1k block: [block 0][superblock][bgdt][block3][block4]	; block 0 was skipped by EXT2_OFST_SUPERBLOCK (1024, ie block size)
			2k block: [padding 0x400|superblock][bgdt]		; block 1 is block group descriptor table
			4k block: [padding 0x400|superblock|padding]		; gbdt is not in cache
	*/

	// XXX: right now I have two variables:
	//	l_bc_block_start	blockid where gdt is
	//	l_ext2_bgdt_lba_start	lba where gdt starts

	// this is a prep work for ext2_access_gde() that requires LBA only .. i should probably drop the other variable completely
	//

	xorl %edx, %edx					/* finish buffer cache setup */
	movl %edx, (l_bc_block_start)			/* our buffer starts at block 0 */

	movl (l_ext2_sb_blocksize), %eax		/* blocksize / 512 = LBAs */
	movw $SECTORSZ, %cx
	div %cx

	addl (q_part_lba_start), %eax
	movl %eax, (l_ext2_bgdt_lba_start)

	cmpl $1024, (l_ext2_sb_blocksize)		/* XXX: I'm keeping it for now but I think I don't need it */
	jne .Lbsnot1k

	movl $2, (l_ext2_bgdt_bstart)			/* block group descriptor table starts at block id 2 */
	jmp .Lext2_clrstat

.Lbsnot1k:
	movl $1, (l_ext2_bgdt_bstart)			/* block group descriptor table starts at block id 1 */

.Lext2_clrstat:
	xorl %eax, %eax
	movl %eax, (l_bc_hits)				/* 0 down the statistics */
	movl %eax, (l_bc_total)

	/* fall through, eax set to 0 */
.Linitm_end:
	popl %edi
	popl %esi	
	ret
.endfunc

/* XXX: for now: dummy function called from boot1 to test ext2 module */
.global ext2_search_file
.func ext2_search_file
ext2_search_file:
	call dbg_ext2_show_superblock

	movl $(dirnode), %edx
	movl $2, %eax
	call ext2_access_inode

	//call dbg_ext2_show_bgt_cache

	movl $dirnode, %eax
	movl $64, %edx
	call dump_mem16

	cli
	hlt
	ret
.endfunc

/* int ext2_access_inode(int inum, struct* inode)
 *
*/
.global ext2_access_inode
.func ext2_access_inode
ext2_access_inode:
	pushl %esi
	pushl %edi
	pushl %ebp
	movl %esp, %ebp

	subl $16, %esp

	movl %eax, %edi						/* save inum for later */
	movl %edx, %esi						/* save struct* for later */

	/* block group is used as index into int global descriptor table to lookup group's  metadata */
	dec %eax
	xorl %edx,%edx
	movl (l_ext2_sb_inodes_per_group), %ecx			/* block_group = (inum-1) / sb.s_inodes_per_group */
	div %ecx						/* idx = (inum-1) % sb.s_inodes_per_group */

	movl %eax, (%ebp)					/* save block_group */
	movl %edx, -4(%ebp)					/* save idx */

	/* compute the block index within given group */
	movl %edx, %eax						/* eax:  idx */
	xorl %edx, %edx
	movl (l_ext2_inodes_per_block), %ecx
	div %ecx

	movl %eax, -8(%ebp)					/* bix: block index */
	movl %edx, -12(%ebp)					/* idx2: inode index within block */

	.ifdef DEBUG_VERBOSE
		pushw %dx
		pushw -4(%ebp)
		pushw %ax
		pushw (%ebp)
		pushw %di
		pushw $(ext2_access_inode_msg)		/* ext2_access_inode: inum %d is in block group %d, offset within block: %d, inode index %d, rel index: %d\r\n" */
		call printf16
		addw $12, %sp
	.endif

	movl (%ebp), %eax
	call ext2_access_gde

	test %ax, %ax
	jz .Lai_agok

	pushw %ax
	pushw %di
	pushw $(ext2_access_inode_msg_err)
	call printf16
	addw $4, %sp
	popw %ax					/* error from ext2_access_gde */
	jmp .Lai_end

.Lai_agok:
	movl (l_bg_inode_table), %eax			/* l_bg_inode_table + bix */
	addl -8(%ebp), %eax
	call ext2_access_block
	test %ax,%ax
	jnz .Lai_abok

	xorl %eax,%eax					/* while errno is set i'm not displaying any error here */
	jmp .Lai_end					/* jump to end */

.Lai_abok:
	/* eax points to the buffer of read inodes, idx2 index it to the correct one */
	movw (w_ext2_inode_size_floor), %cx		/* use precomputed floor of the inode size */
	movl -12(%ebp), %edx				/* idx2 */
	shll %cl, %edx
	addl %eax, %edx					/* offset to inode I'm looking for */
	movl %esi, %eax
	movw (w_ext2_sb_inode_size), %cx
	call memcpy16

.Lai_end:
	addl $16, %esp
	popl %ebp
	popl %edi
	popl %esi
	ret
.endfunc

/* int ext2_access_gde(int32 bg)
 *
 * access blocks group descriptor by its id
 *
 * return 0 if OK
*/
.global ext2_access_gde
.func ext2_access_gde
ext2_access_gde:
	pushl %edi
	pushl %ebx

	movl %eax, %ebx						/* save for later */

	/* compute LBA where the given block group resides: ( block_group*sizeof(ext2_group_desc) ) /512
	 * reminder is the offset within read sector */
	xorl %edx,%edx
	movw $ext2_sz_group_desc, %cx
	mul %cx
	movw $SECTORSZ, %cx
	div %cx

	movl %edx, %edi						/* offset within given LBA */
	addl (l_ext2_bgdt_lba_start), %eax

        .ifdef DEBUG_VERBOSE
		pushl %edx
		pushw %bx
		pushl %eax
		pushw $(ext2_dbg_access_gde_msg)
		call printf16
		addw $12, %sp
	.endif

	/* readdisk(LBA where block_group id resides, nr of sectors, buf) */
	movl $1, %edx
	movw $readbuf, %cx
	call ext2_readdisk
	jc .Lag_end

	/* copy the read entry into ext2_group_desc */
	addl $readbuf, %edi					/* add offset to the buffer we read blocks in */
	movl %edi, %edx
	movw $ext2_sz_group_desc, %cx				/* sizeof(ext2_group_desc) */
	movw $(ext2_group_desc), %ax				/* ext2_group_desc */
	call memcpy16
	xorl %eax, %eax
.Lag_end:
	popl %ebx
	popl %edi
	ret
.endfunc


/* char* access_block(unsigned int blockid)
 *
 * reads the block of given id. if cache is used check block cache first.
 *
 * returns address of a block when read is successfull.
 * NULL otherwise
*/
.global ext2_access_block
.func ext2_access_block
ext2_access_block:
	.ifdef DEBUG_VERBOSE
		pushl %eax
		pushw $(ext2_dbg_access_block_msg)
		call printf16
		addw $2, %sp
		popl %eax				/* restore eax */
	.endif

	movl (l_ext2_sb_blocks_count), %edx
	cmpl %edx, %eax
	ja .Lab_oor					/* block out of range */

	incl (l_bc_total)				/* increase stat counters */

	cmpw  $0, (w_bc_valid_cache)
	jz .Lab_doread

	// TODO: handle cache
	jmp .Ltmp1
		tmpnocache: .asciz "bcache not yet implemented\r\n"
	.Ltmp1:
		pushl %eax
		movw $(tmpnocache), %ax
		call puts16
		popl %eax


.Lab_doread:
	/* LBA to seek to: ext2_LBA_start + blkid * block_size_in_sectors */
	movl %eax, (l_bc_block_start)

	xorl %edx,%edx
	movzxw (w_ext2_blocksize_in_sectors), %ecx
	mull %ecx
	addl (q_part_lba_start), %eax
	movl %eax, (q_dap_start)

	movw $SECTORS_IN_BUF, (w_dap_sectors)
	movw $bcbuf, (w_dap_buf)

	.ifdef DEBUG_VERBOSE
		pushl %eax
		pushw $(ext2_access_block_lba)
		call printf16
		addw $6, %sp
	.endif

        leaw (lba_dap), %dx
        movw (w_bp_disk), %ax
        call diskread16					/* errno16 and ax set in case of an error */

	test %ax, %ax
	jz .Lab_readok
	xor %eax, %eax
	jmp .Lab_end

.Lab_readok:

	setae (w_bc_valid_cache)

	/* XXX: right now we don't have cache so we return the buf address */
	movl $bcbuf, %eax
	jmp .Lab_end

.Lab_oor:
	/* blockid out of range */
	pushl %edx
	pushl %eax
	pushw $(ext2_access_block_oor)
	call printf16
	addw $10, %sp
	xorl %eax,%eax
.Lab_end:
	ret
.endfunc


/* int8_t ext2_readdisk(int lba, int blocks, char* buf)
 *
 * reads the blocks from lba into buf. buf has to have space to read the data
 *
 * CF indicates error, errno16 is set. Otherwise returns 0.
*/
.func ext2_readdisk
ext2_readdisk:
	movw %cx, (w_dap_buf)
	movw %dx, (w_dap_sectors)
	movl %eax, (q_dap_start)

	.ifdef DEBUG_VERBOSE
		.if DEBUG_VERBOSE > 1
			pushw (w_dap_sectors)
			pushl (q_dap_start)
			pushw (w_dap_buf)
			pushw $(dbgmsg_ext2_readdiskstats)
			call printf16
			addw $10, %sp
		.endif
	.endif
	leaw (lba_dap), %dx
	movw (w_bp_disk), %ax
	call diskread16					/* errno16 and ax set in case of an error */
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
	pushw (w_bc_bufaddr)
	pushw $(ext2_dbg_blockcache)
	call printf16
	addw $12, %sp
	ret
.endfunc

.global dbg_ext2_show_partition
.func dbg_ext2_show_partition
dbg_ext2_show_partition:
	pushw (w_bp_disk)
	pushl (q_part_lba_end)
	pushl (q_part_lba_start)
	pushw $(ext2_dbg_bootpartition)
	call printf16
	addw $12, %sp
	ret
.endfunc

.global dbg_ext2_show_superblock
.func dbg_ext2_show_superblock
dbg_ext2_show_superblock:
	pushl (l_ext2_bgdt_lba_start)
	pushl (l_ext2_bgdt_bstart)
	pushw (w_ext2_sb_inode_size)
	pushl (l_ext2_sb_rev_level)
	pushl (l_ext2_sb_inodes_per_group)
	pushl (l_ext2_sb_blocks_per_group)
	pushl (l_ext2_sb_blocks_count)
	pushw (w_ext2_blocksize_in_sectors)
	pushl (l_ext2_sb_blocksize)
	pushw $(ext2_dbg_superblock)
	call printf16
	addw $34, %sp
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
	ext2_partition:
		q_part_lba_start:	.quad 0
		q_part_lba_end:		.quad 0
		w_bp_disk:		.word 0


	// XXX: can't have one DAP being used for different purposes, aka bufread..
	lba_dap:
				.byte 0x10	/* size of the packet */
				.byte 0		/* reserved */
		w_dap_sectors:	.word 0		/* how many LBAs to read */
		w_dap_buf:	.word 0,0	/* adress to read into */
		q_dap_start:	.quad 0		/* LBA */

	/* block cache */
	ext2_blockcache:
		l_bc_block_start:	.long 0		/* blockid start in buf */
		l_bc_block_capacity:	.long 0		/* buffer capacity in blocks */
		w_bc_valid_cache:	.word 0		/* state of the cahce: 0: invalid, anything else: ok */
		w_bc_bufaddr:		.word bcbuf	/* buf addr */
		w_bc_offsets:		.word 0,0,0,0	/* precalculated offsets */
		l_bc_hits:		.long 0		/* cache hits */
		l_bc_total:		.long 0		/* total rq */
		l_bc_phys_ofst:		.long 0		/* physical offset into the disk where cache begins */


	.align 4
	/* excert from superblock structure ext2_super_block */
	l_ext2_sb_blocksize:		.long 0
	l_ext2_sb_blocks_count:		.long 0
	l_ext2_sb_blocks_per_group:	.long 0
	l_ext2_sb_inodes_per_group:	.long 0
	l_ext2_sb_rev_level:		.long 0
	w_ext2_sb_inode_size:		.word 0

	/* superblock related variables to speed up calculations */
	l_ext2_bgdt_bstart:		.long 0		/* block group descriptor start */
	w_ext2_blocksize_in_sectors:	.word 0		/* how many sectors (LBA) blocksize spreads on */
	l_ext2_bgdt_lba_start:		.long 0		/* LBA where global group descriptor starts */
	l_ext2_inodes_per_block:	.long 0		/* how many inodes are there per block */
	w_ext2_inode_size_floor:	.word 0		/* inode size has to be power of 2; floor of that number */

	/* struct ext2_group_desc */
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
	ext2_sz_group_desc = . - ext2_group_desc	/* keep the sizeof(ext2_group_desc) */



	/* ext2_init_module() */
	ext2_init_part_toobig:		.asciz	"ext2: partition spreads beyond 32b lba, unsupported by this driver.\r\n"
	ext2_init_nomagic:		.asciz	"ext2: no magic signature found.\r\n"
	ext2_init_bsize_unsupported:	.asciz	"ext2: unsupported block size: %d\r\n"
	ext2_init_fs_state_unclean:	.asciz	"ext2: warning: filesystem was not unmounted properly.\r\n" 
	ext2_init_fs_state_okenough:	.asciz	"ext2: ok to proceed anyway, error handling code: %d\r\n"

	/* ext2_access_block() */
	ext2_dbg_access_block_msg:	.asciz	"ext2_access_block: blkid: 0x%lx\r\n"
	ext2_access_block_oor:		.asciz	"oops: ext2_access_block: block 0x%lx out of range (0x%lx)\r\n"
	ext2_access_block_lba:		.asciz	"ext2_access_block: accessing LBA 0x%lx\r\n"

	/* ext2_ext2_access_gde() */
	ext2_dbg_access_gde_msg:	.asciz	"ext2_access_gde: LBA: 0x%lx, blockgroup: %d, offset: 0x%lx\r\n"

	/* ext2_access_inode() */
	ext2_access_inode_msg:		.asciz	"ext2_access_inode: inum %d is in block group %d, offset within block: %d, inode index %d, rel index: %d\r\n"
	ext2_access_inode_msg_err:	.asciz	"ext2_access_inode: failed to access group descriptor entry for inum: %d\r\n"


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
					.ascii	"  block GDT:\t\t0x%lx\r\n"
					.asciz	"  LBA GDT:\t\t\t0x%lx\r\n"

	ext2_dbg_msg_end:		.asciz	"-- end of ext2 dump --\r\n"

	dbg_show_bgtcache:	.ascii	"gdt cache:\r\n"
				.ascii	"  block bitmap: 0x%lx\r\n"
				.ascii	"  inode bitmap: 0x%lx\r\n"
				.ascii	"  inode table: 0x%lx\r\n"
				.ascii	"  free blocks: %d\r\n"
				.ascii	"  free inodes: %d\r\n"
				.asciz	"  used dirs: %d\r\n"

	.ifdef DEBUG_VERBOSE
		dbgmsg_ext2_readdiskstats:	.asciz	"ext2_readdisk: buf: 0x%x, LBA: 0x%lx, sectors: %d\r\n"
	.endif

	showbufaddr: .asciz	"bcbuf: %x, readbuf: %x\r\n"

.section .bss
	.align 4
	/* buffer allocated for block cache */
	.global bcbuf
	bcbuf:		.skip	BUFSZ

	/* generic buffer reserved for read operation */
	.global readbuf
	readbuf:	.skip	BUFSZ

	// XXX: is this how we want to do this ?
	.global inode
	inode:	.skip	2*EXT2_DEFAULT_INODE_SIZE

	.global dirnode
	dirnode:.skip	2*EXT2_DEFAULT_INODE_SIZE
