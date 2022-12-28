
AS=/local/cross/bin/i686-elf-as
AFLAGS=--defsym SERIAL=0

OBJDIR=../../obj

pmbr.o:	pmbr.S
	$(AS) $(AFLAGS) pmbr.S -o $(OBJDIR)/pmbr.o
	objcopy -v -O binary $(OBJDIR)/pmbr.o $(OBJDIR)/pmbr

clean:
	cd $(OBJDIR) && rm -f pmbr.o pmbr
