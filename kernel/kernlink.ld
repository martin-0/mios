/* martin */

OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)

ENTRY(_start);
SECTIONS
{
	.text : {
		*.o(.text*)
	}

	.data : {
		*.o(.data*)
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
