/*XXX:	had to drop and rewrite the test from scratch due to issues with hash dirs.

	https://wiki.osdev.org/Ext2#Inode_Type_and_Permissions
	http://web.mit.edu/tytso/www/linux/ext2intro.html
	https://www.nongnu.org/ext2-doc/ext2.html
	https://www.win.tue.nl/~aeb/linux/fs/ext2/ext2.html#AEN703

NOTES:
	while not ext2 specific inode size can be as big as block size. Important thing is it can't spread on more blocks.

PROBLEMS:
	i_blocks seems to be problematic. I'm tempted to ignore it and use the following logic:
		if i_block[] is 0 skip it but continue looking up all 15 of them (0-11,12,13,14)
		if indirect block (whatever level) is 0 skip it.

	Definition of i_blocks:
	"""
		32-bit value representing the total number of 512-bytes blocks reserved to contain the data of this inode, regardless if
		these blocks are used or not. The block numbers of these reserved blocks are contained in the i_block array. 

		Since this value represents 512-byte blocks and not file system blocks, this value should not be directly used as an index to the i_block array.
		Rather, the maximum index of the i_block array should be computed from i_blocks / ((1024<<s_log_block_size)/512), or once simplified, i_blocks/(2<<s_log_block_size).
	"""

	Makes my head spin. "block" is used here to describe different things. Even for inode 2 I get the value 19 which doesn't make sense.
	Max index to i_block[] is 15 as we have DBP: 0-11, SIBP: 12, DIBP: 13, TIBP: 14


NOTES for asm:
	I can't use single buffer cache for this operation. I need to keep these separately:
		- superblock
		- current global descriptor entry
		- inode i'm working on as I need to reference at least i_block[] between reads of blocks
		- in case of indirect blocks i need to cache the entries of these too

	Question is if it makes sense to cache any blocks at all. PAGE_SIZE can hold either 4, 2 or 1 block depending on the blocksize.
	Maybe some sequentional reads can benefit from that. Will see.

	doing double and tripple indirect travelsal is not that different from the single one but it introduces
	interesting problem with the cache. yes, here it's ok just to use another bbuf to cache block data
	and continue .. in bootloader this can be a problem as i need 3 PAGE_SIZE regions to deal with it
	real problem? well .. not exactly .. i could use 0x1000-0x3000 physical for this. or maybe even some higher memory regions below 1MB
	or each return from a subroutine would read from a disk again - trading speed for memory usage

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

//#define	DEBUG	1

// block buffer
typedef struct bbuf {
	unsigned int start_bid;	// start of the cached block id
	unsigned int capacity;	// how many blocks can buffer hold
	int stat_hits;		// item in cache
	int stat_total;		// total requests
	off_t file_ofst;	// actual offset in the file
	char buf[BUFSZ];
} bbuf_t;

struct ext2_super_block	sb;
struct ext2_group_desc gde;

int blkid_gdt;					// block id of the global group descriptor table
int block_size;					// block size ( 1024 << sb.s_log_block_size )
int inodes_per_block;

void show_sblock();
void show_gde(struct ext2_group_desc* gde, int hdr);
void show_bbuf(bbuf_t* buf, int size);
void dump_memory(int* addr, int size);
void init_bbuf(bbuf_t* b);

int access_inode(int fd, int inum, struct ext2_inode* inode);
int access_gde(int fd, int inum, struct ext2_group_desc* gd_entry);
int access_block(int fd, int blkid, bbuf_t* bbf);

int read_dir_entry_nohash(bbuf_t* bbuf);
int read_dir_entry_nohash_sibp(int fd, bbuf_t* bbuf);

int search_dir(int fd, int inum, struct ext2_inode* inode, bbuf_t* bbuf, char* matchstr);
int search_dir_entry_nohash(bbuf_t* bbuf, char* matchstr);
int search_dir_entry_nohash_sibp(int fd, bbuf_t* bbuf, char* matchstr);
int search_dir_entry_nohash_dibp(int fd, bbuf_t* bbuf, char* matchstr);
int search_dir_entry_nohash_tibp(int fd, bbuf_t* bbuf, char* matchstr);

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

	block_size = 1024 << sb.s_log_block_size;
	blkid_gdt = (sb.s_log_block_size == 0) ? 2 : 1;
	inodes_per_block = block_size / sb.s_inode_size;

	show_sblock();

	struct ext2_inode inode;

	bbuf_t bbuf;
	init_bbuf(&bbuf);

	char kernel[] = "/boot/kernel";
	int inum;

	inum = 2;
	char *token = strtok(kernel, "/");

	while(token != NULL) {
		if ((access_inode(fd, inum, &inode)) != 0) {
			printf("failed to access inode %d\n", inum);
			goto out;
		}

		if (! inode.i_mode & 0x4000) {
			printf("inum %d is not a dir\n", inum);
			goto out;
		}

		// XXX: value of i_blocks just doesn't make sense to me
		//printf("** inode i_blocks: %d, max index in i_block[] is %d\n", inode.i_blocks, inode.i_blocks/(2<< sb.s_log_block_size));

		if ((inum = search_dir(fd, inum, &inode, &bbuf, token)) == 0) {
			printf("%s not found\n", token);
			goto out;
		}

		token = strtok(NULL, "/");
	}

	if ((access_inode(fd, inum, &inode)) != 0) {
		printf("failed to access inode %d\n", inum);
		goto out;
	}

	printf("kernel size: %u\n", inode.i_size);

	dump_memory((int*)&inode, 128);

	/// NOTE: this will be a job for elf parser
	if ((access_block(fd, inode.i_block[0], &bbuf)) != 0) { return -1; }
	show_bbuf(&bbuf, 128);


out:
	close(fd);
	return 0;
}

// read the dir entry node
int read_dir_entry_nohash(bbuf_t* bbuf) {
	struct ext2_dir_entry* de;
	int csize = 0;
	char tmp[256];

	while (csize < block_size) {
		de = (struct ext2_dir_entry*)(bbuf->buf+csize);
		snprintf(tmp, (de->name_len & 0xff)+1, "%s", de->name);

		printf("%d -> %s\n", de->inode, tmp);
		csize += de->rec_len;
	}
	return 0;
}

int read_dir_entry_nohash_sibp(int fd, bbuf_t* bbuf) {
	int* bp = (int*)bbuf->buf;
	int i,block_entries = block_size / sizeof(int);

	bbuf_t bbuf2;		// need somewhere to cache the individual entries
	init_bbuf(&bbuf2);

	#ifdef DEBUG
		printf("read_dir_entry_nohash_sibp: block entries in sibp: %d\n", block_entries);
	#endif

	for (i =0; i < block_entries, *bp != 0; i++) {
		#ifdef DBEUG
			printf("read_dir_entry_nohash_sibp: entry %d -> 0x%x\n", i, *bp);
		#endif

		if ((access_block(fd, *bp, &bbuf2)) != 0) { return -1; }
		read_dir_entry_nohash(&bbuf2);
		bp++;

	}
	return 0;
}

// read the directory entry, don't bother with the htree
// returns inode if found, 0 otherwise
int search_dir_entry_nohash(bbuf_t* bbuf, char* matchstr) {
	struct ext2_dir_entry* de;
	int mlen,csize;

	mlen = strlen(matchstr);
	csize = 0;
	while (csize < block_size) {
		de = (struct ext2_dir_entry*)(bbuf->buf+csize);

		if ( (mlen == (de->name_len & 0xff)) && (!strncmp(de->name, matchstr, mlen))) {
			#ifdef DEBUG
				printf("search_dir_entry_nohash: %s found: inode: 0x%x\n", matchstr, de->inode);
			#endif
			return de->inode;
		}
		csize += de->rec_len;
	}
	return 0;
}

int search_dir_entry_nohash_sibp(int fd, bbuf_t* bbuf, char* matchstr) {
	int* bp = (int*)bbuf->buf;
	int ret,i,block_entries = block_size / sizeof(int);

	bbuf_t bbuf2;	// need somewhere to cache the individual entries
	init_bbuf(&bbuf2);

	#ifdef DEBUG
		printf("search_dir_entry_nohash_sibp: block entries in sibp: %d\n", block_entries);
	#endif

	for (i =0; i < block_entries, *bp != 0; i++) {
		#ifdef DBEUG
			printf("search_dir_entry_nohash_sibp: entry %d -> 0x%x\n", i, *bp);
		#endif

		if ((access_block(fd, *bp, &bbuf2)) != 0) { return -1; }
		if (( ret = search_dir_entry_nohash(&bbuf2, matchstr)) != 0) return ret;

		bp++;

	}
	return 0;
}

int search_dir_entry_nohash_dibp(int fd, bbuf_t* bbuf, char* matchstr) {
	#ifdef DEBUG
		printf("search_dir_entry_nohash_dibp: looking for %s\n", matchstr);
	#endif

	int* bp = (int*)bbuf->buf;
	int ret,i,block_entries = block_size / sizeof(int);

	bbuf_t bbuf2;	// need somewhere to cache the individual entries
	init_bbuf(&bbuf2);

	#ifdef DEBUG
		printf("search_dir_entry_nohash_dibp: block entries in sibp: %d\n", block_entries);
	#endif

	for (i =0; i < block_entries, *bp != 0; i++) {
		#ifdef DBEUG
			printf("search_dir_entry_nohash_dibp: entry %d -> 0x%x\n", i, *bp);
		#endif

		if ((access_block(fd, *bp, &bbuf2)) != 0) { return -1; }
		if (( ret = search_dir_entry_nohash_sibp(fd, &bbuf2, matchstr)) != 0) return ret;

		bp++;

	}
	return 0;
}

int search_dir_entry_nohash_tibp(int fd, bbuf_t* bbuf, char* matchstr) {
	#ifdef DEBUG
		printf("search_dir_entry_nohash_tibp: looking for %s\n", matchstr);
	#endif

	int* bp = (int*)bbuf->buf;
	int ret,i,block_entries = block_size / sizeof(int);

	bbuf_t bbuf2;	// need somewhere to cache the individual entries
	init_bbuf(&bbuf2);

	#ifdef DEBUG
		printf("search_dir_entry_nohash_tibp: block entries in sibp: %d\n", block_entries);
	#endif

	for (i =0; i < block_entries, *bp != 0; i++) {
		#ifdef DBEUG
			printf("search_dir_entry_nohash_tibp: entry %d -> 0x%x\n", i, *bp);
		#endif

		if ((access_block(fd, *bp, &bbuf2)) != 0) { return -1; }
		if (( ret = search_dir_entry_nohash_dibp(fd, &bbuf2, matchstr)) != 0) return ret;

		bp++;

	}
	return 0;
}

// returns inode if found, 0 otherwise
int search_dir(int fd, int inum, struct ext2_inode* inode, bbuf_t* bbuf, char* matchstr) {
	struct ext2_dir_entry* de;
	int i,csize,ret;
	char tmp[256];
	int mlen = strlen(matchstr);

	#ifdef DEBUG
		printf("search_dir: looking for %s\n", matchstr);
	#endif

	for (i =0 ; i < 12; i++) {
		#ifdef DEBUG
			printf("search_dir: inode block: 0x%x\n", inode->i_block[i]);
			if (inode->i_flags & 0x1000) {
				printf("search_dir: hash index dir\n");
			}
		#endif

		// read the DBP
		if ((access_block(fd, inode->i_block[i], bbuf)) != 0) { return 0; }
		if ((ret = search_dir_entry_nohash(bbuf, matchstr)) != 0)
			return ret;
	}

	// read the single indirect block pointer and process it
	if ((access_block(fd, inode->i_block[12], bbuf)) != 0) { return 0; }
	if ((ret = search_dir_entry_nohash_sibp(fd, bbuf, matchstr)) != 0)
		return ret;

	if ((access_block(fd, inode->i_block[13], bbuf)) != 0) { return 0; }
	if ((ret = search_dir_entry_nohash_dibp(fd, bbuf, matchstr)) != 0)
		return ret;

	if ((access_block(fd, inode->i_block[14], bbuf)) != 0) { return 0; }
	if ((ret = search_dir_entry_nohash_tibp(fd, bbuf, matchstr)) != 0)
		return ret;

	return 0;
}

int access_inode(int fd, int inum, struct ext2_inode* inode) {
	// NOTE:	inode_table can spread on more blocks. i need to find the proper block offset within the inode table
	int block_group,idx,idx2,bix;

	// block_group is used as index into gdt to lookup the group metadata
	block_group = (inum-1) / sb.s_inodes_per_group;

	// inode position within the block group
	idx = (inum-1) % sb.s_inodes_per_group;

	// block index within the given group
	bix = idx / inodes_per_block;

	// inode index within the block
	idx2 = idx % inodes_per_block;

	printf("access_inode: inum %d is in block group %d, offset within block: %d, inode index %d, rel index: %d\n", inum, block_group, bix, idx, idx2);

	// find the global descriptor entry for the inum
	if ((access_gde(fd, block_group, &gde)) != 0) {
		printf("access_inode: failed to access group descriptor entry for inum: %d\n", inum);
		return -1;
	}

	bbuf_t bbuf;	// NOTE: local bbuf
	init_bbuf(&bbuf);

	// find the inode_table for given group, adjust for the block index
	if ((access_block(fd, (gde.bg_inode_table+bix), &bbuf)) != 0) { return -2; }

	// buffer holds the blocksize full of inode
	memcpy(inode, (struct ext2_inode*)(bbuf.buf)+idx2 , sizeof(*inode));
	return 0;
}

int access_block(int fd, int blkid, bbuf_t* bbf) {
	size_t rb;

	#ifdef DEBUG
		printf("access_block: block id: %d (0x%x)\n", blkid, blkid);
	#endif

	if ( (bbf->file_ofst = lseek(fd, (LBA_START*SECSZ)+(blkid*block_size), SEEK_SET)) == (off_t)-1) {
		printf("access_block: blockid: %d (0x%x): lseek failed\n", blkid, blkid);
		return -1;
	}

	if ((rb=read(fd, bbf->buf, block_size) != block_size) != rb) {
		printf("access_block: failed to read the block\n");
		return -2;
	}

	#ifdef DEBUG_ACCESS_BLOCK
		show_bbuf(bbf, 256);
	#endif

	return 0;
}

int access_gde(int fd, int bg, struct ext2_group_desc* gd_entry) {
	size_t rb;
	
	if ((lseek(fd, (LBA_START*SECSZ)+ blkid_gdt*block_size + bg*(sizeof(struct ext2_group_desc)), SEEK_SET)) == (off_t)-1) {
		printf("access_gde: block group: %d: failed to seek in file\n", bg);
		return -1;
	}

	if ((rb = read(fd, gd_entry, sizeof(struct ext2_group_desc))) != rb) {
		printf("access_gde: block group: %d: read failed\n", bg);
		return -2;
	}

	#ifdef DBEUG
		printf("access_gde: block group: %d\n", bg);
		show_gde(gd_entry,0);
	#endif

	return 0;
}

void init_bbuf(bbuf_t* b) {
	memset(b, 0, sizeof(bbuf_t));
	b->capacity = BUFSZ/block_size;
	b->start_bid = -1;
}

void show_bbuf(bbuf_t* buf, int size) {
	off_t faddr = buf->file_ofst;
	int* cur_addr = (int*)buf->buf;
        int i, chunks;

	printf( "start block id: %d\n"
		"capacity: %d\n"
		"hits: %d/%d\n", buf->start_bid, buf->capacity, buf->stat_hits, buf->stat_total);

	if (!size) return;

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
		"  block size: 0x%x (global var: 0x%x)\n"
		"  blocks per group: 0x%x\n"
		"  inodes per group: 0x%x\n"
		"  inodes per block: 0x%x\n"
		"  inode size: 0x%x\n"
		"  incompat feature: 0x%x\n"
		"  block group desc table: %d\n",
			sb.s_rev_level, sb.s_inodes_count, sb.s_blocks_count, 1024 << sb.s_log_block_size, block_size, sb.s_blocks_per_group, sb.s_inodes_per_group,
			inodes_per_block, sb.s_inode_size, sb.s_feature_incompat, blkid_gdt);
}
