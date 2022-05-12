
#
# Will create pmbr and mios image
#

CC=/local/cross/bin/i686-elf-gcc
AS=/local/cross/bin/i686-elf-as
LD=/local/cross/bin/i686-elf-ld

DISK_RAW=disk00.raw

INCDIR=../include
OBJDIR=../obj

LINKADDR=0x7c00

ASFLAGS=--defsym LINKADDR=$(LINKADDR)

# used for debugging
#LDFLAGS=--defsym LINKADDR=$(LINKADDR) -T ../boot/link.ld -N -M
LDFLAGS=--defsym LINKADDR=$(LINKADDR) -T ../boot/link.ld -N


# https://elixir.bootlin.com/linux/v4.20.17/source/arch/x86/Makefile
# NOTE: -mregparm=3 not used
CFLAGS=-m32 -march=i386 -g -Os -ffreestanding -fomit-frame-pointer -fno-stack-protector -Wall -Wextra -mpreferred-stack-boundary=4
CFLAGS+=-I$(INCDIR) -DDEBUG -DDEBUG_TRAP -DDEBUG_PM
#CFLAGS+=-DDEBUG_IRQ -DDEBUG_TRAP

SRCO=boot1.o libsa16.o cons.o libsa.o pic.o idt.o main.o mm.o

.PHONY: pmbr
all: gboot

gboot:	$(SRCO)
	cd $(OBJDIR) && $(LD) $(LDFLAGS) -o gboot.bin $(SRCO)
	objcopy -v -O binary $(OBJDIR)/gboot.bin $(OBJDIR)/gboot

# boot1 requires LINKADDR as it loads gdt which requires linear address
boot1.o: boot1.S
	$(AS) $(ASFLAGS) boot1.S -o $(OBJDIR)/boot1.o

idt.o: idt.S
	$(AS) idt.S -o $(OBJDIR)/idt.o

libsa16.o: libsa16/libsa16.S
	$(AS) libsa16/libsa16.S -o $(OBJDIR)/libsa16.o

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

pmbr:
	make -C pmbr

clean:
	cd $(OBJDIR) && rm -f $(SRCO) gboot gboot.bin
	make -C pmbr clean
