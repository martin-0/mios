/* martin */

/* Assumptions and considerations:

	LBA limit:	DAP's starting block number is 64b number. Support for this complicates things.
			I'll treat this number as 32b. This means no support for partition beyond 2TB. 

	Sector size:	Due to BIOS limitations I'll use 512B sector size as constant.

	Block buffer:	Set to 4096 bytes. Supported block sizes are 1024,2048 and 4096. At least one
			block will always fit the block buffer.
			Currently no caching is used, block is always being read from disk by access_block()

	Buffers used in the module:
	---------------------------
	I opted for fixed buffer addresses to simplify use of extended read/DAP (requires segmented address).
	During the boot1 we have set the following:
		- all segments are 0
		- %sp starts at 0x1ffc

		tidpbuf[4096]	0x2000 - 0x2fff		in case of need to go through tripple indirect blocks
		readbuf[4096]	0x3000 - 0x3fff		used in regular reads
		blocbuf[4096]	0x4000 - 0x4fff		buffer to hold read blocks
		sidpbuf[4096]	0x5000 - 0x5fff		in case of need to go through single indirect blocks
		didpbuf[4096]	0x6000 - 0x6fff		in case of need to go through double indirect blocks

	Standard inode size is 0x80. I'll allocate twice that much for it just in case:
		inode		0x7000 - 0x70ff
		dirnode		0x7100 - 0x71ff

	To handle symlinks I need temporary space to copy data over. During this operation indirect block buffers
	are free and can be used to move the data around.


   XXX: maybe too much 16/32 asm mixing ?
   XXX: check if all errors are handled properly and dealth with
   XXX: make all functions description follow the same layout

*/
	.set ADDR_TIBPBUF, 0x2000
	.set ADDR_READBUF, 0x3000
	.set ADDR_BLOCBUF, 0x4000
	.set ADDR_SIBPBUF, 0x5000
	.set ADDR_DIBPBUF, 0x6000
	.set ADDR_INODE,0x7000
	.set ADDR_DIRNODE, 0x7100

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

	.set INODE_OFST_ISIZE, 0x4			/* inode offset to i_size */
	.set INODE_OFST_DBP_0, 0x28			/* inode offset to direct block pointer 0 */
	.set INODE_OSFT_SIBP, 0x58			/* inode offset to single indirect block pointer */
	.set INODE_OSFT_DIBP, 0x5c			/* inode offset to double indirect block pointer */
	.set INODE_OSFT_TIBP, 0x60			/* inode offset to triple indirect block pointer */

	/* inode mode */
	.set S_IFMT, 0xF000				/* mask to be used for inode.i_mode */
	.set S_IFDIR, 0x4000				/* inode is a directory */

	.set NAME_LEN, 255				/* max name size */
	.set MAX_PATH, 4096
	.set MAX_SYMLINK_FOLLOW, 40			/* how deeep to follow symlinks */
	.set FAST_SYMLINK_SIZE, 60			/* symlink's data is in its inode if len not more than FAST_SYMLINK_SIZE */

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
	movl $ADDR_READBUF, %ecx
	movl $SECTORS_IN_BUF, %edx
	movl (q_part_lba_start), %eax			/* set start LBA of partition */

	.ifdef DEBUG_VERBOSE
		call dbg_ext2_show_partition
	.endif
	call ext2_readdisk

	test %ax,%ax					/* ax is set to 1 along with errno16 in case of an error */
	jnz .Linitm_end

	/* check the ext2 signature first */
	movl $ADDR_READBUF, %esi
	addl $EXT2_OFST_SUPERBLOCK, %esi		/* offset to superblock */
	cmpw $EXT2_MAGIC, EXT2_SB_OFST_MAGIC(%si)
	je .Lmagic_ok
	
	movw $(ext2_init_nomagic), %ax			/* partition doesn't have magic word, rejecting to continue */
	call puts16
	movw $ENOMAGIC, %ax				/* set error code */
	jmp .Linitm_end

