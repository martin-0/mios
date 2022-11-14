/* martin */
	.set ELFSIG, 	0x464c457f			/* 0x7F "ELF" */

	.set EI_CLASS,		0x4
	.set EI_MACHINE,	0x12
	.set E_ENTRY, 		0x18
	.set E_PHOFF,		0x1c
	.set E_PHNUM, 		0x2c
	.set E_SHSTRMDX, 	0x32	

	/* elf32 program header */
	.set P_TYPE,		0x0
	.set P_OFFSET,		0x4
	.set P_VADDR,		0x8
	.set P_PADDR,		0xc
	.set P_FILESZ,		0x10
	.set P_MEMSZ,		0x14
	.set P_FLAGS,		0x18
	.set P_ALIGN,		0x1c

	.set MASK_ABOVE1M,	0xFFF00000

	.set PAGE_SIZE,		0x1000				/* XXX: PAGE_SIZE should be defined somewhere else maybe? */
	.set MASK_PALIGN, 	(PAGE_SIZE-1)

.include "gboot.inc"
	
.section .text
	.code16

/* CF set in case of an error */
.func linear_to_segmented
linear_to_segmented:
	movl %eax, %edx					/* linear address has to be below 1MB */
	andl $MASK_ABOVE1M, %edx
	testl %edx, %edx
	jnz .Llts_err

	// TODO:


.Llts_err:
	stc
	ret
.endfunc


/* int elf32_load_file(struct* inode)
 *
 * return 0 if OK
*/
.global elf32_load_file
.func elf32_load_file
elf32_load_file:
	pushl %esi
	pushl %edi
	pushl %ebx

	movl %eax, %esi					/* inode */
	xorl %ebx, %ebx					/* i-count */

	.ifdef DEBUG_VERBOSE
		xorl %edx, %edx
		movl (l_ext2_sb_blocksize), %ecx
		movl INODE_OFST_ISIZE(%esi), %eax
		div %ecx
		test %edx, %edx
		jz .Llf_1
		inc %eax

	.Llf_1:
		pushw (l_ext2_sb_blocksize)
		pushw %ax
		pushl INODE_OFST_ISIZE(%esi)
		pushw $(elf32_lf_info)		// "elf32_load_file: file size: 0x%lx bytes, spread on %d %d-byte blocks\r\n"
		call printf16
		addw $10, %sp
	.endif

	/* load the first block of ELF file */
        movl $ADDR_BLOCBUF, %edx
        movl INODE_OFST_DBP_0(%esi), %eax       // block0 of ELF
        call ext2_access_block
	jc .Llf_end_err

	/* check the ELF32 header */
	call elf32_check_header
	testl %eax, %eax
	jnz .Llf_end_err

	// TODO: 
	//	we have a location/offset where program headers begin
	//	go through them and load any PT_LOAD entries into memory
	//

	// offset	:	how far into the file header starts
	// addr (phy/virt)	where we start loading (possibly todo once paging is enabled)
	// filesize:		how much into the file i'll be reading
	// memsize:		how much memory i will be reserving

	// the memsize is important for PM but at this stage I'm not using it at all. XXX: should I pass this information to kernel?

	movl (l_e_phoff), %edi
	addl $ADDR_BLOCBUF, %edi					/* start of the program header */

.Llf_progheader_loop:
	cmpw (w_e_phnum), %bx
	jae .Llf_progheader_loop_end

	.ifdef DEBUG_VERBOSE
		pushl P_FILESZ(%edi)
		pushl P_PADDR(%edi)
		pushl P_OFFSET(%edi)
		pushw $(elf32_lf_dbg1)
		call printf16
		addw $14, %sp
	.endif

	/* address has to be below 1MB */
	movl P_PADDR(%edi), %eax
	andl $MASK_ABOVE1M, %eax
	test %eax,%eax
	jnz .Llf_loadaddr_toohigh

	/* has to be page aligned too */
	movl P_PADDR(%edi), %eax
	andl $MASK_PALIGN, %eax
	test %eax, %eax
	jnz .Llf_loadaddr_notaligned

	inc %bx
	addl $32, %edi		// sizeof(phy_e)
	loop .Llf_progheader_loop

