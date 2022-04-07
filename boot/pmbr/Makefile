
AS=/local/cross/bin/i686-elf-as

OBJDIR=../../obj

pmbr.o:	pmbr.S
	$(AS) pmbr.S -o $(OBJDIR)/pmbr.o
	objcopy -v -O binary $(OBJDIR)/pmbr.o $(OBJDIR)/pmbr

clean:
	cd $(OBJDIR) && rm -f pmbr.o pmbr