.Lmagic_ok:
	/* check the ext2 fs state */
	movl EXT2_SB_OFST_STATE(%esi), %eax		/* loads 2B s_state and 2B s_error at the same time */
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

	/* unlikely but check */
	movl EXT2_SB_OFST_ALLBLOCKS(%si), %eax		/* l_ext2_sb_blocks_count */
	testl %eax, %eax
	jnz .Lcheck_tb
	movw $ENOBLOCKS, %ax				/* it's expected to have some blocks on FS */
	jmp .Linitm_end	

.Lcheck_tb:
	movl %eax, (l_ext2_sb_blocks_count)		/* save it */

	/* XXX: check the version and verify if I can use it as read-only */

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
	movw $EBLKINODE, %ax
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

	/* figure out the 2^n exponent of the inode size; used in acces_inode() */
	movl (w_ext2_sb_inode_size), %eax
	bsr %ax, %cx
	movw %cx, (w_ext2_inode_size_exp)

	/* NOTE:
		Superblock starts 1024b from the partition start and is 1kB big.
		Depending on the block size following is in the buffer cache:

			1k block: [block 0][superblock][bgdt][block3][block4]	; block 0 was skipped by EXT2_OFST_SUPERBLOCK (1024, ie block size)
			2k block: [padding 0x400|superblock][bgdt]		; block 1 is block group descriptor table
			4k block: [padding 0x400|superblock|padding]		; gbdt is not in cache
	*/

	cmpl $1024, (l_ext2_sb_blocksize)
	jne .Lbsnot1k

	movl $2, (l_ext2_bgdt_bstart)			/* block group descriptor table starts at block id 2 */
	jmp .Lgbdt_lba

.Lbsnot1k:
	movl $1, (l_ext2_bgdt_bstart)			/* block group descriptor table starts at block id 1 */

.global .Lgbdt_lba
.Lgbdt_lba:
	movzxw (w_ext2_blocksize_in_sectors), %eax	/* blocksize_in_sectors * bgdt_start = LBA of the bgdt start from partition start */
	movl (l_ext2_bgdt_bstart), %ecx
	xorl %edx, %edx
	mull %ecx

	addl (q_part_lba_start), %eax			/* add the LBA partition start to get the absolute LBA start */
	movl %eax, (l_ext2_bgdt_lba_start)

	xorl %eax, %eax
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

	movl $ADDR_BLOCBUF, %ecx
	movl $ADDR_DIRNODE, %edx
	movl $2, %eax
	call ext2_access_inode			/* 0 on success */
	test %eax, %eax
	jnz .Ldebugend

	jmp .Ltmp2
		tmp2str: .asciz "boot"
		tmp3str: .asciz "kernel"
	.Ltmp2:
	movl $ADDR_BLOCBUF, %ecx
	movw $(tmp2str), %dx
	movl $ADDR_DIRNODE, %eax
	call ext2_search_dir_entry		/* ptr on success */
	test %eax,%eax
	jz .Ldebugend

	movl $ADDR_BLOCBUF, %ecx
	movl $ADDR_DIRNODE, %edx		/* boot found */
	call ext2_access_inode			/* 0 on success */
	test %eax, %eax
	jnz .Ldebugend

	movl $ADDR_BLOCBUF, %ecx
	movw $(tmp3str), %dx
	movl $ADDR_DIRNODE, %eax
	call ext2_search_dir_entry		/* ptr on success */
	jz .Ldebugend

	movl $ADDR_BLOCBUF, %ecx
	movl $ADDR_INODE, %edx
	call ext2_access_inode			/* 0 on success */
	test %eax, %eax
	jnz .Ldebugend

	movl $ADDR_BLOCBUF, %ecx
	movl $ADDR_INODE,%ebx
	movl INODE_OFST_DBP_0(%edx), %eax	/* block0 of ELF */
	call ext2_access_block

	call puts16

	movl $ADDR_BLOCBUF, %eax
	movl $16, %edx
	call dump_mem16

	jmp .Ldloop

.Ldebugend:
	pushw %ax
	pushw $a
	call printf16
