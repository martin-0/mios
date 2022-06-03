/*XXX:	had to drop and rewrite the test from scratch due to issues with hash dirs.

	https://wiki.osdev.org/Ext2#Inode_Type_and_Permissions
	http://web.mit.edu/tytso/www/linux/ext2intro.html
	https://www.nongnu.org/ext2-doc/ext2.html
	https://www.win.tue.nl/~aeb/linux/fs/ext2/ext2.html#AEN703

PROBLEMS:
	What happens if ext2_dir_entry->rec_len is larger than block size? can direct block pointer (DBP) step outside of the block ?
	This is the biggest issue now. Found the FS where I can't find the block leafs to do the "old" link list traversal.
	Indexed dir entry articles confused me a lot .. 

	should I stop continue if DBP in i_block[] is 0? i_blocks seems not practical
	should I stop if I find ext2_dir_entry with valid rec_len but inode is 0?

	Definition of i_blocks:
	"""
		32-bit value representing the total number of 512-bytes blocks reserved to contain the data of this inode, regardless if
		these blocks are used or not. The block numbers of these reserved blocks are contained in the i_block array. 
	"""

	Makes my head spin. "block" is used here to describe different things. Even for inode 2 I get the value 19 which doesn't make sense.

NOTES for asm:
	I can't use single buffer cache for this operation. I need to keep these separately:
		- superblock
		- current global descriptor entry
		- inode i'm working on as I need to reference at least i_block[] between reads of blocks

	Question is if it makes sense to cache any blocks at all. PAGE_SIZE can hold either 4, 2 or 1 block depending on the blocksize.
	Maybe some sequentional reads can benefit from that. Will see.

*/


#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#include <ext2fs/ext2_fs.h>

#define	BUFSZ	4096

#define	DISK		"./disk00.raw"
#define LBA_START	4096
#define	SECSZ		512

#define	EXT2_OFST_SB	1024
#define MAGIC		0xef53

// block buffer
typedef struct bbuf {
	off_t file_ofst;	// actual offset in the file
	char buf[BUFSZ];
} bbuf_t;

struct ext2_super_block	sb;
struct ext2_group_desc gde;
int blkid_gdt;

void show_sblock();
void show_gde(struct ext2_group_desc* gde, int hdr);
void show_bbuf(bbuf_t* buf, int size);
void dump_memory(int* addr, int size);

int access_gde(int fd, int inum, struct ext2_group_desc* gd_entry);
int access_block(int fd, int blkid, bbuf_t* bbf);
int read_dir(int fd, int inum, struct ext2_inode* inode, bbuf_t* bbuf, char* matchstr);

int main(int argc, char** argv) {
	char* dname = (argc == 2) ? argv[1] : DISK; 
	size_t rb;
	int fd;

	printf("using disk: %s\n", dname);

	if ((fd = open(dname, O_RDONLY)) < 0) {
		printf("failed to open %s\n", dname);
		return -1;
	}

	if ((lseek(fd, (LBA_START*SECSZ)+EXT2_OFST_SB, SEEK_SET)) == (off_t)-1) {
		printf("failed to seek to superblock\n");
		goto out;
	}

	if ((rb = read(fd, &sb, sizeof(sb))) != rb) {
		printf("failed to read the superblock\n");
		goto out;
	}

	if (sb.s_magic != MAGIC) {
		printf("ext2: magic signature not found\n");
		goto out;
	}
	
	blkid_gdt = (sb.s_log_block_size == 0) ? 2 : 1;

	show_sblock();

	struct ext2_inode inode;
	int inum, block_group,idx, bix;		// bix = block idx
	bbuf_t bbuf;


	char kernel[] = "/boot/kernel";
	char *token = strtok(kernel, "/");

	inum = 2;
	while(token != NULL) {
		// NOTE:	inode_table can spread on more blocks. i need to find the proper
		//		block offset within the inode table
		//
		//		block_inode_capacity = block_size/inode_size
		//		myblock = idx / block_inode_capacity
		//
		//		i can simplify that as ( (idx/block_size)/inode_size) = idx*inode_size/block_size
		//

		block_group = (inum-1) / sb.s_inodes_per_group;
		idx = (inum-1) % sb.s_inodes_per_group;
		bix = (idx * sb.s_inode_size)/((1024 << sb.s_log_block_size));

		printf("inum %d is in block group %d, offset within block: %d,  inode index %d\n", inum, block_group, bix, idx);

		// find the global descriptor entry for the inum
		if ((access_gde(fd, block_group, &gde)) != 0) {
			printf("failed to access group descriptor entry for inum: %d\n", inum);
			goto out;
		}

		// find the inode_table for given group, adjust for the block index
		if ((access_block(fd, (gde.bg_inode_table+bix), &bbuf)) != 0) { goto out; }

		// buffer holds the blocksize full of inode
		memcpy(&inode, (struct ext2_inode*)(bbuf.buf)+idx , sizeof(inode));

		// XXX: this check doesn't apply to last token
		if (! inode.i_mode & 0x4000) {
			printf("inum %d is not a dir\n", inum);
			goto out;
		}

		// XXX: how .. how is this possible ? Official statement about i_blocks: 
		//
		//	Since this value represents 512-byte blocks and not file system blocks, this value should not be directly used as an index to the i_block array. 
		//	Rather, the maximum index of the i_block array should be computed from i_blocks / ((1024<<s_log_block_size)/512), or once simplified, i_blocks/(2<<s_log_block_size). 
		//
		printf("** inode i_blocks: %d, max index in i_block[] is %d\n", inode.i_blocks, inode.i_blocks/(2<< sb.s_log_block_size));

		read_dir(fd, inum, &inode, &bbuf, token);


		printf("searching for %s\n", token);
		token = strtok(NULL, "/");
		_exit(42);
	}


out:
	close(fd);
	return 0;
}

