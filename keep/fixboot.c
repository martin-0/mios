#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

/* size of the loader */
#define	BOOT_LBA0_OFST		0x1f6

int fd = -1;
void __attribute__((destructor)) cleanup() { if(fd >= 0) close(fd); } ;

int main(int argc, char** argv) { 
	if (argc != 2) {
		printf("parameter missing: %s: <diskimage>\n", argv[0]);
		return 1;
	}

	struct stat s; 
	if ((fd = open(argv[1], O_RDWR)) < 0) {
		perror("failed to open diskimage file");
		return 2;
	}

	if ((fstat(fd, &s)) != 0) {
		perror("fstat failed");
		return 3;
	}

	if ((lseek(fd, BOOT_LBA0_OFST, SEEK_SET)) == (off_t)-1) {
		perror("lseek ");
		return 4;
	}
	if ( (write(fd, &s.st_size, sizeof(off_t))) != sizeof(off_t)) {
		perror("failed to update the image size");
		return 5;
	}

	printf("image updated, size: %u.\n", s.st_size);

	return 0;
}
