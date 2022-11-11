#
# creates pmbr and gboot image
#

CC=/local/cross/bin/i686-elf-gcc
AS=/local/cross/bin/i686-elf-as
LD=/local/cross/bin/i686-elf-ld

INCDIR=../include
OBJDIR=../obj

LINKADDR=0x7c00

ASFLAGS=--defsym LINKADDR=$(LINKADDR) --defsym DEBUG_VERBOSE=1

LDFLAGS=--defsym LINKADDR=$(LINKADDR) -T ../boot/link.ld -N
#LDFLAGS=--defsym LINKADDR=$(LINKADDR) -T ../boot/link.ld -N -M

SRCO=boot1.o libsa16.o ext2.o elf32.o

.PHONY: pmbr
all: gboot

gboot:	$(SRCO)
	cd $(OBJDIR) && $(LD) $(LDFLAGS) -o gboot.bin $(SRCO)
	objcopy -v -O binary $(OBJDIR)/gboot.bin $(OBJDIR)/gboot

# boot1 requires LINKADDR as it loads gdt which requires linear address
boot1.o: boot1.S
	$(AS) $(ASFLAGS) boot1.S -o $(OBJDIR)/boot1.o

ext2.o: ext2.S gboot.inc
	$(AS) $(ASFLAGS) ext2.S -o $(OBJDIR)/ext2.o

elf32.o: elf32.S gboot.inc
	$(AS) $(ASFLAGS) elf32.S -o $(OBJDIR)/elf32.o

libsa16.o: libsa16.S
	$(AS) libsa16.S -o $(OBJDIR)/libsa16.o

pmbr:
	make -C pmbr

clean:
	cd $(OBJDIR) && rm -f $(SRCO) gboot gboot.bin
	make -C pmbr clean
