/* martin */
	.set ELFSIG, 	0x464c457f				/* 0x7F "ELF" */

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

	.set PT_LOAD,		1				/* program header type */

	.set MASK_MEM_ABOVE1M,	0xFFF00000

	.set PAGE_SIZE,		0x1000				/* XXX: PAGE_SIZE should be defined somewhere else maybe? */
	.set MASK_PALIGN, 	(PAGE_SIZE-1)

	.set SZ_PHDR,		0x20				/* size of program header structure */

.include "gboot.inc"
	
.section .text
	.code16


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
	pushl %ebp
	movl %esp, %ebp
	subl $32, %esp

	/* variables on stack:
		-4(%ebp)	NOTE: unused, was P_OFFSET: block index within inode's blocks
		-8(%ebp)	NOTE: unused, was P_OFFSET: offset within block itself
		-12(%ebp)	P_FILESZ: blocks to read
		-16(%ebp)	P_FILESZ: size leftover, requires additional block to read
		-20(%ebp)	current paddr
		-22(%ebp)	int16: current segment used during program header copy
		-24(%ebp)	int16: current offset used during program header copy
		-28(%ebp)	offset within file when loading segments
	*/

	movl %eax, %esi						/* inode */
	xorl %ebx, %ebx						/* i-count */

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
		pushw $(elf32_lf_info)	// "elf32_load_file: file size: 0x%lx bytes, spread on %d %d-byte blocks\r\n"
		call printf16
		addw $10, %sp
	.endif

	/* load the first block of ELF file, we can use pathbuf[] for this */
	movl $pathbuf, %edx
        movl INODE_OFST_DBP_0(%esi), %eax			/* inode's 1st direct block */
        call ext2_access_block
	jc .Llf_err_end

	/* check the ELF32 header */
	call elf32_check_header
	testl %eax, %eax
	jnz .Llf_err_end

	/* NOTE:
		e_phoff should point right after ELF header. This means program headers will be close to start and
		very unlikely bigger than 1024b (smallest ext2 block size).
		Initial checks is done but maybe I should at least detect this in the loop.
	*/

	/* check the initial buffer boundary */
	movl (l_e_phoff), %edi
	cmpl %edi, (l_ext2_sb_blocksize)			/* very unlikely */
	jbe .Llf_err_phdr_toodeep

	addl $pathbuf, %edi					/* start of the program headers */

	/* Master loop: go through every program header */
	movw $(elf32_load_file_msg1), %ax
	call puts16

.Llf_progheaders_loop:
	cmpw (w_e_phnum), %bx
	jae .Llf_progheaders_loop_end

	.ifdef DEBUG_VERBOSE
		pushl P_FILESZ(%edi)
		pushl P_PADDR(%edi)
		pushl P_OFFSET(%edi)
		pushl P_TYPE(%edi)
		pushw $(elf32_lf_dbg1)
		call printf16
		addw $18, %sp
	.endif

	/* header has to be of PT_LOAD type */
	cmpl $PT_LOAD, P_TYPE(%edi)
	jne .Llf_progheaders_loop_1

	/* address has to be below 1MB */
	movl P_PADDR(%edi), %eax
	andl $MASK_MEM_ABOVE1M, %eax
	test %eax,%eax
	jnz .Llf_err_loadaddr_toohigh

	/* has to be page aligned too */
	movl P_PADDR(%edi), %eax
	andl $MASK_PALIGN, %eax
	test %eax, %eax
	jnz .Llf_err_loadaddr_notaligned

	/* We will load program header:
		of type:	PT_LOAD
		to addr:	P_PADDR
		of size:	P_FILESZ
		up to mem:	P_MEMSZ (0 down the unused memory)

		NOTE:		P_MEMSZ and P_VADDR are probably needed by PM when paging is enabled.
		XXX:		P_ALIGN ( addr % align = offset % align or  addr===offset (mod align) )
					can be probably ignored during loading
	*/

	/* XXX: probably avoid using div but rather mask and check */

	xorl %edx,%edx						/* P_OFFSET: calculate block index within inode's blocks and its offset within buffer */
	movl P_OFFSET(%edi), %eax
	movl (l_ext2_sb_blocksize), %ecx
	div %ecx

	/* Linker script aligned all segments to page size which implies block size. Reject loading unaligned segments. */
	testl %edx, %edx
	jnz .Llf_err_unsupp_offset

	/* P_FILESZ: calculate blocks to read and leftovers in bytes */
	xorl %edx,%edx
	movl P_FILESZ(%edi), %eax
	movl (l_ext2_sb_blocksize), %ecx
	div %ecx
	movl %eax, -12(%ebp)					/* P_FILESZ: blocks to read */
	movl %edx, -16(%ebp)					/* P_FILESZ: size leftover, requires additional block to read */

	.ifdef DEBUG_VERBOSE
		pushl -16(%ebp)
		pushl -12(%ebp)
		pushw $(elf32_lf_dbg2)
		call printf16
		addw $10, %sp
	.endif

	/* P_PADDR: page aligned, below 1MB: linear_addr >> 4 gives us required segment */
	movw $0, -24(%ebp)					/* reset dst offset to 0 */
	movl P_PADDR(%edi), %eax
	movb %al, -24(%ebp)					/* dst offset */
	shr $4, %eax
	movw %ax, -22(%ebp)					/* dst segment */

	.ifdef DEBUG_VERBOSE
		pushw %ax
		pushw $(elf32_lf_dbg3)
		call printf16
		addw $4, %sp
	.endif

	/*
		laod is done in 2 stages:
			.Llf_load_blocks			read -12(%ebp) blocks
			.Llf_load_leftover_block		if P_FILESZ doesn't fit the blocksize completely

		Segment:offset needs to be properly adjusted during block copy.
	*/

	movl P_PADDR(%edi), %eax
	movl %eax, -20(%ebp)					/* current paddr */
	movl P_OFFSET(%edi), %eax
	movl %eax, -28(%ebp)					/* starting offset within file */

