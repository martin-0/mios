#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

#define	MAX_PMBR_CODE		0x1be			/* pmbr code should not be more than this */
#define	PART1_BOOTFLAG		( (MAX_PMBR_CODE) + 1 )

int fd = -1;
int fd2 = -1;

void __attribute__((destructor)) cleanup() { if(fd >= 0) close(fd); if(fd2 >= 0) close(fd2); } 

int main(int argc, char** argv) { 
	if (argc != 3) {
		printf("parameter missing: %s: <diskimage> <pmbr>\n", argv[0]);
		return 1;
	}

	size_t rb;

	/* open the disk */	
	if ((fd = open(argv[1], O_RDWR)) < 0) {
		perror("failed to open diskimage file");
		return 2;
	}

	/* open the pmbr file */
	if ((fd2 = open(argv[2], O_RDONLY)) < 0) {
		perror("failed to open pmbr file");
		return 3;
	}

	/* load the current pmbr */
	char buf[512];
	if ((rb = read(fd, buf, 512)) != 512) {
		perror("read diskimage");
		return 4;
	}

	/* load the new pmbr */	
	if ((rb = read(fd2, buf, PART1_BOOTFLAG)) != PART1_BOOTFLAG) {		// XXX: sgdisk was not able to set this on GPT, using it this way
		perror("read pmbr");
		return 4;
	}
		
	/* rewind */
	if ((lseek(fd, 0, SEEK_SET)) == (off_t)-1) {
		perror("lseek");
		return 4;
	}

	/* write new pmbr */
	if ( (write(fd, buf, 512)) != 512 ) {
		perror("failed to update the image size");
		return 5;
	}
	puts("pmbr updated");
	return 0;
}
