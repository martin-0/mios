/*
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
	or each return from a subroutine would read from a disk again - trading speed for memory usage. or i could use another buf for sidp, but double and tripple lookups
	will suffer from speed as i would drop the cache..

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

#define	DEBUG			1
#define	DEBUG_BLOCK_CACHE	1

#define	PANIC_IF_ERR		1

#define	PATH_MAX		4096
#define	NAME_MAX		255
#define	FAST_SYMLINK_SIZE	60
#define	MAX_SYMLINK_FOLLOW	40

// block buffer
typedef struct bbuf {
	unsigned int start_blkid;	// start of the cached block id
	unsigned int capacity;		// how many blocks can buffer hold
	int invalid;			// state of the buffer
	int stat_hits;			// item in cache
	int stat_total;			// total requests
	off_t file_ofst;		// actual offset in the file
	char buf[BUFSZ];
} bbuf_t;

struct ext2_super_block	sb;
struct ext2_group_desc gde;

unsigned int blkid_gdt;				// block id of the global group descriptor table
int block_size;					// block size ( 1024 << sb.s_log_block_size )
int inodes_per_block;

char pathbuf[PATH_MAX];			// buffer used for path resolution
char pathbuftmp[PATH_MAX];		// used during symlink resolution
int symlink_depth;			// how many times did we try to follow symlink

void show_sblock();
void show_gde(struct ext2_group_desc* gde, int hdr);
void show_bbuf(bbuf_t* buf, int size);
void dump_memory(int* addr, int size);
void init_bbuf(bbuf_t* b);

int access_inode(int fd, int inum, struct ext2_inode* inode, bbuf_t* bbuf);
int access_gde(int fd, int inum, struct ext2_group_desc* gd_entry);
char* access_block(int fd, unsigned int blkid, bbuf_t* bbf);

int handle_symlink(int fd, struct ext2_inode* inode, bbuf_t* bbuf, char** ntoken);

int search_dir_entry(int fd, struct ext2_inode* inode, bbuf_t* bbuf, char* matchstr);
int search_dir_entry_nohash(char* buf, char* matchstr);
int search_dir_entry_nohash_sibp(int fd, char* buf, char* matchstr);
int search_dir_entry_nohash_dibp(int fd, char* buf, char* matchstr);
int search_dir_entry_nohash_tibp(int fd, char* buf, char* matchstr);

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

	if ((rb = read(fd, &sb, sizeof(sb))) != sizeof(sb) ) {
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

	struct ext2_inode inode, dirnode;
	bbuf_t bbuf;
	init_bbuf(&bbuf);
	int inum = 0;

	symlink_depth = 0;

	char kernel[] = "/boot/kernel";
	char* token, *ntoken = NULL;

	strcpy(pathbuf, kernel);
	printf("search path: %s\n", pathbuf);

	token = pathbuf;
	while(token != NULL) {

		printf("token: %s, next token: %s\n", token, ntoken);

		// access_inode() does: access_gde()->access_block()->copy_to_inode

		// read root dir
		if (token[0] == '/') {
			inum = 2;

			printf("starting with pathbuf: %s\n", pathbuf);
			if ((access_inode(fd, inum, &dirnode, &bbuf)) != 0) {
				printf("failed to access dirnode %d\n", inum);
				goto out;
			}

			if (! S_ISDIR(dirnode.i_mode)) {
				printf("oops: root inode %d is not a directory\n", inum);
				goto out;
			}
			token = strtok_r(pathbuf, "/", &ntoken);
			continue;
		}

		// assumes we have directory opened and referenced by inode
		if ((inum = search_dir_entry(fd, &dirnode, &bbuf, token)) == 0) {
			printf("%s not found\n", token);
			goto out;
		} else {
			printf("%s is in inode %d\n", token, inum);
		}

		printf("lookign up inum: %d\n", inum);
		if ((access_inode(fd, inum, &inode, &bbuf)) != 0) {
			printf("failed to access inode %d\n", inum);
			goto out;
		}

		if ( (strlen(ntoken) == 0) && S_ISREG(inode.i_mode)) {
			printf("this is is, we foudn what we were lookign for..\n");
			break;
		}

		dump_memory((int*)&inode, 128);

		printf("inode: %d mode: %x\n", inum, inode.i_mode);
		if ( S_ISDIR(inode.i_mode)) {
			printf("inum %d is a dirnode\n", inum);
			memcpy(&dirnode, &inode, sizeof(dirnode));
		} 
		else if ( S_ISLNK(inode.i_mode) ) {
			handle_symlink(fd, &inode, &bbuf, &ntoken);
			token = pathbuf;
			printf("new pathbuf: %s, token: %s, ntoken: %s\n", pathbuf, token, ntoken);
			
			if (*token == '/') continue;
		}

		token = strtok_r(NULL, "/", &ntoken);
	}

	printf("kernel size: %u\n", inode.i_size);

	dump_memory((int*)&inode, 128);

	/// NOTE: this will be a job for elf parser
	if ((access_block(fd, inode.i_block[0], &bbuf)) == NULL) { return -1; }
	show_bbuf(&bbuf, 128);

	printf("symlink_depth: %d\n", symlink_depth);

out:
	close(fd);
	return 0;
}

int handle_symlink(int fd, struct ext2_inode* inode, bbuf_t* bbuf, char** ntoken) {
	printf("handle_symlink: inode size: %d\n", inode->i_size);
	char* buf;

	if ( symlink_depth++ > MAX_SYMLINK_FOLLOW) {
		printf("handle_symlink: too many symlinks levels\n");
		#ifdef PANIC_IF_ERR
			_exit(42);
		#endif
		return 1;
	}

	if (inode->i_size < FAST_SYMLINK_SIZE) {
		buf = (char*)&inode->i_block[0];
	}
	else {
		if ((buf = access_block(fd, inode->i_block[0], bbuf)) == NULL) { return 0; }
		show_bbuf(bbuf, 128);
	}

	if (strlen(buf) > NAME_MAX) {
		printf("handle_symlink: oops: symlink name more than %d chars\n", NAME_MAX);
		#ifdef PANIC_IF_ERR
			_exit(42);
		#endif	
		return 1;
	}

	printf("handle_symlink: symlink name: %s\n", buf);


	strcpy(pathbuftmp, buf);

	if (**ntoken) {
		strcat(pathbuftmp, "/");
		strcat(pathbuftmp, *ntoken);
		*ntoken = pathbuf;
	}
	strcpy(pathbuf, pathbuftmp);

	*ntoken = pathbuf;

	// XXX: still need to take care of token

	return 0;
}

// search for matchstr in directory pointed by inode
//
// returns inum if found, 0 otherwise
int search_dir_entry(int fd, struct ext2_inode* inode, bbuf_t* bbuf, char* matchstr) {
	char* bufloc;
	int i,found_inum;

	#ifdef DEBUG
		printf("search_dir: looking for %s\n", matchstr);
	#endif

	if (! S_ISDIR(inode->i_mode)) {
		printf("search_dir_entry: not a dir inode\n");
		#ifdef PANIC_IF_ERR
			dump_memory((int*)inode, 128);
			_exit(42);
		#endif
		return 0;
	}

	for (i =0 ; i < 12; i++) {
		#ifdef DEBUG
			printf("search_dir: inode block: 0x%x\n", inode->i_block[i]);
			if (inode->i_flags & 0x1000) {
				printf("search_dir: hash index dir\n");
			}
		#endif

		// read the DBP
		if ((bufloc = access_block(fd, inode->i_block[i], bbuf)) == NULL) { return 0; }
		if ((found_inum = search_dir_entry_nohash(bufloc, matchstr)) != 0)
			return found_inum;
	}

	printf("search_dir: moving to indirect blocks\n");

	// read the single indirect block pointer and process it
	if ((bufloc = access_block(fd, inode->i_block[12], bbuf)) == NULL) { return 0; }
	if ((found_inum = search_dir_entry_nohash_sibp(fd, bufloc, matchstr)) != 0)
		return found_inum;

	// read the double indirect block pointer and process it
	if ((bufloc = access_block(fd, inode->i_block[13], bbuf)) == NULL) { return 0; }
	if ((found_inum = search_dir_entry_nohash_dibp(fd, bufloc, matchstr)) != 0)
		return found_inum;

	// read the tripple indirect block pointer and process it
	if ((bufloc = access_block(fd, inode->i_block[14], bbuf)) == NULL) { return 0; }
	if ((found_inum = search_dir_entry_nohash_tibp(fd, bufloc, matchstr)) != 0)
		return found_inum;

	return 0;
}

// searches for inode inum, if found inode structure is updated
// returns 0 if all ok, err otherwise
int access_inode(int fd, int inum, struct ext2_inode* inode, bbuf_t* bbuf) {
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

	//bbuf_t bbuf;	// NOTE: local bbuf
	//init_bbuf(&bbuf);

	char* bufloc;

	// find the inode_table for given group, adjust for the block index
	if ((bufloc = access_block(fd, (gde.bg_inode_table+bix), bbuf)) == NULL) { return -2; }

	// buffer holds the blocksize full of inode
	memcpy(inode, (struct ext2_inode*)(bufloc)+idx2 , sizeof(*inode));
	return 0;
}

char* access_block(int fd, unsigned int blkid, bbuf_t* bbf) {
	unsigned int pos, adjstart;
	size_t rb;

	#ifdef DEBUG_BLOCK_CACHE
		printf("access_block: block id: %u (0x%x)\n", blkid, blkid);
	#endif

	if (blkid > sb.s_blocks_count) {
		printf("access_block: oops: blkid %u > %u\n", blkid, sb.s_blocks_count);

		#ifdef PANIC_IF_ERR
			_exit(42);
		#endif
		return NULL;
	}

	bbf->stat_total++;

	// attempt to search in cache
	if (! bbf->invalid) {

		if (blkid <  bbf->start_blkid ) goto read_disk;
		pos = blkid - bbf->start_blkid;

		if (pos >= bbf->capacity) goto read_disk;

		#ifdef PANIC_IF_ERR
			if (pos >= bbf->capacity) {
				printf("access_block: oops: position %d outside of the boundary <0,%d>\n", pos, bbf->capacity-1);
				_exit(42);
			}
		#endif

		/*
		#ifdef DEBUG_BLOCK_CACHE
			printf("access_block: blkid %u in cache, pos %u\n", blkid, pos);
			show_bbuf(bbf, 128);
		#endif
		*/

		bbf->stat_hits++;
		return bbf->buf + block_size*pos;
	}

