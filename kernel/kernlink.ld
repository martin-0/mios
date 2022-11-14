/* martin */

PAGE_SIZE = 4096;

OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)

ENTRY(_kernel_entry);
SECTIONS
{
	. = LINKADDR;
	.text : {
		*.o(.text*)
	}

	. = ALIGN(PAGE_SIZE);
	.data : {
		*.o(.data*)
	}

	. = ALIGN(PAGE_SIZE);
	.bss : {
		*.o(.bss*)
	}

	/* Discard common unwanted/unneeded sections */
	/DISCARD/ : {
		*(.comment);
		*(.debug*);
		*(.note.gnu.build-id);
	}

	.signature : {
		QUAD(0xf001cafe)
	}
}
