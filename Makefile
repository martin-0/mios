CC=/local/cross/bin/i686-elf-gcc
AS=/local/cross/bin/i686-elf-as
LD=/local/cross/bin/i686-elf-ld

INCDIR=include
OBJDIR=obj

LINKADDR=0x7c00

ASFLAGS=--defsym LINKADDR=$(LINKADDR)
LDFLAGS=--defsym LINKADDR=$(LINKADDR) -T../tools/link.ld -N

# XXX: original flags I used for m16
# CFLAGS=-ffreestanding -fomit-frame-pointer -fno-stack-protector -Wall -Wextra -mregparm=3 -I${INCDIR}/ 

# inspired by https://elixir.bootlin.com/linux/v4.20.17/source/arch/x86/Makefile
REALMODE_CFLAGS:=-m16 -g -Os -Wall -Wstrict-prototypes -march=i386 -mregparm=3 \
		-fno-strict-aliasing -fomit-frame-pointer -fno-pic \
		-mno-mmx -mno-sse -ffreestanding -fno-stack-protector -mpreferred-stack-boundary=2
REALMODE_CFLAGS+=-I$(INCDIR)

SRCO= boot0.o boot1.o libsa16.o a20.o

.PHONY: tools
all: tools mios 

mios:	${SRCO}
	cd $(OBJDIR) && $(LD) $(LDFLAGS) -o mios.bin $(SRCO)
	objcopy -v -O binary ${OBJDIR}/mios.bin mios
	${OBJDIR}/fixboot mios

a20.o:	a20.c
	$(CC) $(REALMODE_CFLAGS) a20.c -c -o $(OBJDIR)/a20.o

boot0.o: boot0.S
	${AS} boot0.S -o ${OBJDIR}/boot0.o

# boot1 requires LINKADDR as it loads gdt which requires linear address
boot1.o: boot1.S
	${AS} ${ASFLAGS} boot1.S -o ${OBJDIR}/boot1.o

libsa16.o: libsa16.S
	${AS} libsa16.S -o ${OBJDIR}/libsa16.o

tools:
	make -C tools

clean:
	rm -f ${OBJDIR}/* mios
	make -C tools clean
