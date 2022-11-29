CFLAGS=-g -m32  -no-pie -Wall -Wpedantic -Wextra -DDEBUG
OBJDIR=../obj

all: ext2 seek-test verify-seek

verify-seek: verify-seek.c
	gcc $(CFLAGS) -o $(OBJDIR)/verify-seek verify-seek.c

seek-test: seek-test.c
	gcc $(CFLAGS) -o $(OBJDIR)/seek-test seek-test.c

ext2:	ext2.c
	gcc $(CFLAGS) -o $(OBJDIR)/ext2_test ext2.c

clean:
	rm -f $(OBJDIR)/ext2_test div $(OBJDIR)/seek-test $(OBJDIR)/verify-seek
