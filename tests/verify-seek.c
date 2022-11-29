/* test: use libc lseek to verify my inode seek is correct */

#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>

#define	COOKIE	"/tmp/rootfs/debugme"

int main(int argc, char** argv) {
	int fd;
	char buf[256] = { 0 } ;
	off_t ofst;

	if (argc == 1) {
		ofst = 0;
	} else {
		ofst = strtol(argv[1], NULL, 10);
	}

	if ((fd = open(COOKIE, O_RDONLY)) < 0) {
		perror("cookie");
		return 1;
	}

	printf("using offset: %lu\n", ofst);

	if ((lseek(fd, ofst, SEEK_SET)) == (off_t)-1) {
		perror("lseek");
		return 2;
	}

	read(fd, buf, 32);
	printf("cookie: %s\n",buf);


	close(fd);
	return 42;
}
