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

LDFLAGS=-T ../kernel/linkkern.ld --defsym LINKADDR=$(LINKADDR)

# https://elixir.bootlin.com/linux/v4.20.17/source/arch/x86/Makefile
CFLAGS=-m32 -march=i386 -g -Os -ffreestanding -fomit-frame-pointer -fno-stack-protector -Wall -Wextra -mpreferred-stack-boundary=4 -mregparm=3
CFLAGS+=-I$(INCDIR) -DDEBUG -DDEBUG_PM
#CFLAGS+=-DDEBUG_IRQ -DDEBUG_TRAP

SRCO= entry.o kernel.o cons.o pic.o idt.o mm.o kbd.o uart.o libk.o gshell.o

all: kernel

kernel:	$(SRCO) kernel.h libk.h pic.h mm.h kbd.h uart.h gshell.h
	cd $(OBJDIR) && $(LD) $(LDFLAGS) -o kernel $(SRCO)

entry.o: entry.S
	$(AS) $(ASFLAGS) entry.S -o $(OBJDIR)/entry.o

kernel.o: kernel.c kernel.h
	$(CC) $(CFLAGS) kernel.c -c -o $(OBJDIR)/kernel.o

idt.o: idt.S
	$(AS) $(ASFLAGS) idt.S -o $(OBJDIR)/idt.o

cons.o:	cons.c cons.h
	$(CC) $(CFLAGS) cons.c -c -o $(OBJDIR)/cons.o

libk.o: libk.c libk.h
	$(CC) $(CFLAGS) libk.c -c -o $(OBJDIR)/libk.o

pic.o: pic.c pic.h 
	$(CC) $(CFLAGS) pic.c -c -o $(OBJDIR)/pic.o

mm.o: mm.c
	$(CC) $(CFLAGS) mm.c -c -o $(OBJDIR)/mm.o

kbd.o: kbd.c kbd.h
	$(CC) $(CFLAGS) kbd.c -c -o $(OBJDIR)/kbd.o

uart.o: uart.c uart.h
	$(CC) $(CFLAGS) uart.c -c -o $(OBJDIR)/uart.o

gshell.o: gshell.c gshell.h
	$(CC) $(CFLAGS) gshell.c -c -o $(OBJDIR)/gshell.o


clean:
	cd $(OBJDIR) && rm -f $(SRCO) kernel