read_disk:
	if (blkid+bbf->capacity > sb.s_blocks_count) {
		adjstart = sb.s_blocks_count - bbf->capacity;
		printf("access_block: blockid: %u, adjstart: %u\n", blkid, adjstart);
	} else {
		adjstart = blkid;
	}

	if ( (bbf->file_ofst = lseek(fd, (LBA_START*SECSZ)+(adjstart*block_size), SEEK_SET)) == (off_t)-1) {
		printf("access_block: blockid: %u (0x%x): lseek failed\n", adjstart, adjstart);

		#ifdef PANIC_IF_ERR
			_exit(42);
		#endif
			return NULL;
	}

	if ((rb = read(fd, bbf->buf, bbf->capacity*block_size)) != bbf->capacity*block_size) {
		printf("access_block: failed to read blocks: start: %u\n", adjstart);
		#ifdef PANIC_IF_ERR
			_exit(42);
		#endif
		return NULL;
	}

	bbf->start_blkid = adjstart;
	bbf->invalid = 0;

	#ifdef DEBUG_ACCESS_BLOCK
		show_bbuf(bbf, 256);
	#endif

	return bbf->buf;
}

int access_gde(int fd, int bg, struct ext2_group_desc* gd_entry) {
	size_t rb;
	
	if ((lseek(fd, (LBA_START*SECSZ)+ blkid_gdt*block_size + bg*(sizeof(struct ext2_group_desc)), SEEK_SET)) == (off_t)-1) {
		printf("access_gde: block group: %d: failed to seek in file\n", bg);
		return -1;
	}

	if ((rb = read(fd, gd_entry, sizeof(struct ext2_group_desc))) != sizeof(struct ext2_group_desc)) {
		printf("access_gde: block group: %d: read failed\n", bg);
		return -2;
	}

	#ifdef DBEUG
		printf("access_gde: block group: %d\n", bg);
		show_gde(gd_entry,0);
	#endif

	return 0;
}

