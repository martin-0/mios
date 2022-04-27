/* martin */

/*  LINKADDR is passed by the ld, set to 0x7c00 */
OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)

ENTRY(_start);
SECTIONS
{

	. = LINKADDR; 
	.boot1 : { 
		boot1.o(.*)
		libsa16.o(.*)
	}

	.code32 : {
		__c32start = . ; 
		pic.o(.*)
		idt.o(.*)
		cons.o(.*)
		libsa.o(.*)
		main.o(.*)
	}


	/* Discard common unwanted/unneeded sections */
	/DISCARD/ : {
		*(.comment);
		*(.debug*);
		*(.note.gnu.build-id);
	}

	.signature : {
		QUAD(0x1337decafe)
	}
}