.Llf_progheader_loop_end:
	cli
	hlt

	movl $ADDR_SIBPBUF, %edx
	leal INODE_OFST_DBP_0(%esi), %eax
	movl 4(%eax), %eax
	call ext2_access_block
	jc .Llf_end_err

	/* 0x20000 is 2000:0000 */
	pushw $0x1000
	pushw $ADDR_SIBPBUF
	pushw $0
	pushw $0x2000
	call memcpy_seg
	addw $8, %sp

	/* load block 1 */	
	movl $ADDR_SIBPBUF, %edx
	leal INODE_OFST_DBP_0(%esi), %eax
	movl 8(%eax), %eax
	call ext2_access_block
	jc .Llf_end_err

	pushw $0x594
	pushw $ADDR_SIBPBUF
	pushw $0
	pushw $0x2100
	call memcpy_seg
	addw $8, %sp

	xorl %eax, %eax
	jmp .Llf_end

.Llf_loadaddr_notaligned:
	pushl P_PADDR(%edi)
	pushw $(elf32_load_file_err_laddr_notaligned)
	call printf16
	addw $6, %sp
	jmp .Llf_end_err

.Llf_loadaddr_toohigh:
	pushl P_PADDR(%edi)
	pushw $(elf32_load_file_err_laddr_high)
	call printf16
	addw $6, %sp
	// fall through

.Llf_end_err:
	movw $1, %ax

.Llf_end:
	popl %ebx
	popl %edi
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
	jne .Lelf32_err_badsig

	/* check the elf class */
	movb EI_CLASS(%esi), %al
	cmpb $1, %al
	jne .Lelf32_err_badclass

	/* check the architecture */
	movw EI_MACHINE(%esi), %ax
	cmpw $3, %ax
	jne .Lelf32_err_badmachine

	/* save some header variables */
	movl E_ENTRY(%esi), %eax				/* ELF32 entry point */
	movl %eax, (l_e_entry)
	movl E_PHOFF(%esi), %eax				/* offset to program headers */
	movl %eax, (l_e_phoff)
	movw E_PHNUM(%esi), %ax					/* number of program headers */
	movw %ax, (w_e_phnum)

	/* unlikely but check */
	testw %ax,%ax
	jz .Lelf32_err_noph

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

.Lelf32_err_noph:
	movw $(elf32_check_header_noprogramh), %ax
	call puts16
	jmp .Lelf32_err_end

.Lelf32_err_badmachine:
	movw $(elf32_check_header_wrongiset), %ax
	call puts16
	jmp .Lelf32_err_end

.Lelf32_err_badclass:
	movw $(elf32_check_header_badclass), %ax
	call puts16
	jmp .Lelf32_err_end

.Lelf32_err_badsig:
	movw $(elf32_check_header_badsig), %ax
	call puts16

.Lelf32_err_end:
	movb $1, %al

.Lelf32_end:
	popl %esi

	ret
.endfunc

.section .data
	.align 4

	/* saved variables from elf header */
	l_e_entry:	.long	0	/* entry point for this ELF */
	l_e_phoff:	.long	0	/* start of the program header table */
	w_e_phnum:	.word	0	/* number of entries in the program header table */
	w_e_shstrndx:	.word	0	/* index to secrion header with section names */ // XXX: ? but then I need sections to be loaded too..


	/* elf32_check_header() */
	elf32_check_header_badsig:	.asciz	"ELF32: bad signature\r\n"
	elf32_check_header_badclass:	.asciz	"ELF32: only 32B kernel image is supported.\r\n"
	elf32_check_header_wrongiset:	.asciz	"ELF32: wrong architecture, only x86 is supported.\r\n"
	elf32_check_header_noprogramh:	.asciz	"ELF32: no program headers defined in file, nothing to load.\r\n"

	/* elf32_load_file() */
	elf32_load_file_err_laddr_high:		.asciz	"ELF32: address 0x%lx above 1MB limit, unable to load.\r\n"
	elf32_load_file_err_laddr_notaligned:	.asciz	"ELF32: address 0x%lx not PAGE aligned, unable ot load.\r\n"


	.ifdef DEBUG_VERBOSE
		elf32_ch_info:	.asciz "program header entries: %d, starting at 0x%x, entry: 0x%x\r\n"
		elf32_lf_info:	.asciz "elf32_load_file: file size: 0x%lx bytes, spread on %d %d-byte blocks\r\n"
		elf32_lf_dbg1:	.asciz "program header: offset: 0x%lx, physaddr: 0x%lx, filesize: 0x%lx\r\n"
	.endif

	// xxx
	dbg2: .asciz	"entry: %lx\r\n"