.Ldloop:
	hlt
	jmp .Ldloop
	a: .asciz "FAIL: %x\r\n"
	ret
.endfunc

/* int ext2_handle_symlink(struct* inode, char* token)
 *
 * resolve the symlink and continue with the path resolution
 *
 * returns: 0 if OK
*/
.global ext2_handle_symlink
.func ext2_handle_symlink
ext2_handle_symlink:
	pushl %esi
	pushl %edi

	movl %eax, %esi					/* esi: inode */
	movl %edx, %edi					/* edi: token */

	movzxb (b_ext2_symlink_depth), %cx
	inc %cl
	movb %cl, (b_ext2_symlink_depth)
	cmpw $MAX_SYMLINK_FOLLOW, %cx
	jae .Lhs_lim_err

	/* check if the name size fits the FAST_SYMLINK */
	movl INODE_OFST_ISIZE(%esi), %eax		/* inode size */
	cmp $FAST_SYMLINK_SIZE, %eax			/* check if symlink name is in data */
	jae .Lhs_ab					/* or if access_block() is required */

	/* symlink name is in inode's data */
	leal INODE_OFST_DBP_0(%esi), %eax
	jmp .Lhs_update_path

.Lhs_ab:
	/* check the blockid where name is stored */
	movl INODE_OFST_DBP_0(%esi), %eax
	movl $ADDR_BLOCBUF, %edx
	call ext2_access_block
	jz .Lhs_err

.Lhs_update_path:
	/* eax has pointer to the new name */
	movl $ADDR_TIBPBUF, %edx			/* use ADDR_TIBPBUF as tmppathbuf */
	call strcpy32

	movl $(ext2_path_delim), %edx			/* eax points to the dst */
	call strcat32

	// XXX: TODO: finish up, we need the rest of the path (token) to be copied over here

	xorl %eax,%eax
	jmp .Lhs_lim_end

	/* generic error */
.Lhs_err:
	inc %eax
	jmp .Lhs_lim_end

	/* max symlink depth reached */
.Lhs_lim_err:
	pushw %cx
	pushw $(ext2_handle_symlink_err)
	call printf16
	addw $4, %sp

	xorl %eax, %eax
	incw %ax

.Lhs_lim_end:
	popl %edi
	popl %esi
	ret
.endfunc


/* int ext2_search_dir_entry(struct* inode, char* matchstr, char* blockbuf)
 *
 * returns inode of matchstr
 * returns 0 if matchstr not found
*/
.global ext2_search_dir_entry
.func ext2_search_dir_entry
ext2_search_dir_entry:
	pushl %ebx
	pushl %esi
	pushl %edi
	pushl %ebp
	movl %esp, %ebp
	subl $20, %esp

	movl %edx, %edi					/* edi: matchstr */
	movl %ecx, -8(%ebp)				/* block buf */
	movl $0, -4(%ebp)				/* i variable */

	.ifdef DEBUG_VERBOSE
		pushl %eax
		pushl %ecx
		pushw %dx
		pushw $(ext2_search_dir_entry_msg)
		call printf16
		addw $2, %sp
		popw %dx
		popl %ecx
		popl %eax
	.endif

	/* check if the inode is directory */
	movl %eax, %esi					/* esi: inode */
	movw (%esi), %ax
	andw $S_IFMT, %ax
	cmpw $S_IFDIR, %ax
	je .Lsde_isdir

	/* can't proceed with inode is not a directory */
	movw $(ext2_search_dir_entry_err), %ax
	call puts16
	xorl %eax, %eax
	jmp .Lsde_end

.Lsde_isdir:
	movl %esi, %ebx					/* start of direct block pointer */
	addl $INODE_OFST_DBP_0, %ebx

.Lsde_search_blocks:
	/* loop all 12 block entries */
	movl -8(%ebp),%edx
	movl (%ebx), %eax				/* block id */
	call ext2_access_block
	test %ax, %ax
	jnz .Lsde_search_blocks.abok

	pushl (%ebx)					/* display error and return 0 */
	pushw $(ext2_search_dir_entry_err2)
	call printf16
	addw $6, %sp

	xorl %eax, %eax
	jmp .Lsde_end