.Llf_load_blocks:
	/* load the region by blocksize, -12(%ebp) times */
	movl -12(%ebp), %eax
	testl %eax, %eax
	jz .Llf_load_leftover_block

	movl -28(%ebp), %ecx					/* current offset within file */
	movl $ADDR_BLOCBUF, %edx
	movl $ADDR_INODE, %eax
	call ext2_inode_seek
	testl %eax,%eax
	jz .Llf_inodeseek_err

	movl (l_ext2_sb_blocksize), %edx
	pushw %dx		/* copy by block size  */
	pushw %ds		/* src segment (0) */
	pushw %ax		/* src offset */
	pushw -22(%ebp)		/* dst segment */
	pushw -24(%ebp)		/* dst offset */
	call farmemcpy
	add $10, %sp

	decl -12(%ebp)						/* blocks_to_read-- */
	movl (l_ext2_sb_blocksize), %eax
	addl %eax, -28(%ebp)					/* adjust offset within file */


	addw %ax, -24(%ebp)					/* adjust dst offset */
	jnc .Llf_load_blocks					/* was there overflow? if so adjust segment */

	addw $0x1000, -22(%ebp)					/* adjust segment register */
	jnc .Llf_load_blocks					/* unlikely but check for it */

	jmp .Llf_err_segment_overflow				/* handle overflow error */

.Llf_load_leftover_block:
	movl -16(%ebp), %eax
	testl %eax, %eax
	jz .Llf_progheaders_loop_1

	movl -28(%ebp), %ecx					/* current offset within file */
	movl $ADDR_BLOCBUF, %edx
	movl $ADDR_INODE, %eax
	call ext2_inode_seek
	testl %eax,%eax
	jz .Llf_inodeseek_err

	movl -16(%ebp), %edx	/* leftovers */
	pushw %dx		/* copy by block size  */
	pushw %ds		/* src segment (0) */
	pushw %ax		/* src offset */
	pushw -22(%ebp)		/* dst segment */
	pushw -24(%ebp)		/* dst offset */
	call farmemcpy
	add $10, %sp

	movl P_FILESZ(%edi), %eax
	movl P_MEMSZ(%edi), %edx

	cmpl %eax, %edx						/* if P_MEMSZ <= P_FILESZ: end : otherwise zero down mem */
	jbe .Llf_progheaders_loop_1

	/* dst offsets needs to be adjusted as I should 0 down the memory up to P_MEMSZ */
	movl -16(%ebp), %eax
	addw %ax, -24(%ebp)					/* adjust dst offset */

	// TODO: create farmemset(dst, c, size)

