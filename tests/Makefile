CFLAGS=-g -m32  -no-pie -Wall -Wpedantic -Wextra
OBJDIR=../obj

all: ext2

ext2:	ext2.c
	gcc $(CFLAGS) -o $(OBJDIR)/ext2_test ext2.c

clean:
	rm -f $(OBJDIR)/ext2_test
