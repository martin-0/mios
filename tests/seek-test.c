/* test: avoid using div when locating correct block in inode's data. */

#include <stdio.h>

#define	BLOCK_SIZE		1024

#define	BLOCK_ENTRIES		( BLOCK_SIZE >> 2)
#define	BLOCK_MASK		~( (BLOCK_ENTRIES)-1 )
#define	BLOCK_MASK_OFFSET	((BLOCK_ENTRIES)-1)


int main() { 
	int r;
	unsigned long int i, tmp;
	unsigned long int tblock, block, offset, t1,b1, o1;

	printf("block size: 0x%x, mask: %x\n", BLOCK_ENTRIES, BLOCK_MASK);

	i =0;
	while(1) { 
		i = t1=b1=o1=tblock=block=offset=0;

		printf("\n> ");
		r = scanf("%lu", &i);
		if (r == 0 || r == EOF ) break;

		if (i == 0) break;

		if (i < 12) {
			printf("%ld is in direct block, file offset: 0x%lx\n", i, i*BLOCK_SIZE);
			continue;
		}
		tmp = i-12;

		if ( tmp < BLOCK_ENTRIES ) {
			printf("%ld is in indirect block, file offset 0x%lx\n", i, i*BLOCK_SIZE);
			continue;
		}

		tmp -= BLOCK_ENTRIES;

		if (tmp < BLOCK_ENTRIES*BLOCK_ENTRIES) {
			printf("we need to split: %ld\n", tmp);
			block = tmp / BLOCK_ENTRIES;
			offset = tmp % BLOCK_ENTRIES; 

			b1 =  tmp >> 8;
			o1 = tmp & BLOCK_MASK_OFFSET;

			printf("%ld is in DIBP: double: %ld, single: %ld, file offset: 0x%lx\n", i, block, offset, i*BLOCK_SIZE);
			printf("%ld is in DIBP: double: %ld, single: %ld, file offset: 0x%lx\n", i, b1, o1, i*BLOCK_SIZE);
			continue;

		}

		tmp -= ( BLOCK_ENTRIES*BLOCK_ENTRIES);

		// 65804 and more
		if ( tmp < BLOCK_ENTRIES*BLOCK_ENTRIES*BLOCK_ENTRIES) {
			printf("we need to split: %ld\n", tmp);
			unsigned long t;

			tblock = tmp / ( BLOCK_ENTRIES*BLOCK_ENTRIES) ;
			t = tmp % ( BLOCK_ENTRIES*BLOCK_ENTRIES);
			block = t / BLOCK_ENTRIES;
			offset = t % BLOCK_ENTRIES; 

			t1 = tmp >> 16;
			t = tmp-t1;
			b1 =  ( t >> 8) & BLOCK_MASK_OFFSET;
			o1 = tmp & BLOCK_MASK_OFFSET;
			
			printf("%ld is in TIBP: triple; %ld, double: %ld, single: %ld, file offset: 0x%lx\n", i, tblock, block, offset, i*BLOCK_SIZE);
			printf("%ld is in TIBP: triple; %ld, double: %ld, single: %ld, file offset: 0x%lx\n", i, t1, b1, o1, i*BLOCK_SIZE);

			continue;
		}	
	
		printf("ETOOBIG: %lu > 16843020 \n", i);

	}


	return 42;
}	
