/* martin */

/*
	Constants used in gboot loader.
	Rather then repeating them in every source file I've created this file and put them all in.
*/

.set PAGE_SIZE, 	0x1000
.set MASK_PALIGN,       (PAGE_SIZE-1)

//.set ADDR_KERNEL_ENTRY, 0x20000
.set ADDR_KERNEL_ENTRY, 0x200000

.set GENERIC_BUFSZ,	0x1000				/* if not stated otherwise all buffers are of this size */
.set BOOT1_STACK_SP,	0x1ffc

/* GPT */
.set OFST_GPT_HDR_LBA_START,		0x48
.set OFST_GPT_HDR_NR_ENTRIES,		0x50
.set OFST_GPT_HDR_ENTRY_SZ,		0x54
.set OFST_GPT_PART_ENTRY_LBA_START,	0x20
.set OFST_GPT_PART_ENTRY_LBA_END,	0x24

/* buffers primarily used in ext2 */
.set ADDR_READBUF,	0x3000
.set ADDR_BLOCBUF,	0x4000
.set ADDR_SIBPBUF,	0x5000
.set ADDR_DIBPBUF,	0x6000
.set ADDR_TIBPBUF,	0x2000
.set ADDR_DIRNODE,	0x7000
.set ADDR_INODE,	0x7100

/* EXT2 module */
.set NAME_LEN, 255					/* max file name size */
.set PATH_MAX, 4096
.set MAX_SYMLINK_FOLLOW, 40				/* how deeep to follow symlinks */
.set FAST_SYMLINK_SIZE, 60				/* symlink's data is in its inode if len not more than FAST_SYMLINK_SIZE */

.set EXT2_MAGIC,			0xef53
.set EXT2_SIZE_LOG_UNIT,		1024		/* block size: EXT2_SIZE_LOG_UNIT << s_log_block_size */
.set EXT2_DEFAULT_INODE_SIZE,		0x80
.set EXT2_OFST_SUPERBLOCK,		0x400		/* offset from the beginning of the ext2 FS to superblock (independent of the block size) */
.set EXT2_SB_OFST_ALLBLOCKS,		4		/* s_blocks_count */
.set EXT2_SB_OSFT_LOGBS,		0x18		/* s_log_block_size */
.set EXT2_SB_OFST_BLOCK_PG,		0x20		/* s_blocks_per_group */
.set EXT2_SB_OFST_INODES_PG,		0x28		/* s_inodes_per_group */
.set EXT2_SB_OFST_MAGIC,		0x38		/* s_magic */
.set EXT2_SB_OFST_STATE,		0x3a		/* s_state */
.set EXT2_SB_OFST_ERR,			0x3c		/* s_error */
.set EXT2_SB_OSFT_REV_LEVEL,		0x4c		/* s_rev_level */
.set EXT2_SB_OFST_INODE_SZ,		0x58		/* s_inode_size */

.set SECTORSZ,				512		/* disk sector size */
.set SECTORS_IN_EXT2BUF,		8		/* statically computed from PAGE_SIZE/512 = 8; buffers are PAGE_SIZE big */

/* EXT2 error codes */
.set ETOOBIG, 1
.set ENOMAGIC, 2
.set EBSUNSUPP, 3
.set EFSPANIC, 4
.set EINODESZ, 5
.set ENOBLOCKS, 6
.set ENOBLCPG, 7
.set ENOINOPG, 8
.set EBLKINODE, 9

/* inode mode */
.set S_IFMT, 0xF000				/* mask to be used for inode.i_mode */
.set S_IFDIR, 0x4000				/* inode is a directory */
.set S_IFREG, 0x8000				/* inode is a regular file */
.set S_IFLNK, 0xa000				/* inode is a symlink */

/* inode */
.set INODE_OSFT_TYPEPERM, 0			/* inode offset to type and permissions */
.set INODE_OFST_ISIZE, 0x4			/* inode offset to i_size */
.set INODE_DIRECT_BLOCKS, 12			/* how many direct blocks inode has */
.set INODE_OFST_DBP_0, 0x28			/* inode offset to direct block pointer 0 */
.set INODE_OSFT_SIBP, 0x58			/* inode offset to single indirect block pointer */
.set INODE_OSFT_DIBP, 0x5c			/* inode offset to double indirect block pointer */
.set INODE_OSFT_TIBP, 0x60			/* inode offset to triple indirect block pointer */

/* dir inode */
.set DIR_OFST_RECLEN, 4				/* offset to reclen in directory inode */
.set EXT2_DENTRY_OFST_INODE, 0			/* offset to inode in directory entry */
.set EXT2_DENTRY_OFST_SIZE, 4			/* size of the current directory entry */
.set EXT2_DENTRY_OFST_NAMELEN, 6		/* len of the name entry */
.set EXT2_DENTRY_OFST_NAME, 8			/* name of the entry being described */

