#
# build kernel image
#

CC=/local/cross/bin/i686-elf-gcc
AS=/local/cross/bin/i686-elf-as
LD=/local/cross/bin/i686-elf-ld

INCDIR=../include
OBJDIR=../obj

#LINKADDR=0x20000
LINKADDR=0x200000

ASFLAGS=
#ASFLAGS=--defsym LINKADDR=$(LINKADDR)

LDFLAGS=-T ../kernel/kernlink.ld --defsym LINKADDR=$(LINKADDR)

# https://elixir.bootlin.com/linux/v4.20.17/source/arch/x86/Makefile
CFLAGS=-m32 -march=i386 -g -Os -ffreestanding -fomit-frame-pointer -fno-stack-protector -Wall -Wextra -mpreferred-stack-boundary=4
#-mregparm=3
CFLAGS+=-I$(INCDIR) -DDEBUG -DDEBUG_TRAP -DDEBUG_PM
#CFLAGS+=-DDEBUG_IRQ -DDEBUG_TRAP

SRCO= entry.o main.o cons.o pic.o idt.o mm.o libsa.o

all: kernel

kernel:	$(SRCO)
	cd $(OBJDIR) && $(LD) $(LDFLAGS) -o kernel $(SRCO)

entry.o: entry.S
	$(AS) $(ASFLAGS) entry.S -o $(OBJDIR)/entry.o

idt.o: idt.S
	$(AS) $(ASFLAGS) idt.S -o $(OBJDIR)/idt.o

cons.o:	cons.c cons.h
	$(CC) $(CFLAGS) cons.c -c -o $(OBJDIR)/cons.o

libsa.o: libsa.c libsa.h
	$(CC) $(CFLAGS) libsa.c -c -o $(OBJDIR)/libsa.o

pic.o: pic.c pic.h 
	$(CC) $(CFLAGS) pic.c -c -o $(OBJDIR)/pic.o

main.o: main.c 
	$(CC) $(CFLAGS) main.c -c -o $(OBJDIR)/main.o

mm.o: mm.c
	$(CC) $(CFLAGS) mm.c -c -o $(OBJDIR)/mm.o

clean:
	cd $(OBJDIR) && rm -f $(SRCO) kernel