.Lsde_search_blocks.abok:
	/* eax points to the bufcache location */
	movl %edi, %edx
	call ext2_search_dir_entry_nohash
	test %eax, %eax
	jnz .Lsde_end					/* we found the inode, it's in ax, return */

	/* keep looking */
	addl $4, %ebx
	incw -4(%ebp)					/* i variable */
	cmpw $12, -4(%ebp)
	jb .Lsde_search_blocks

	/* direct blocks search didn't yield any results, need to check indirect ones */

	/* SIBP */
	.ifdef DEBUG_VERBOSE
		movw $(ext2_search_dir_entry_msg_sidp), %ax
		call puts16
	.endif

	/* Here we used ADDR_BLOCBUF that holds the entries for ext2_search_dir_entry_nohash_sibp().
	   This function needs to use its own buffer for access_block()
	 */
	movl -8(%ebp), %edx				/* block buffer ADDR_BLOCKBUF */
	movl INODE_OSFT_SIBP(%esi), %eax
	call ext2_access_block				/* returns ptr to buf if ok */
	test %eax, %eax
	jz .Lsde_end
	movl %edi, %edx
	call ext2_search_dir_entry_nohash_sibp
	test %eax, %eax
	jnz .Lsde_end

	/* DIBP */
	movl -8(%ebp), %edx				/* block buffer ADDR_BLOCBUF */
	movl INODE_OSFT_DIBP(%esi), %eax
	call ext2_access_block				/* returns ptr to buf if ok */
	test %eax, %eax
	jz .Lsde_end
	movl %edi, %edx
	call ext2_search_dir_entry_nohash_dibp
	test %eax, %eax
	jnz .Lsde_end

	/* TIBP */
	movl -8(%ebp), %edx				/* block buffer ADDR_BLOCBUF */
	movl INODE_OSFT_TIBP(%esi), %eax
	call ext2_access_block				/* returns ptr to buf if ok */
	test %eax, %eax
	jz .Lsde_end
	movl %edi, %edx
	call ext2_search_dir_entry_nohash_tibp
	test %eax, %eax
	jnz .Lsde_end

	xorl %eax,%eax		/* we searched it all and didn't find it */

.Lsde_end:
	addl $20, %esp
	popl %ebp
	popl %edi
	popl %esi
	popl %ebx
	ret
.endfunc

/* int ext2_search_dir_entry_nohash_sibp(char* buf, char* matchstr)
 *
 * search matchstr in single indirect data block
 *
 * returns: inode if OK, 0 otherwise
*/
.global ext2_search_dir_entry_nohash_sibp
.func ext2_search_dir_entry_nohash_sibp
ext2_search_dir_entry_nohash_sibp:
	pushl %esi
	pushl %edi
	pushl %ebx
	pushl %ebp

	movl %eax, %esi					/* esi: block cache where search is done */
	movl %edx, %edi					/* edi: matchstr */

	/* determine how many block ids fit to blocksize */
	movl (l_ext2_sb_blocksize), %eax		/* block_size/sizeof(int32t) */
	shr $2, %eax

	pushw %ax
	pushw $(ext2_block_entries_in_blocksize_msg)
	call printf16
	addw $4, %sp

	movl %eax, %ebp					/* block_entries */
	xorl %ebx, %ebx					/* current entry, "i" */

	/* go through each indirect entry */
.Lsden_sibp_loop:
	cmp %ebp, %ebx
	jnb .Lsden_sibp_not_found			/* we went through all entries and didn't find it */

	movl (%esi), %eax				/* current block id */
	movl $ADDR_SIBPBUF, %edx			/* use ADDR_SIBPBUF as new block buffer */
	call ext2_access_block
	test %eax,%eax					/* should return pointer to a block */
	jz .Lsden_sibp_end				/* finish if error */

	movl %edi, %edx
	call ext2_search_dir_entry_nohash
	test %eax, %eax
	jnz .Lsden_sibp_end				/* we found the entry */

	addl $4, %esi					/* move to next block */
	inc %ebx					/* i++ */
	jmp .Lsden_sibp_loop

