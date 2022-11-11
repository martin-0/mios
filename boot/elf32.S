/* martin */
	.set ELFSIG, 	0x464c457f			/* 0x7F "ELF" */

	.set EI_CLASS,		0x4
	.set EI_MACHINE,	0x12
	.set E_ENTRY, 		0x18
	.set E_PHOFF,		0x1c
	.set E_PHNUM, 		0x2c
	.set E_SHSTRMDX, 	0x32	

.include "gboot.inc"
	
.section .text
	.code16

/* int elf32_load_file(struct* inode) */
.global elf32_load_file
.func elf32_load_file
elf32_load_file:
	pushl %esi
	movl %eax, %esi					/* inode */

	xorl %edx, %edx
	movl (l_ext2_sb_blocksize), %ecx
	movl INODE_OFST_ISIZE(%esi), %ecx
	div %ecx
	test %edx, %edx
	jz .Llf_1
	inc %eax

.Llf_1:
	pushw (l_ext2_sb_blocksize)
	pushw %ax
	pushw %cx
	pushw $(elf32_lf_info)
	call printf16
	addw $8, %sp

	/* load the first block */
        movl $ADDR_BLOCBUF, %edx
        movl INODE_OFST_DBP_0(%esi), %eax       // block0 of ELF
        call ext2_access_block
	jc .Llf_end_err

	/* check the ELF32 header */
	call elf32_check_header

	// TODO: 
	//	we have a location/offset where program headers begin
	//		go through them and load any PT_LOAD entries into memory
	//
	//	problem: file is being loaded by blocks. while there's good chance program headers will be within
	//	range of PAGE_SIZE I need to take special care I need to load it .. what if entry lives on cross block?

	jmp .Llf_end

.Llf_end_err:
	movw $1, %ax

.Llf_end:

	popl %esi
	ret
.endfunc


/* int elf32_check_header(elf32hdr* header) */

/* return 0 if all OK */
.global elf32_check_header
.func elf32_check_header
elf32_check_header:
	pushl %esi

	movl %eax, %esi						/* save the header reference */

	/* signature check */
	movl (%esi), %eax
	cmpl $ELFSIG, %eax
	jne .Lelf32_badsig

	/* check the elf class */
	movb EI_CLASS(%esi), %al
	cmpb $1, %al
	jne .Lelf32_badclass

	/* check the architecture */
	movw EI_MACHINE(%esi), %ax
	cmpw $3, %ax
	jne .Lelf32_badmachine

	/* save some header variables */
	movl E_ENTRY(%esi), %eax				/* ELF32 entry point */
	movl %eax, (l_e_entry)
	movl E_PHOFF(%esi), %eax				/* offset to program headers */
	movl %eax, (l_e_phoff)
	movw E_PHNUM(%esi), %ax					/* number of physical headers */
	movw %ax, (w_e_phnum)
	movw E_SHSTRMDX(%esi), %ax				/* index to section names in section header */
	movw %ax, (w_e_shstrndx)

	.ifdef DEBUG_VERBOSE
		pushl (l_e_entry)
		pushl (l_e_phoff)
		pushw (w_e_phnum)
		pushw $(elf32_ch_info)
		call printf16
		addw $12, %sp
	.endif

	/* consider header OK, we're done here */
	xorl %eax,%eax
	jmp .Lelf32_end

.Lelf32_badmachine:
	movw $(elf32_check_header_wrongiset), %ax
	call puts16
	jmp .Lelf32_errend

.Lelf32_badclass:
	movw $(elf32_check_header_badclass), %ax
	call puts16
	jmp .Lelf32_errend

.Lelf32_badsig:
	movw $(elf32_check_header_badsig), %ax
	call puts16

.Lelf32_errend:
	movb $1, %al

.Lelf32_end:
	popl %esi

	ret
.endfunc

.section .data
	.align 4
	l_e_entry:	.long	0	/* entry point for this ELF */
	l_e_phoff:	.long	0	/* start of the program header table */
	w_e_phnum:	.word	0	/* number of entries in the program header table */
	w_e_shstrndx:	.word	0	/* index to secrion header with section names */ // XXX: ? but then I need sections to be loaded too..

	
	elf32_check_header_badsig:	.asciz	"ELF32: bad signature\r\n"
	elf32_check_header_badclass:	.asciz	"ELF32: only 32B kernel image is supported.\r\n"
	elf32_check_header_wrongiset:	.asciz	"ELF32: wrong architecture, only x86 is supported.\r\n"


	.ifdef DEBUG_VERBOSE
		elf32_ch_info:	.asciz "program header entries: %d, starting at 0x%lx, enty: 0x%lx\r\n"
		elf32_lf_info:	.asciz "elf32_load_file: file size: %d bytes, spread on %d %d-byte blocks\r\n"
	.endif

	// xxx
	dbg2: .asciz	"entry: %lx\r\n"