// read the directory entry, ignore htree
// buf points to a block entry
// called by search_dir_entry()
//
// returns inode if found, 0 otherwise
int search_dir_entry_nohash(char* buf, char* matchstr) {
	struct ext2_dir_entry* de;
	int mlen,csize;

	mlen = strlen(matchstr);
	csize = 0;
	while (csize < block_size) {
		de = (struct ext2_dir_entry*)(buf+csize);

		// avoid infinite loop
		if (de->rec_len == 0) {
			printf("search_dir_entry_nohash: oops: rec_len is 0: %d\n", de->rec_len);

			dump_memory((int*)buf, 128);

			#ifdef PANIC_IF_ERR
				_exit(42);
			#endif
			return 0;
		}

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

// called by search_dir_entry()
int search_dir_entry_nohash_sibp(int fd, char* buf, char* matchstr) {
	char* bufloc;
	int* bp = (int*)buf;
	int ret,i,block_entries;
	bbuf_t bbuf2;	// need somewhere to cache the individual entries

	block_entries = block_size / sizeof(int);
	init_bbuf(&bbuf2);

	#ifdef DEBUG
		printf("search_dir_entry_nohash_sibp: block entries in sibp: %d\n", block_entries);
	#endif

	for (i =0; i < block_entries; i++) {
		#ifdef DEBUG
			printf("search_dir_entry_nohash_sibp: entry %d/%d -> 0x%x\n", i, block_entries, *bp);
		#endif
		// skip over 0
		if (*bp == 0) continue;

		if ((bufloc = access_block(fd, *bp, &bbuf2)) == NULL) { return 0; }
		if ((ret=search_dir_entry_nohash(bufloc, matchstr)) != 0) return ret;

		bp++;
	}

	#ifdef DEBUG_BLOCK_CACHE
		show_bbuf(&bbuf2, 0);
	#endif
	return 0;
}

// called by search_dir_entry()
int search_dir_entry_nohash_dibp(int fd, char* buf, char* matchstr) {
	#ifdef DEBUG
		printf("search_dir_entry_nohash_dibp: looking for %s\n", matchstr);
	#endif

	char* bufloc;
	int* bp = (int*)buf;
	int ret,i,block_entries = block_size / sizeof(int);

	bbuf_t bbuf2;	// need somewhere to cache the individual entries
	init_bbuf(&bbuf2);

	#ifdef DEBUG
		printf("search_dir_entry_nohash_dibp: block entries in sibp: %d\n", block_entries);
	#endif

	for (i =0; i < block_entries; i++) {
		#ifdef DBEUG
			printf("search_dir_entry_nohash_dibp: entry %d/%d -> 0x%x\n", i, block_entries, *bp);
		#endif
		// skip over 0
		if (*bp == 0) continue;

		if ((bufloc = access_block(fd, *bp, &bbuf2)) == NULL) { return 0; }
		if ( (ret=search_dir_entry_nohash_sibp(fd, bufloc, matchstr)) != 0) return ret;

		bp++;
	}

	#ifdef DEBUG_BLOCK_CACHE
		show_bbuf(&bbuf2, 0);
	#endif
	return 0;
}

int search_dir_entry_nohash_tibp(int fd, char* buf, char* matchstr) {
	#ifdef DEBUG
		printf("search_dir_entry_nohash_tibp: looking for %s\n", matchstr);
	#endif

	char* bufloc;
	int* bp = (int*)buf;
	int ret,i,block_entries = block_size / sizeof(int);

	bbuf_t bbuf2;	// need somewhere to cache the individual entries
	init_bbuf(&bbuf2);

	#ifdef DEBUG
		printf("search_dir_entry_nohash_tibp: block entries in sibp: %d\n", block_entries);
	#endif

	for (i =0; i < block_entries;  i++) {
		#ifdef DBEUG
			printf("search_dir_entry_nohash_tibp: entry %d/%d -> 0x%x\n", i, block_entries, *bp);
		#endif
		// skip over 0
		if (*bp == 0) continue;

		if ((bufloc = access_block(fd, *bp, &bbuf2)) == NULL) { return 0; }
		if (( ret = search_dir_entry_nohash_dibp(fd, bufloc, matchstr)) != 0) return ret;

		bp++;
	}

	#ifdef DEBUG_BLOCK_CACHE
		show_bbuf(&bbuf2, 0);
	#endif
	return 0;
}


void init_bbuf(bbuf_t* b) {
	memset(b, 0, sizeof(bbuf_t));
	b->capacity = BUFSZ/block_size;
	b->invalid = 1;
}

void show_bbuf(bbuf_t* buf, int size) {
	off_t faddr = buf->file_ofst;
	int* cur_addr = (int*)buf->buf;
        int i, chunks;

	printf( "start block id: %d\n"
		"capacity: %d\n"
		"hits: %d/%d\n", buf->start_blkid, buf->capacity, buf->stat_hits, buf->stat_total);

	if (!size) return;

        // round up chunks
        chunks = ( size + sizeof(int)-1 ) / sizeof(int);

        printf("0x%.08lx", faddr);
        for(i =0, faddr+=sizeof(int) ; i < chunks; i++, faddr+=sizeof(int)) {
                printf("\t0x%.08x", *cur_addr++);
                if ((i+1)%4 == 0) {
                        printf("\n0x%.08lx", faddr);
                }
        }
        puts("\n");
}

void dump_memory(int* addr, int size) {
	int* cur_addr = addr;
	int i, chunks;

	// round up chunks
	chunks = ( size + sizeof(int)-1 ) / sizeof(int);

	printf("%p", (void*)cur_addr);
	for(i =0; i < chunks; i++) {
		printf("\t0x%.08x", *cur_addr++);
		if ((i+1)%4 == 0) { printf("\n%p", (void*)cur_addr); }
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