.Lsden_sibp_not_found:
	xorl %eax,%eax

.Lsden_sibp_end:
	popl %ebp
	popl %ebx
	popl %edi
	popl %esi

	ret
.endfunc

/* int ext2_search_dir_entry_nohash_dibp(char* buf, char* matchstr)
 *
 * search matchstr in double indirect data block
 *
 * returns: inode if OK, 0 otherwise
*/
.global ext2_search_dir_entry_nohash_dibp
.func ext2_search_dir_entry_nohash_dibp
ext2_search_dir_entry_nohash_dibp:
	pushl %esi
	pushl %edi
	pushl %ebx
	pushl %ebp

	movl %eax, %esi					/* esi: block cache where search is done */
	movl %edx, %edi					/* edi: matchstr */

	/* determine how many block ids fit to blocksize */
	movl (l_ext2_sb_blocksize), %eax		/* block_size/sizeof(int32t) */
	shr $2, %eax

	pushw %ax
	pushw $(ext2_block_entries_in_blocksize_msg)
	call printf16
	addw $4, %sp

	movl %eax, %ebp					/* block_entries */
	xorl %ebx, %ebx					/* current entry, "i" */

	/* go through each indirect entry */
.Lsden_dibp_loop:
	cmp %ebp, %ebx
	jnb .Lsden_dibp_not_found			/* we went through all entries and didn't find it */

	movl (%esi), %eax				/* current block id */
	movl $ADDR_DIBPBUF, %edx			/* use ADDR_DIBPBUF as new block buffer */
	call ext2_access_block
	test %eax,%eax					/* should return pointer to a block */
	jz .Lsden_dibp_end				/* finish if error */

	movl %edi, %edx
	call ext2_search_dir_entry_nohash_sibp
	test %eax, %eax
	jnz .Lsden_dibp_end				/* we found the entry */

	addl $4, %esi					/* move to next block */
	inc %ebx					/* i++ */
	jmp .Lsden_dibp_loop

.Lsden_dibp_not_found:
	xorl %eax,%eax

.Lsden_dibp_end:
	popl %ebp
	popl %ebx
	popl %edi
	popl %esi

	ret
.endfunc

/* int ext2_search_dir_entry_nohash_tibp(char* buf, char* matchstr)
 *
 * search matchstr in tripple indirect data block
 *
 * returns: inode if OK, 0 otherwise
*/
.global ext2_search_dir_entry_nohash_tibp
.func ext2_search_dir_entry_nohash_tibp
ext2_search_dir_entry_nohash_tibp:
	pushl %esi
	pushl %edi
	pushl %ebx
	pushl %ebp

	movl %eax, %esi					/* esi: block cache where search is done */
	movl %edx, %edi					/* edi: matchstr */

	/* determine how many block ids fit to blocksize */
	movl (l_ext2_sb_blocksize), %eax		/* block_size/sizeof(int32t) */
	shr $2, %eax

	pushw %ax
	pushw $(ext2_block_entries_in_blocksize_msg)
	call printf16
	addw $4, %sp

	movl %eax, %ebp					/* block_entries */
	xorl %ebx, %ebx					/* current entry, "i" */

	/* go through each indirect entry */
.Lsden_tibp_loop:
	cmp %ebp, %ebx
	jnb .Lsden_tibp_not_found			/* we went through all entries and didn't find it */

	movl (%esi), %eax				/* current block id */
	movl $ADDR_TIBPBUF, %edx			/* use ADDR_TIBPBUF as new block buffer */
	call ext2_access_block
	test %eax,%eax					/* should return pointer to a block */
	jz .Lsden_tibp_end				/* finish if error */

	movl %edi, %edx
	call ext2_search_dir_entry_nohash_dibp
	test %eax, %eax
	jnz .Lsden_tibp_end				/* we found the entry */

	addl $4, %esi					/* move to next block */
	inc %ebx					/* i++ */
	jmp .Lsden_tibp_loop