int read_dir(int fd, int inum, struct ext2_inode* inode, bbuf_t* bbuf, char* matchstr) {
	struct ext2_dir_entry* de;
	int i,csize;
	char tmp[256];
	int mlen = strlen(matchstr);

	printf("read_dir: looking for %s\n", matchstr);

	for (i =0 ; i < 12; i++) {
		printf("read_dir: inode block: %x\n", inode->i_block[i]);

		if (inode->i_flags & 0x1000) {
			printf("read_dir: hash index dir\n");
		}			

		inode->i_block[i] = 0x20f;	

		// read the DBP
		if ((access_block(fd, inode->i_block[i], bbuf)) != 0) { return -1; }

		de = (struct ext2_dir_entry*)bbuf->buf;
		csize = 0;
		while (csize < 1024 << sb.s_log_block_size) {
			snprintf(tmp, (de->name_len & 0xff)+1, "%s", de->name);
			//printf("read_dir: dbp %d: rec_len: 0x%x, inode: 0x%x -> %s\n", i,de->rec_len,  de->inode, tmp);

			if ( (mlen == (de->name_len & 0xff)) && (!strncmp(de->name, matchstr, mlen))) {
				printf("read_dir: %s found: inode: 0x%x\n", matchstr, de->inode);
				_exit(2);
				break;
			}
			
			csize += de->rec_len;
			printf("current size: %d\n", csize);
		
			de = (struct ext2_dir_entry*)(bbuf->buf+csize);
		}

		_exit(42);

	}

/*
	// XXX: HA! I need to cache these this twice .. i need to have buffer for this block as i parse it i need to buffer other stuff too
	printf("inode block: %x\n", inode->i_block[12]);

	if ((access_block(fd, inode->i_block[12], bbuf)) != 0) { return -1; }

	int* iblock = bbuf->buf[0];

	while (*iblock != 0) {
		
	}	
*/

	printf("inode block: %x\n", inode->i_block[13]);
	printf("inode block: %x\n", inode->i_block[14]);
	return 0;
}

int access_block(int fd, int blkid, bbuf_t* bbf) {
	size_t rb;
	printf("access_block: block id: %d (0x%x)\n", blkid, blkid);

	if ( (bbf->file_ofst = lseek(fd, (LBA_START*SECSZ)+blkid*(1024 << sb.s_log_block_size), SEEK_SET)) == (off_t)-1) {
		printf("access_block: blockid: %d (0x%x): lseek failed\n", blkid, blkid);
		return -1;
	}

	if ((rb=read(fd, bbf->buf, 1024 << sb.s_log_block_size) != 1024 << sb.s_log_block_size) != rb) {
		printf("access_block: failed to read the block\n");
		return -2;
	}
	show_bbuf(bbf, 256);

	return 0;
}

int access_gde(int fd, int bg, struct ext2_group_desc* gd_entry) {
	size_t rb;
	
	if ((lseek(fd, (LBA_START*SECSZ)+ blkid_gdt*(1024 << sb.s_log_block_size) + bg*(sizeof(struct ext2_group_desc)), SEEK_SET)) == (off_t)-1) {
		printf("access_gde: block group: %d: failed to seek in file\n", bg);
		return -1;
	}

	if ((rb = read(fd, gd_entry, sizeof(struct ext2_group_desc))) != rb) {
		printf("access_gde: block group: %d: read failed\n", bg);
		return -2;
	}

	printf("access_gde: block group: %d\n", bg);
	show_gde(gd_entry,0);

	return 0;
}

void show_bbuf(bbuf_t* buf, int size) {
	off_t faddr = buf->file_ofst;
	int* cur_addr = (int*)buf->buf;
        int i, chunks;

        // round up chunks
        chunks = ( size + sizeof(int)-1 ) / sizeof(int);

        printf("0x%.08x", faddr);
        for(i =0, faddr+=sizeof(int) ; i < chunks; i++, faddr+=sizeof(int)) {
                printf("\t0x%.08x", *cur_addr++);
                if ((i+1)%4 == 0) {
                        printf("\n0x%.08x", faddr);
                }
        }
        puts("\n");
}

void dump_memory(int* addr, int size) {
	int* cur_addr = addr;
	int i, chunks;

	// round up chunks
	chunks = ( size + sizeof(int)-1 ) / sizeof(int);

	printf("%p", cur_addr);
	for(i =0; i < chunks; i++) {
		printf("\t0x%.08x", *cur_addr++);
		if ((i+1)%4 == 0) { printf("\n%p", cur_addr); }
	}
	puts("\n");
}

void show_gde(struct ext2_group_desc* gde, int hdr) {
	if (hdr)
		printf("global block entry:\n");

	printf( "  block bitmap: 0x%x\n"
		"  inode bitmap: 0x%x\n"
		"  inode table: 0x%x\n", gde->bg_block_bitmap, gde->bg_inode_bitmap, gde->bg_inode_table);
}

void show_sblock() {
	printf ("ext2 fs:\n"
		"  version: %d\n"
		"  inodes count: 0x%x\n"
		"  block count: 0x%x\n"
		"  block size: 0x%x\n"
		"  blocks per group: 0x%x\n"
		"  inodes per group: 0x%x\n"
		"  inode size: 0x%x\n"
		"  incompat feature: 0x%x\n"
		"  block group desc table: %d\n",
			sb.s_rev_level, sb.s_inodes_count, sb.s_blocks_count, 1024 << sb.s_log_block_size, sb.s_blocks_per_group, sb.s_inodes_per_group, sb.s_inode_size, sb.s_feature_incompat, blkid_gdt);
}
