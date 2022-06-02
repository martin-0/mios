/*XXX:	had to drop and rewrite the test from scratch due to issues with hash dirs.

	https://wiki.osdev.org/Ext2#Inode_Type_and_Permissions
	http://web.mit.edu/tytso/www/linux/ext2intro.html
	https://www.nongnu.org/ext2-doc/ext2.html
	https://www.win.tue.nl/~aeb/linux/fs/ext2/ext2.html#AEN703

PROBLEMS:
	What happens if ext2_dir_entry->rec_len is larger than block size? can direct block pointer (DBP) step outside of the block ?
	This is the biggest issue now. Found the FS where I can't find the block leafs to do the "old" link list traversal.
	Indexed dir entry articles confused me a lot .. 

	should I stop continue if DBP in i_blocks[] is 0? i_blocks seems not practical
	should I stop if I find ext2_dir_entry with valid rec_len but inode is 0?

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
	off_t file_ofst;
	char buf[BUFSZ];
} bbuf_t;

struct ext2_super_block	sb;
struct ext2_group_desc gde;
int blkid_gdt;

void show_sblock();
void show_gde(struct ext2_group_desc* gde, int hdr);
void show_bbuf(bbuf_t* buf, int size);

int access_gde(int fd, int inum, struct ext2_group_desc* gd_entry);
int access_block(int fd, int blkid, bbuf_t* bbf);

int main(int argc, char** argv) {
	char* dname = (argc == 2) ? argv[1] : DISK; 
	size_t rb;
	int fd;

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

	int block_group,idx;
	block_group = 1 / sb.s_inodes_per_group;
	idx = 1 % sb.s_inodes_per_group;

	// locate inode 2
	if ((access_gde(fd, block_group, &gde)) != 0) {
		printf("failed to access node 2\n");
		goto out;
	}
	bbuf_t buf;

	if ((access_block(fd, gde.bg_inode_table, &buf)) != 0) {
		goto out;
	}

	// buffer holds the inode list of blocksize
	struct ext2_inode* inode = (struct ext2_inode*)(buf.buf)+idx;

	if (! inode->i_mode & 0x4000) {
		printf("root inode is not dir, huh?\n");
		goto out;
	}

	// XXX: full rewrite .. tested the seek manually to the first dir index
	if ((access_block(fd, 0x205, &buf)) != 0) { goto out; }

out:
	close(fd);
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