.Lsden_tibp_not_found:
	xorl %eax,%eax

.Lsden_tibp_end:
	popl %ebp
	popl %ebx
	popl %edi
	popl %esi

	ret
.endfunc

/* int ext2_search_dir_entry_nohash(char* buf, char* matchstr)
 *
 * search the directory entry, ignore hash tree if it exists
 *
 * returns:	inode of matched string
 * err: 	0
 */
.global ext2_search_dir_entry_nohash
.func ext2_search_dir_entry_nohash
ext2_search_dir_entry_nohash:
	pushl %esi
	pushl %edi
	pushl %ebx
	pushl %ebp

	movl %eax, %esi				/* esi: buf */
	movl %edx, %edi				/* edi: matchstr */

	movl %edx, %eax				/* strlen(matchstr) */
	call strlen16
	movl %eax, %ebp				/* ebp: matchstr len */

	xorl %ebx, %ebx				/* csize */
.Lsden_mainloop:
	cmpl %ebx,(l_ext2_sb_blocksize)
	jb .Lsden_nofound

	/* to avoid infinite loop check the size of the direntry */
	cmpl $0, 4(%esi,%ebx)			/* it can't be 0 */
	jnz .Lsden_mainloop_csizeok

	movw $(ext2_search_dir_entry_nohash_err), %ax
	call puts16
	jmp .Lsden_nofound

.Lsden_mainloop_csizeok:
	movzxb 6(%esi,%ebx), %cx		/* dir len */

	cmp %cx, %bp				/* skip the entry if its size is not the same */
	jne .Lsden_keepgoing			/* as matchstr len */

	movw %di, %dx
	leaw 8(%esi,%ebx), %ax
/*
	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw $(ext2_search_dir_entry_nohash_debug)
		call printf16
		addw $2, %sp
		popw %ax
	.endif
*/
	call strncmp16
	test %ax,%ax
	jz .Lsden_found

.Lsden_keepgoing:
	addw 4(%esi,%ebx), %bx
	jmp .Lsden_mainloop

.Lsden_nofound:
	xorl %eax,%eax
	jmp .Lsden_end

.Lsden_found:
	movl (%esi,%ebx), %eax					/* inode */
	.ifdef DEBUG_VERBOSE
		pushl %eax
		pushl %eax
		pushw %di
		pushw $(ext2_search_dir_entry_nohash_found)
		call printf16
		addw $8, %sp
		popl %eax
	.endif

.Lsden_end:
	popl %ebp
	popl %ebx
	popl %edi
	popl %esi
	ret
.endfunc


/* int ext2_access_inode(int inum, struct* inode, char* blockbuf)
 *
 * figures out the location of the inode on disk, copies the inode to inode structure
 * when found. uses blockbuf to store access_block() data
 *
 * returns 0: OK
*/
.global ext2_access_inode
.func ext2_access_inode
ext2_access_inode:
	pushl %esi
	pushl %edi
	pushl %ebp
	movl %esp, %ebp
	subl $20, %esp

	test %eax,%eax						/* inum can't be 0 */
	jnz .Lai_not0
	sete %al

	.ifdef DEBUG_VERBOSE
		pushl %eax
		movw $(ext2_access_inode_msg_err2), %ax
		call puts16
		popl %eax
	.endif
	jmp .Lai_end

.Lai_not0:

	movl %eax, %edi						/* save inum for later */
	movl %edx, %esi						/* save struct* inode for later */
	movl %ecx, -16(%ebp)					/* block buffer */

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
		pushw $(ext2_access_inode_msg)
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

.global .Lai_agok
.Lai_agok:
	movl (l_bg_inode_table), %eax			/* l_bg_inode_table + bix */
	addl -8(%ebp), %eax
	movl -16(%ebp), %edx				/* block buffer */
	call ext2_access_block
	test %ax,%ax
	jz .Lai_end

