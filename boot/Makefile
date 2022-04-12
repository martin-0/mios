
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

# inspired by https://elixir.bootlin.com/linux/v4.20.17/source/arch/x86/Makefile
REALMODE_CFLAGS:=-m16 -g -Os -Wall -Wstrict-prototypes -march=i386 -mregparm=3 \
		-fno-strict-aliasing -fomit-frame-pointer -fno-pic \
		-mno-mmx -mno-sse -ffreestanding -fno-stack-protector -mpreferred-stack-boundary=2
REALMODE_CFLAGS+=-I$(INCDIR)

CFLAGS=-m32 -march=i386 -g -Os -ffreestanding -fomit-frame-pointer -fno-stack-protector -Wall -Wextra -mregparm=3
CFLAGS+=-I$(INCDIR)

SRCO=boot1.o libsa16.o cons.o libsa.o

.PHONY: pmbr
all: gboot

gboot:	$(SRCO)
	cd $(OBJDIR) && $(LD) $(LDFLAGS) -o gboot.bin $(SRCO)
	objcopy -v -O binary $(OBJDIR)/gboot.bin $(OBJDIR)/gboot

# boot1 requires LINKADDR as it loads gdt which requires linear address
boot1.o: boot1.S
	$(AS) $(ASFLAGS) boot1.S -o $(OBJDIR)/boot1.o

libsa16.o: libsa16/libsa16.S
	$(AS) libsa16/libsa16.S -o $(OBJDIR)/libsa16.o

cons.o:	cons.c cons.h
	$(CC) $(CFLAGS) cons.c -c -o $(OBJDIR)/cons.o

libsa.o: libsa.c libsa.h cons.o
	$(CC) $(CFLAGS) libsa.c -c -o $(OBJDIR)/libsa.o

pmbr:
	make -C pmbr

clean:
	cd $(OBJDIR) && rm -f $(SRCO) gboot gboot.bin
	make -C pmbr clean