.Llf_progheaders_loop_1:
	/* next program header */
	inc %bx
	addl $SZ_PHDR, %edi					/* next entry */
	jmp .Llf_progheaders_loop

	/* all program headers are loaded, we are done */
.Llf_progheaders_loop_end:
	xorl %eax, %eax
	jmp .Llf_end

	/* offset to a program segment is not page size/block size aligned */
.Llf_err_unsupp_offset:
	pushl P_MEMSZ(%edi)
	pushl P_FILESZ(%edi)
	pushl P_PADDR(%edi)
	pushl P_OFFSET(%edi)
	pushw $(elf32_load_file_err_unaligned_ofst)
	call printf16
	addw $16, %sp
	jmp .Llf_err_end

	/* generic error in seek */
.Llf_inodeseek_err:
	movw $(elf32_load_file_err_inodeseek), %ax
	call puts16
	jmp .Llf_err_end

	/* handle error during segment adjustment */
.Llf_err_segment_overflow:
	movw $(elf32_load_file_err_segmentoverflow), %ax
	call puts16
	jmp .Llf_err_end

	/* unlikely event of program headers being away from ELF header of more than blocksize */
.Llf_err_phdr_toodeep:
	pushl (l_ext2_sb_blocksize)
	pushl %edi
	pushw $(elf32_load_file_err_phdr_too_deep)
	call printf16
	addw $10, %sp
	jmp .Llf_err_end

	/* PT_LOAD segment requires page aligned addresses */
.Llf_err_loadaddr_notaligned:
	pushl P_PADDR(%edi)
	pushw $(elf32_load_file_err_laddr_notaligned)
	call printf16
	addw $6, %sp
	jmp .Llf_err_end

	/* we need to load the segment below <1MB as we are using "flat" model even in realmode */
.Llf_err_loadaddr_toohigh:
	pushl P_PADDR(%edi)
	pushw $(elf32_load_file_err_laddr_high)
	call printf16
	addw $6, %sp
	// fall through

.Llf_err_end:
	movw $1, %ax

.Llf_end:
	addl $32, %esp
	popl %ebp
	popl %ebx
	popl %edi
	popl %esi
	ret
.endfunc


/* int elf32_check_header(elf32hdr* header)
 *
 * return 0 if all OK
*/
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
	movw %ax, (w_e_shstrndx)				/* NOTE: unsuned */

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
	elf32_load_file_msg1:			.asciz	"Loading kernel\r\n"
	elf32_load_file_err_laddr_high:		.asciz	"ELF32: address 0x%lx above 1MB limit, unable to load.\r\n"
	elf32_load_file_err_laddr_notaligned:	.asciz	"ELF32: address 0x%lx not PAGE aligned, unable to load.\r\n"
	elf32_load_file_err_phdr_too_deep:	.asciz	"ELF32: e_phoff (0x%lx) >= blocksize (0x%lx)\r\n"
	elf32_load_file_err_inodeseek:		.asciz	"ELF32: error in inode seek.\r\n"
	elf32_load_file_err_segmentoverflow:	.asciz	"ELF32: segment register overflow.\r\n"
	elf32_load_file_err_unaligned_ofst:	.ascii	"ELF32: unaligned file offset to a segment.\r\n"
						.ascii	"Offset\t\tPhysAddr\tFileSiz\t\tMemSiz\r\n"
						.asciz	"0x%lx\t\t0x%lx\t\t0x%lx\t\t0x%lx\r\n"


	.ifdef DEBUG_VERBOSE
		elf32_ch_info:	.asciz	"program header entries: %d, starting at 0x%x, entry: 0x%x\r\n"
		elf32_lf_info:	.asciz	"elf32_load_file: file size: 0x%lx bytes, spread on %d %d-byte blocks\r\n"
		elf32_lf_dbg1:	.asciz	"phdr: type: 0x%lx, offset: 0x%lx, paddr: 0x%lx, filesize: 0x%lx\r\n"
		elf32_lf_dbg2:	.asciz	"P_FILESZ: 0x%lx/0x%lx (blocks/leftovers)\r\n"
		elf32_lf_dbg3:	.asciz	"dst segment: 0x%x\r\n"
	.endif