.Lai_abok:
	/* eax points to the buffer of read inodes, idx2 indexes it to the correct one */
	movw (w_ext2_inode_size_exp), %cx		/* use precomputed exponent of the inode size */
	movl -12(%ebp), %edx				/* idx2 */
	shll %cl, %edx
	addl %eax, %edx					/* offset to inode I'm looking for */
	movl %esi, %eax
	movw (w_ext2_sb_inode_size), %cx
	call memcpy16
	xorl %eax,%eax					/* indicate success */
.Lai_end:
	addl $20, %esp
	popl %ebp
	popl %edi
	popl %esi
	ret
.endfunc

/* int ext2_access_gde(int32 bg)
 *
 * access blocks group descriptor by its id
 * uses defualt ADDR_READBUF to store its data
 *
 * return 0 if OK
*/
.global ext2_access_gde
.func ext2_access_gde
ext2_access_gde:
	pushl %edi
	pushl %ebx
	movl %eax, %ebx						/* save for later */

	.ifdef DEBUG_VERBOSE
		pushl %eax
		pushw $(ext2_dbg_access_gde_msg0)
		call printf16
		addw $6,%sp
	.endif

	/* LBA of the blockid: (blkdid*group_desc_sz)/512 + LBA_global_descriptor_table */
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
	movl $ADDR_READBUF, %ecx
	call ext2_readdisk
	jc .Lag_end

	/* copy the read entry into ext2_group_desc */
	addl $ADDR_READBUF, %edi				/* add offset to the buffer we read blocks in */
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


/* char* access_block(unsigned int blockid, char* buf)
 *
 * reads the block of a given blockid into buffer
 *
 * returns address of a block when read is successfull.
 * NULL otherwise
*/
.global ext2_access_block
.func ext2_access_block
ext2_access_block:
	.ifdef DEBUG_EXT2
		pushw %dx
		pushl %eax
		pushw $(ext2_dbg_access_block_msg)
		call printf16
		popw %ax				/* dummy pop */
		popl %eax				/* restore eax */
		popw %dx
	.endif

	movl (l_ext2_sb_blocks_count), %ecx
	cmpl %ecx, %eax
	ja .Lab_oor					/* block out of range */

.Lab_doread:
	/* LBA to seek to: ext2_LBA_start + blkid * block_size_in_sectors */
	movw %dx, (w_dap_buf)				/* set the appropriate buffer location */

	xorl %edx,%edx
	movzxw (w_ext2_blocksize_in_sectors), %ecx	/* blockid * w_ext2_blocksize_in_sectors */
	mull %ecx

	addl (q_part_lba_start), %eax			/* add the result to the start of the partition */
	movl %eax, (q_dap_start)
	movw $SECTORS_IN_BUF, (w_dap_sectors)

	.ifdef DEBUG_EXT2
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
	movzxw (w_dap_buf), %eax			/* address used for read is still saved in DAP */
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

