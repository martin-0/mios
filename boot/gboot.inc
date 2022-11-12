/* martin */

/*
	Constants used in gboot loader. Rather then repeating them in every source file
	I've created this file and put them all in.
*/

	/* ext2 related offsets */

	/* buffers primarily used in ext2 */
        .set ADDR_TIBPBUF,	0x2000
        .set ADDR_READBUF,	0x3000
        .set ADDR_BLOCBUF,	0x4000
        .set ADDR_SIBPBUF,	0x5000
        .set ADDR_DIBPBUF,	0x6000
        .set ADDR_DIRNODE,	0x7000
        .set ADDR_INODE,	0x7100

	/* ext2 specific constants */
        .set INODE_OSFT_TYPEPERM, 0			/* inode offset to type and permissions */
        .set INODE_OFST_ISIZE, 0x4			/* inode offset to i_size */
        .set INODE_OFST_DBP_0, 0x28			/* inode offset to direct block pointer 0 */
        .set INODE_OSFT_SIBP, 0x58			/* inode offset to single indirect block pointer */
        .set INODE_OSFT_DIBP, 0x5c			/* inode offset to double indirect block pointer */
        .set INODE_OSFT_TIBP, 0x60			/* inode offset to triple indirect block pointer */
        .set DIR_OFST_RECLEN, 4				/* offset to reclen in directory inode */

        .set EXT2_DENTRY_OFST_INODE, 0			/* offset to inode in directory entry */
        .set EXT2_DENTRY_OFST_SIZE, 4			/* size of the current directory entry */
        .set EXT2_DENTRY_OFST_NAMELEN, 6		/* len of the name entry */
        .set EXT2_DENTRY_OFST_NAME, 8			/* name of the entry being described */