.global dbg_ext2_show_gbdt
.func dbg_ext2_show_gbdt
dbg_ext2_show_gbdt:
	pushw (w_bg_used_dirs_count)
	pushw (w_bg_free_inodes_count)
	pushw (w_bg_free_blocks_count)
	pushl (l_bg_inode_table)
	pushl (l_bg_inode_bitmap)
	pushl (l_bg_block_bitmap)
	pushw $(dbg_show_gbdt_msg)
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

	lba_dap:
				.byte 0x10	/* size of the packet */
				.byte 0		/* reserved */
		w_dap_sectors:	.word 0		/* how many LBAs to read */
		w_dap_buf:	.word 0,0	/* adress to read into */
		q_dap_start:	.quad 0		/* LBA */


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
	w_ext2_inode_size_exp:		.word 0		/* inode size has to be power of 2; save the exponent */

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

	b_ext2_symlink_depth:		.byte 0		/* how many itterations did we do handling symlink already */

	/* ext2_init_module() */
	ext2_init_part_toobig:		.asciz	"ext2: partition spreads beyond 32b lba, unsupported by this driver.\r\n"
	ext2_init_nomagic:		.asciz	"ext2: no magic signature found.\r\n"
	ext2_init_bsize_unsupported:	.asciz	"ext2: unsupported block size: %d\r\n"
	ext2_init_fs_state_unclean:	.asciz	"ext2: warning: filesystem was not unmounted properly.\r\n" 
	ext2_init_fs_state_okenough:	.asciz	"ext2: ok to proceed anyway, error handling code: %d\r\n"

	/* ext2_access_block() */
	ext2_dbg_access_block_msg:	.asciz	"access_block: searching for blkid: 0x%lx, buf: 0x%x\r\n"
	ext2_access_block_lba:		.asciz	"access_block: accessing LBA 0x%lx\r\n"
	ext2_access_block_oor:		.asciz	"oops: access_block: block 0x%lx out of range (0x%lx)\r\n"

	/* ext2_ext2_access_gde() */
	ext2_dbg_access_gde_msg0:	.asciz	"access_gde: searching for blockid: 0x%lx\r\n"
	ext2_dbg_access_gde_msg:	.asciz	"access_gde: LBA: 0x%lx, blockgroup: %d, offset: 0x%lx\r\n"

	/* ext2_access_inode() */
	ext2_access_inode_msg:		.asciz	"access_inode: inum %d is in block group %d, offset within block: %d, inode index %d, rel index: %d\r\n"
	ext2_access_inode_msg_err:	.asciz	"access_inode: failed to access group descriptor entry for inum: %d\r\n"
	ext2_access_inode_msg_err2:	.asciz	"access_inode: invalid inum 0\r\n"

	/* ext2_search_dir_entry() */
	ext2_search_dir_entry_msg:	.asciz	"search_dir_entry: search for %s, buf: 0x%lx\r\n"
	ext2_search_dir_entry_msg_sidp:	.asciz	"search_dir_entry: proceeding to SIDP\r\n"
	ext2_search_dir_entry_err:	.asciz	"search_dir_entry: inode not a directory\r\n"
	ext2_search_dir_entry_err2:	.asciz	"search_dir_entry: failed to access block 0x%lx\r\n"

	/* ext2_search_dir_entry_nohash() */
	ext2_search_dir_entry_nohash_err:	.asciz	"search_dir_entry_nohash: oops: dir entry size is 0\r\n"
	ext2_search_dir_entry_nohash_found:	.asciz	"search_dir_entry_nohash: %s found: inode: 0x%lx\r\n"
	ext2_search_dir_entry_nohash_debug:	.asciz	"search_dir_entry_nohash: comparing: %s\r\n"

	/* ext2_handle_symlink() */
	ext2_handle_symlink_err:	.asciz	"handle_symlink: too many levels of symbolic links: %d\r\n"

	/* generic */
	ext2_block_entries_in_blocksize_msg:	.asciz	"block entries in blocksize: %d\r\n"

	/* debug strings */
	ext2_dbg_msg_start:		.asciz	"\r\n-- ext2 dump of variables --\r\n"
	ext2_dbg_dap:			.asciz	"dap packet: size: %d, sectors: %d, buf: %x:%x, lba: 0x%lx%lx\r\n"
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

	dbg_show_gbdt_msg:	.ascii	"global bdt:\r\n"
				.ascii	"  block bitmap: 0x%lx\r\n"
				.ascii	"  inode bitmap: 0x%lx\r\n"
				.ascii	"  inode table: 0x%lx\r\n"
				.ascii	"  free blocks: %d\r\n"
				.ascii	"  free inodes: %d\r\n"
				.asciz	"  used dirs: %d\r\n"

	.ifdef DEBUG_VERBOSE
		dbgmsg_ext2_readdiskstats:	.asciz	"ext2_readdisk: buf: 0x%x, LBA: 0x%lx, sectors: %d\r\n"
	.endif

	/* character used to split path with */
	ext2_path_delim:	.asciz	"/"

.section .bss
	/* buffer to hold the path that is being searched. */
	pathbuf:	.skip	MAX_PATH
