/* martin */

/* ABI: cdecl: args on stack, scratch registers: ax cx dx */
/* ABI: regparm=3: ax,dx,cx ; variadic function still uses stack */

// XXX: I should maybe get rid of func32 functions. While they operate on 32b regs
// XXX:	I can't address mem > 0xffff with them.

	.set TABSPACE,	4

.section .text
	.code16

/* -============================-
 *				*
 *	string functions	*
 *				*
 * -============================-
*/

/* void puts16(char* ptr) */
.global puts16
.func puts16
puts16:
	pushw %si
	pushw %bx

	xorw %dx, %dx			/* com0 */
        xorw %bx, %bx
	movw %ax, %si			/* ds:si  string to print */

	movw (comconsole), %cx
0:
        lodsb
        testb %al, %al
        jz 1f

        mov $0x0e, %ah			/* int 0x10, AH=0Eh: teletype output */
        int $0x10

	jcxz 0b				/* no serial console */
	call write_com0			/* send byte to a com0 */
        jmp 0b
1:
	popw %bx
        popw %si
        ret
.endfunc


/* void printf16(char* fmt, ...)
 *
 * variadic function overwrites regparm(3) attribute
*/
.global printf16
.func printf16
printf16:
	pusha				/* save them all */
	movw %sp, %bp			/* local vars can be addressed using bp (ss segment) */
	subw $2, %sp			/* reserve space for variable(s) */
	movw 0x12(%bp), %si		/* si = string to print */
	leaw 0x14(%bp), %di		/* di = points to arguments ; 0x10(pusha), 0x02 (near call), 0x02 - fmt */
	cld

.Lbigloop:
	lodsb
	test %al, %al
	je .Lendprintf

	cmp $0x25, %al			/* test for % char */
	je .Lfmt

.Ltab:
	cmp $0x09, %al			/* handle tabs */
	jne .Lputc

	// t = TABSPACE - (cursx % TABSPACE);
	movw $0x450, %bx		/* BDA: cursor position */
	movw $TABSPACE, %cx		/* cx = TABSPACE */
	xor %dx, %dx
	movzxb (%bx), %ax		/* ax = current x pos */
	div %cx
	subw %dx, %cx			/* how many spaces do we need to print */

.Ltab_print:
	movw $0x0e20,%ax
        int $0x10

	pushw %ax
	movw (comconsole), %ax
	testw %ax,%ax
	popw %ax
	jz .Ltab_print.1

	call write_com0			/* %al: char to print */

.Ltab_print.1:
	loop .Ltab_print
	jmp .Lbigloop

.Lfmt:
	/* 
	 *  Known formats:
	 *	%	- actual %
	 *	s	- string
	 *	x X	- hex number
	 *	lx lX	- print 32b number
	 *	p	- pointer
	 *	d	- signed integer
	 *	u	- unsigned integer
	 *	c	- character
	 */

	/* compare next char against known formats */
	lodsb
	cmp $0x25, %al			/* %% */
	je .Lputc

	/* Check for known formats. %di moves up after each successfull FMT handling */
.Lfmt_lXx:
	cmpb $0x6c, %al			/* l */
	jne .Lfmt_s

	/* only %lx or %lX are valid formats */
	lodsb
	movb $0x27, -2(%bp)		/* tmp = 0x27, a-f */
	cmpb $0x78, %al			/* %lx */
	jne .Lfmt_lX

.Lfmt_lx:
	// XXX: this is all dirty hack, i should do this in better way and for decimals too
	movw %ss:2(%di), %dx		/* upper half */
	movw -2(%bp), %ax		/* ax is non-zero value */
//	movw %ax, %cx			/* set cx with it to indicate to print leading 0s */
	xorw %cx,%cx			/* don't print leading 0s */
	call printf16_helper_x

	xorw %cx,%cx
	testw $0, %ss:2(%di)
	cmovnz %ax, %cx			/* print leading 0s only if upper half was non-zero */

	movw %ss:(%di), %dx		/* lower half */
	movw -2(%bp), %ax
	movw %ax, %cx
	call printf16_helper_x

	addw $4, %di
	jmp .Lbigloop

.Lfmt_lX:
	cmpb $0x58, %al			/* %lX */
	jne .Lputc			/* if anything else print char (but not %) */
	subw $0x20, -2(%bp)		/* tmp -= 0x20, adjust for A-F */
	jmp .Lfmt_lx

.Lfmt_s:
	cmp $0x73, %al			/* %s */
	jne .Lfmt_Xx			/* next fmt */

	movw %ss:(%di), %ax		/* bp:di points to current arg, ds:ax*/
	call puts16
	addw $2, %di			/* advance counter */
	jmp .Lbigloop

.Lfmt_Xx:
	movw $0x27, -2(%bp)		/* tmp = 0x27, set for a-f */
	cmp $0x78, %al			/* %x */
	je .Lfmt_x

	cmp $0x58, %al			/* %X */
	jne .Lfmt_p			/* next fmt */
	subw $0x20, -2(%bp)		/* tmp -= 0x20, adjust for A-F */

.Lfmt_x:
	xorw %cx, %cx
.Lfmt_x.1:
	movw %ss:(%di), %dx
	movw -2(%bp), %ax
	call printf16_helper_x

	addw $2, %di			/* advance counter */
	jmp .Lbigloop

.Lfmt_p:
	cmpb $0x70, %al			/* %p */	
	jne .Lfmt_u
	xorw %cx,%cx			/* print leading 0s */
	inc %cx
	jmp .Lfmt_x.1			/* then treat as %x */

.Lfmt_u:
	cmpb $0x75, %al			/* %u */
	jne .Lfmt_d

.Lfmt_u.1:
	movw %ss:(%di), %ax		/* ax = hex number to print */
	movw %ax, -2(%bp)		/* store in stack for later */

.Lfmt_u.2:
	movw $10000, %bx		/* we start dividing by 10000, max that can fit into 16b number */
	xorw %cx, %cx			/* bool flag if we started printing already, to avoid leading 0s */

.Lfmt_u.loop:
	movw -2(%bp), %ax		/* get the MSB of the number */
	xorw %dx, %dx
	div %bx

	testb %cl, %cl			/* did we print any char yet? */
	jnz .Lfmt_u.loop.1

	cmp $1, %bx			/* are we printing the last digit already */
	je .Lfmt_u.loop.1

	testb %al, %al			/* if not, is this char also 0 */
	jz .Lfmt_u.loop.2
	inc %cx				/* no, indicate we are printing number */

.Lfmt_u.loop.1:
	push %bx
	push %ax
	movb $0x0e, %ah			/* print char */
	addb $0x30, %al			/* ASCII code: 0x30+digit */
	int $0x10

	pushw %ax
	movw (comconsole), %ax
	testw %ax,%ax
	popw %ax
	jz 1f
	call write_com0

1:
	pop %ax
	pop %bx

.Lfmt_u.loop.2:
	xorw %dx,%dx			/* we dont't care about reminder */
	mul %bx				/* substracting the 10x number from original number */
	movw -2(%bp), %dx	
	subw %ax, %dx			/* new number to divide */
	movw %dx, -2(%bp)		/* store it for reference in loop */

	xorw %dx, %dx			/* decrease the divisor */
	movw %bx, %ax
	movw $10, %bx
	div %bx
					/* XXX: I could probably stop one loop sooner as dx has the reminder */	
					/* TODO: ?? */
	test %ax, %ax			/* stop if it's 0 */
	movw %ax, %bx
	jnz .Lfmt_u.loop

	addw $2, %di			/* advance counter */
	jmp .Lbigloop

.Lfmt_d:
	cmp $0x64, %al			/* %d */
	jne .Lfmt_c

	movw %ss:(%di), %ax		/* load the number */
	test $0x8000, %ax		/* test the MSB */
	jz .Lfmt_u.1			/* if not set proceed as unsigned int */

	neg %ax				/* get the 2's complement */
	movw %ax, -2(%bp)		/* store it on stack */
	jmp .Lfmt_u.2			/* proceed as unsigned int */

.Lfmt_c:
	cmp $0x63, %al			/* %c */
	jne .Lnofmt

	movb %ss:(%di), %al		/* load the character */
	inc %di
	/* fall through to .Lputc .. testing for c has to be the last format check */

.Lnofmt:
.Lputc:
	movb $0x0e,%ah
	int $0x10

	pushw %ax
	movw (comconsole), %ax
	testw %ax,%ax
	popw %ax
	jz .Lbigloop
	call write_com0
	jmp .Lbigloop

.Lendprintf: 
	addw $2, %sp
	popa
	ret

.endfunc

/* void printf16_helper_x(uint16_t islower, uint16_t nr, uint16_t lz)
 *
 * Intened to be called by printf16 only.
 *	islower: print a-f or A-F, nr: number to print, lz: print leading zeros
*/
.func printf16_helper_x
printf16_helper_x:
	pushw %si
	pushw %di
	pushw %bx

	/* dx already set to number to print */
	movw %ax, %di			/* islower offset */

	movw %cx, %si			/* leading 0s */
	movw $4,%cx			/* max digits in 16b nr */

	xor %bx,%bx			/* set for int 0x10/AH=0Eh print */
.Lhelpx_loop:
	rolw $4, %dx			/* start from the MSB */
	movb %dl, %al
	andb $0xf, %al

	test %si, %si			/* did we print something already? */
	jnz .Lhelpx.2			/* if so continue printing */

	cmpb $1, %cl			/* is this the last digit already? */
	je .Lhelpx.2			/* if so print the 0 */

	testb %al, %al			/* is this a leading zero ? */
	jnz .Lhelpx.1			/* no more leading 0s */
	loop .Lhelpx_loop

.Lhelpx.1:
	inc %si				/* no, it's not 0 */

.Lhelpx.2:
	cmp $0xa, %al			/* are we printing digit or a-f */
	jb .Lhelpx.3
	addw %di, %ax			/* print char += offset */

.Lhelpx.3:
	addb $0x30, %al
	movb $0x0e, %ah
	int $0x10

	pushw %ax
	movw (comconsole), %ax
	testw %ax,%ax
	popw %ax
	jz .Lhelpx_comcons

	call write_com0

.Lhelpx_comcons:
	loop .Lhelpx_loop

	pop %bx
	pop %di
	pop %si
	ret
.endfunc


/* int16_t strlen16(char* str) */
.global strlen16
.func strlen16
strlen16:
	push %di
	movw %ax, %di			/* str */

	xor %ax,%ax			/* scasb compares against al */
	xor %cx,%cx			/* set the counter to 0xffff */
	dec %cx
	repne scasb			/* search for 0 in the es:di string */

	inc %cx				/* we had to decrease cx by one */
					/* cx got decremented once more when 0 byte was tested */
	not %cx				/* we can compensate for that by doing 1's complement */
	xchg %cx, %ax

	pop %di
	ret
.endfunc


/* int16_t strcmp16(char* s1, char* s2) */
.global strcmp16
.func strcmp16
strcmp16:
	push %si
	push %di

	movw %ax, %si
	movw %dx, %di

	/* ax still has arg1 */
	call strlen16			/* determine the size of the s1 string */
	mov %ax, %cx			/* set the loop count ; acts as strncmp from now on */
	xor %ax, %ax
1:
	repe cmpsb
	test %cx, %cx			/* we finished looking through the string */
	jz 2f
	
	dec %si				/* rollback si back */
	dec %di				/* rollback di back */

2:
	lodsb				/* load ds:si into al */
	subb %es:(%di), %al		/* al is 0 if bytes are the same */

	pop %di
	pop %si
	ret
.endfunc

/* int16_t strncmp(char* src, char* dst, int16_t len) */
.global strncmp16
.func strncmp16
strncmp16:
	push %si
	push %di

	movw %ax, %si
	movw %dx, %di				/* cx is set as 3rd argument */
	test %cx,%cx				/* don't start the comparison if cx is 0 */
	jnz .Lcmp
	xor %ax,%ax				/* return 0 */
	jmp .Lend

.Lcmp:
	test %cx, %cx				/* are we done yet? */
	jz .Lcmp_end

	cmpsb					/* compare ds:si with es:di at most cx times */
	jne .Lcmp_end

	dec %si
	lodsb					/* test if one of the string is 0 already */
	test %al, %al
	jz .Lcmp_end
	dec %cx					/* check next char */
	jmp .Lcmp

.Lcmp_end:					/* cmpsb inc si/di, we need it for ret val */
	dec %si
	dec %di
	xor %ax, %ax
	lodsb
	sub %es:(%di), %al

.Lend:
	pop %di
	pop %si
	ret
.endfunc


/* int16_t memcmp16(char* s1, char* s2, uint16_t n) */
.global memcmp16
.func memcmp16
memcmp16:
	pushw %si
	pushw %di

	movw %ax, %si
	movw %dx, %di				/* cx is already set */

	xor %ax,%ax				/* prepare the return value */
	repe cmpsb				/* compare cx times */
	test %cx,%cx				/* was it the same cx times ? */
	jz .Lmemcmp_end

	dec %si					/* rollback both si and di */
	dec %di					/* so we can return expected val */

	lodsb					/* load ds:si */
	subb %es:(%di), %al			/* sub es:di from it */

.Lmemcmp_end:
	pop %di
	pop %si
	ret
.endfunc

/* void memcpy16(void *dst, void* src, uint16_t bytes)
 *
 * copy n bytes from source to destination.
*/
.global memcpy16
.func memcpy16
memcpy16:
	pushw %si
	pushw %di

	movw %ax, %di
	movw %dx, %si				/* cx is already set */

.Lmemcpy:
	lodsb
	stosb
	loop .Lmemcpy

	movw %dx, %ax				/* ret ptr to dst */
	pop %di
	pop %si
	ret
.endfunc


/* void memcpyw16(void *dst, void* src, uint16_t n-words)
 *
 * copy n words from source to destination.
*/
.global memcpyw16
.func memcpyw16
memcpyw16:
	pushw %si
	pushw %di

	movw %ax, %di
	movw %dx, %si				/* cx is already set */

.Lmemcpyw:
	lodsw
	stosw
	loop .Lmemcpyw

	movw %dx, %ax				/* ret ptr to dst */
	pop %di
	pop %si
	ret
.endfunc

/* void* memset16(char* dst, uint16_t c, uint16_t n)
 *
*/
.global memset16
.func memset16
memset16:
	pushw %di

	push %ax
	movw %ax, %di				/* dst */
	movw %dx, %ax				/* c */
						/* cx is already set */
	rep stosb

	pop %ax					/* return val is dst */
	pop %di
	ret
.endfunc


/* char* strtok16(char* str, char* delim)
 *
*/
.global strtok16
.func strtok16
strtok16:
	pushw %si
	pushw %di
	pushw %bx

	cld
	test %ax,%ax			/* check if str == NULL */
	jz .Lstrtok_loadptr

	movw %ax, %si			/* si: str */
	xor %ax, %ax
	mov %ax, (__strtok_nextptr)	/* __strtok_nextptr = NULL */
	jmp .Lstrtok_1

.Lstrtok_loadptr:
	movw (__strtok_nextptr), %si

.Lstrtok_1:
	test %si,%si
	jz .Lstrtok_retnull

	movw %si, %cx			/* save str */
	movw %dx, %bx			/* save delim */

	movw %dx, %di			/* load di with delim */
.Lstrtok_trim:				/* trim any delims from the start of the string */
	lodsb
	testb %al, %al
	jz .Lstrtok_retnull		/* we hit end of str when parsing delims */

.Lstrtok_trim.inner:			/* go through all delim[] */
	movb (%di), %dl
	testb %dl, %dl			/* did we hit end of delim */
	jz .Lstrtok_trim_end		/* if yes we're done with the trimming */

	cmpb (%di), %al
	je .Lstrtok_trim		/* continue with trimming */

	inc %di				/* next delim char */
	jmp .Lstrtok_trim.inner

.Lstrtok_trim_end:
	dec %si				/* lodsb increments si automatically */
	movw %si,%cx			/* si has correct start of str, store it */

.Lstrtok_main:
	lodsb
	testb %al, %al
	jz .Lstrtok_final_done		/* end of string, we're completely done */

	movw %bx, %di			/* reset di back to start of delim */
.Lstrtok_main_inner:			/* check all delims */
	movb (%di), %dl
	testb %dl, %dl
	jz .Lstrtok_main		/* end of delims, try next char in str */
	cmpb %dl, %al
	je .Lstrtok_main_done
	inc %di
	jmp .Lstrtok_main_inner

.Lstrtok_main_done:
	xor %ax, %ax
	movw %si, (__strtok_nextptr)	/* next ptr will start in place of si+1 */
	dec %si
	movb %al,(%si)			/* mark the end of str where delim was */
	movw %cx, %ax			/* return val is the orig trimmed str */
	jmp .Lstok_end

.Lstrtok_final_done:
	xor %ax, %ax
	movw %ax, (__strtok_nextptr)
	movw %cx, %ax
	jmp .Lstok_end

.Lstrtok_retnull:
	xor %ax, %ax

.Lstok_end:
	pop %bx
	pop %di
	pop %si
	ret
.endfunc

/* -====================================-
 * 					*
 *	A20 gate related functions	*
 *					*
 * -====================================-
*/

/* int16_t A20check16()
 *
 * Check if A20 gate is enabled.
 * Two memory locations - 0x600 and 0x100600 - are written into but not restored.
 * It's assumed that during the check neither of the memory locations are used.
 *
 * return val in %ax: 0: A20 is enabled, 1: A20 is disabled
*/
.global A20check16
.func A20check16
A20check16:
	push %ds
	push %es
	push %di
	push %si

	.ifdef DEBUG_A20		/* we need to reference stack vars */
		push %bp		/* only if we need to print */
		movw %sp, %bp
	.endif

	xorw %ax, %ax
	movw %ax, %ds			/* set ds to 0 */
	dec %ax
	movw %ax, %es			/* set es to 0xffff */

	movw $0x600, %si		/* ds:si points to 0000:600 -> 0x600 */
	movw $0x610, %di		/* es:di points to ffff:610 -> 0x100600 */

	movb %al, %ds:(%si)		/* 0000:600 = 0xff */
	inc %ax				/* set ax back to 0 */
	movb %al, %es:(%di)		/* ffff:610 = 0 */

	cmpb $0xff, %ds:(%si)
	setne %al			/* if ds:si is the same A20 gate is enabled */

	/* print the debugging information if DEBUG_A20 is enabled */
	.ifdef DEBUG_A20
		pushw %ax		// save return value
		movw %es:(%di), %ax
		andw $0xff, %ax
		pushw %ax		// +2
		pushw %di		// +2
		pushw %es		// +2

		movw %ds:(%si), %ax
		andw $0xff, %ax
		pushw %ax		// +2
		pushw %si		// +2
		pushw %ds		// +2

		movw 8(%bp), %ds	/* load the ds back to what is was saved */
		pushw $((dbg_a20_test))
		call printf16
		addw $14, %sp
		pop %ax		// ret val

		pop %bp
	.endif

	pop %si
	pop %di
	pop %es
	pop %ds
	ret
.endfunc

/* int16_t A20e_bios()
 *
 * Try to enable A20 gate with the BIOS call.
 * return val in %ax: 0: call was successfull, non-zero error code otherwise.
*/
.global A20e_bios
.func A20e_bios
A20e_bios:
	movw $0x2401, %ax		/* BIOS call int 0x15 : enable A20 gate */
	int $0x15			/* AX: 0x2401 */
	jc 1f				/* error if CF is set */
	xor %ax, %ax
	jmp 2f
1:
	movb %ah, %al
	andw $0xff, %ax
2:
	ret
.endfunc

/* void A20e_fast()
 *
 * Try to enable A20 gate with the fast port.
 * Doesn't return anything. A20 test has to be done after this. 
*/
.global A20e_fast
.func A20e_fast
A20e_fast:
	inb $0x92, %al			/* read the current value from System port A on 8204 ctrl */
	orb $2, %al			/* bit1: enable A20 gate */
	andb $0xfe, %al			/* make sure bit0 - system reset - is 0 */
	outb %al, $0x92
	ret
.endfunc

/* void A20e_kbd()
 *
 * Try to enable A20 gate via 8042 keyboard controller.
*/

/*	port 0x60 read:		read input buffer
 *	port 0x60 write: 	write output buffer
 *	port 0x64 read:		read status register
 *	port 0x64 write:	send command to controller
*/
.global A20e_kbd
.func A20e_kbd
A20e_kbd:
	call wait_clear_8042

	movb $0xd1, %al			/* request write from the kbd port */
	outb %al, $0x64
	call wait_clear_8042

	movb $0xdf, %al
	outb %al, $0x60
	call wait_clear_8042

	movb $0xff, %al			/* NULL command, inspired by Linux */
	outb %al, $0x64

	ret
.endfunc

/* int16_t wait_clear_8042()
 *
*/
.global wait_clear_8042
.func wait_clear_8042
wait_clear_8042:
	xor %ax, %ax	
	xor %dx, %dx			/* err count */
	xor %cx, %cx
	dec %cx				/* max loop counter */

.Lloop:
	outb %al, $0x80			/* dummy delay; https://groups.google.com/g/linux.kernel/c/UTKlqyBFiyU */
	in $0x64, %al
	
	cmp $0xff, %al			/* no kbc ; expired by Linux */
	jne .Lloop.1
	inc %dx
	cmpb $32, %dl
	jge .Lreterr
	jmp .Lloop

.Lloop.1:
	test $1, %al			/* bit0: output buffer full */
	jne .Lloop.2
	outb %al, $0x80			/* delay */
	in $0x60, %al			/* discard the read, we don't care about the buffer */

.Lloop.2:
	test $2, %al			/* bit1: input buffer full (can't write yet) */
	jz .Lretok
	loop .Lloop
	jmp .Lreterr			/* if main loop is over we are done, report error */

.Lretok:	
	xor %ax, %ax
	jmp .Lend8042
	
.Lreterr:
	xor %ax, %ax
	neg %ax	

.Lend8042:
	ret
.endfunc

/* int16_t enable_A20()
 *
 * try all defined options to enable the A20 gate
*/
.global enable_A20
.func enable_A20
enable_A20:
	call A20check16			/* return success if A20 is already enabled */
	test %ax, %ax
	jz .LeA20end

	call A20e_bios			/* try to use BIOS */
	test %ax, %ax
	jz .LeA20end

	call A20e_kbd			/* try kbd controller */
	call A20check16
	test %ax, %ax
	jz .LeA20end

	call A20e_fast			/* try fast port to enable A20 */
	call A20check16
	test %ax, %ax
	jz .LeA20end

	movb $0xff, %al			/* fatal error */
	jmp .LeA20end

.LeA20endOK:
	xor %ax, %ax		
.LeA20end:
	ret
.endfunc

/* -============================-
 *				*
 *	memory-probe functions	*
 *				*
 * -============================-
*/

/* void detect_low_mem() */
.global detect_low_mem
.func detect_low_mem
detect_low_mem:
	clc
	int $0x12
	jnc 1f				/* in case of an error */
	xorw %ax, %ax			/* return 0B memory */
1:
	ret
.endfunc


/* getmem_e820( smap ) */
/* to be executed in real-mode on i386 computer */
.global getmem_E820
.func getmem_E820
getmem_E820:
	pushl %esi
	pushl %edi
	pushl %ebx
	pushl %ebp
	movl %esp, %ebp
	movw 12(%bp), %di

	xorl %esi, %esi				/* entry count */

.Lfirst_try:
	leaw (smap_data), %di
	xorl %ebx, %ebx
	xorl %ecx, %ecx
	movb $24, %cl				/* forcing 24b acpi 3 */
	movl $0x534d4150, %edx			/* SMAP */
	movl $0xe820, %eax			/* to make sure upper half of eax is 0 */
	int $0x15
	jc .Le820unsupported

	movl $0x534d4150, %edx			/* some BIOSes trash this ? */
	cmpl %edx, %eax
	jnz .Le820unsupported

	movzx %cl, %ecx	
	movl %ecx, (smap+4)			/* save the entry size */

.Lget_entries:
	xorw %ax, %ax				/* prep for return code */
	test %ebx, %ebx				/* already finished ? */
	jz .LE820end

	cmpb $20, %cl				/* do we have extended acpi attr? */
	jbe .Lnoext

	testb $1, %es:20(%di)			/* extended atrribute, bit0: 0 : skip */
	jz .Lskip

.Lnoext:
	movl %es:8(%di), %eax
	or %es:12(%di), %eax			/* check the len */
	jz .Lskip

	inc %esi				/* entries++ */
	addw $24, %di

	cmpl $64, %esi				/* we don't have buffer for 64+ */
	jg .Ltoomany				/* max entries reached */

.Lskip:
	movb $24, %cl				/* forcing 24b acpi 3 */
	movl $0x534d4150, %edx			/* SMAP */
	movw $0xe820, %ax
	int $0x15
	jnc .Lget_entries
	jmp .Le820unsupported			/* handle error */

.Ltoomany:					/* too many entries, log it but end as success */
	leaw (e820_err_entries), %ax
	call puts16				/* warn about it but don't report error */
	xor %ax, %ax
	jmp .LE820end

.Le820unsupported:
	shr $8, %ax
	and $0xff, %ax

.LE820end:
	movl %esi, (smap)			/* save entries */
	popl %ebp
	popl %ebx
	popl %edi
	popl %esi
	ret
.endfunc

/* -============================-
 *				*
 *	PIC and PIT functions	*
 *				*
 * -============================-
*/

/* void init16_8259() */
.global init16_8259
.func init16_8259
init16_8259:
	/* ICW1 */
	mov $0x11, %al				/* let's init PIC, use 4 W */
	out %al, $0x20				/* PIC master */
	out %al, $0xa0				/* PIC slave */
	outb %al, $0x80				/* delay */

	/* ICW2 */
	mov $0x20, %al				/* IRQ0 to int 0x20 */
	out %al, $0x21
	mov $0x28, %al				/* IRQ8 to int 0x28 */
	out %al, $0xa1
	outb %al, $0x80

	/* ICW3 */
	mov $0x4, %al				/* master: IRQ2 slave */
	out %al, $0x21
	mov $0x2, %al				/* slave: master at (bit notation): 010: 2 */
	out %al, $0xa1
	outb %al, $0x80

	/* ICW4 */
	mov $1, %al
	out %al, $0x21
	out %al, $0xa1
	outb %al, $0x80

	ret
.endfunc


/* -============================-
 *				*
 *	debug functions		*
 *				*
 * -============================-
*/

.global dump_regs
.func dump_regs
dump_regs:
	/* dumping all regs first to get as much accurate state as possible */
	pushw %ds
	pusha				/* +16: ax, cx, dx, bx, orig sp, bp, si, di */
	pushw %gs
	pushw %fs
	pushw %es
	pushw %ds
	pushw %ss
	pushw %cs
	pushf 				/* flags */
	call 1f				/* +32 %ip */
1:
	movw %sp, %bp
	/* reorder the registers according to the printf arguments */
	pushw 16(%bp)			/* di */
	pushw 18(%bp)			/* si */
	pushw 20(%bp)			/* bp */
	pushw 22(%bp)			/* sp */
	pushw 24(%bp)			/* bx */
	pushw 26(%bp)			/* dx */
	pushw 28(%bp)			/* cx */
	pushw 30(%bp)			/* ax */

	xorw %ax,%ax			/* ds=0 required for printing */
	movw %ax, %ds
	pushw $(dbg_regs)
	call printf16

	/* while I do have ds saved on stack it's faster just to push-pop */
	addw $34, %sp			/* roll back the stack; we don't care about flags */
	popa				/* restore orig registers */
	pop %ds				/* restore ds */
	ret
.endfunc

/* void dump_mem16(void* addr, int16_t nblocks)
 *
 * Dump nblocks words of addr */
.global dump_mem16
.func dump_mem16
dump_mem16:
	push %si
	push %di
	push %bx

	movw %ax, %si				/* addr */
	movw %dx, %di				/* blocks */
	xorw %bx, %bx				/* counter */

	pushw %si
	pushw $(dump_mem_addr)
	call printf16

.Ldump_loop:
	lodsw
	push %ax
	push $(dump_mem_val)
	call printf16
	addw $4, %sp

	inc %bx
	cmpw %bx, %di
	jbe .Ldumpmem_end

	testw $3, %bx
	jnz .Ldump_loop
	pushw %si
	pushw $(dump_mem_addrnl)
	call printf16
	addw $4, %sp

.Ldumpmem.1:
	jmp .Ldump_loop

.Ldumpmem_end:
	pushw %si
	pushw $(dump_mem_addr_end)
	call printf16
	addw $8, %sp

	pop %bx
	pop %di
	pop %si
	ret
.endfunc

/* -============================-
 *                              *
 *	basic I/O functions	*
 *				*
 * -============================-
*/

/* int16_t diskread16(int16_t disk, struct lba_dap_t* dap) */
.global diskread16
.func diskread16
diskread16:
	pushw %si

	movw %dx, %si				/* dap */
	movw %ax, %dx				/* disk drive */
	movw $0x4200, %ax			/* int 0x13, AH=42h: extended read */
	int $0x13

	movb %ah, (errno16)
	setc %al

	popw %si
	retw
.endfunc

/* void* diskinfo16(char* buf, int16_t disk, char eddver)
 *
 * Returns buffer filled up with the diskinfo, NULL otherwise.
 *
 * NOTE: first byte of buffer requires to have its size set
 *	http://www.ctyme.com/intr/rb-0715.htm
 *	001Ah for v1.x, 001Eh for v2.x, 42h for v3.0
*/
.global diskinfo16
.func diskinfo16
diskinfo16:
	push %si

	movw %ax, %si				/* buf */
						/* dx = disk: already set */
						/* cx = eddver: already set */
	cmpb $3, %cl
	jne .Ltry2
	movw $0x42, %ax
	jmp .Ldo48

.Ltry2:
	cmpb $2, %cl
	jne .Ltry1
	movw $0x1e, %ax
	jmp .Ldo48

.Ltry1:
	cmpb $1, %cl
	jne .Lerr_param
	movw $0x1a, %ax

.Ldo48:
	movw %ax, (%si)				/* set buffer size */
	movw $0x4800, %ax
	int $0x13				/* AH=48H, int 0x13: get drive parameters */

	movb %ah, (errno16)
	jc .Ldss_end_err

	movw %si, %ax				/* set ax back to buffer if all OK */
	jmp .Ldss_end

.Lerr_param:
	movb $0x51, (errno16)			/* custom value not defined in disk op status */
.Ldss_end_err:
	xor %ax, %ax
.Ldss_end:
	pop %si
	ret
.endfunc

/* void init_com0()
 *
 * port as expected by AH=00h, int $0x14 BIOS function
*/
.global init_com0
.func init_com0
init_com0:
        xorw %dx, %dx
        movw $0xe3, %ax                                 /* port settings: 9600bps,8N1 */
        int $0x14
	ret
.endfunc

/* void write_com0(char c)
 *
 * Only al is use as a character to print.
*/
.global write_com0
.func write_com0
write_com0:
	pushw %dx
	xorw %dx,%dx					/* com0 */
	movb $0x01, %ah
	int $0x14
	popw %dx
	ret
.endfunc


/* void farmemcpy(void far* dst, void far* src, uint16_t bytes)
 *
 * NOTE: beware printf16() assumes ds=0 in its current implementation
 *
 * Arguments passed on stack:
 *	<bytes>			2
 *	<seg|ofst>		4
 *	<seg|ofst>		4
*/
.global farmemcpy
.func farmemcpy
farmemcpy:
	pushw %bp
	movw %sp, %bp
	pushw %si
	pushw %di
	pushw %es
	pushw %ds

	/* (%bp) is using ss by defualt */
	movw  4(%bp), %di
	movw  6(%bp), %es		/* dst: es:di */
	movw  8(%bp), %si
	movw 10(%bp), %ds		/* src: ds:si */
	movw 12(%bp), %cx		/* size: cx */

	testw %cx,%cx			/* end if nothing to copy */
	jz .Lfmcpy_end

	movw %cx, %dx
	shr $1, %cx			/* words we can copy */
	testw %cx,%cx
	jz .Lfmpcy_prepb

.Lfmcpy_loopw:
	lodsw
	stosw
	loop .Lfmcpy_loopw

.Lfmpcy_prepb:
	movw %dx, %cx
	test $1, %cx			/* byte leftovers */
	jnz .Lfmcpy_end

	/* there can be only single byte left with 2B words, no loop needed */
	lodsb
	stosb

.Lfmcpy_end:
	xorw %ax,%ax
	popw %ds
	popw %es
	popw %di
	popw %si

	popw %bp
	ret
.endfunc

/* void pm_copy(char* dst32, char* src32, int32_t size)
 *
 * Copy src to dst in protected mode.
 */
.global pm_copy
.func pm_copy
pm_copy:
	cli
	pushl %esi
	pushl %edi
	pushw %bp
	movw %sp, %bp

	lgdt (sa_gdt_desc)
	movl %cr0, %eax
	orl $1, %eax
	movl %eax, %cr0
	jmp $0x8, $.Lpc_pmentry

.Lpc_pmentry:
	movw $0x10, %ax
	movw %ax, %ds
	movw %ax, %es

	movl 0x14(%ebp), %ecx
	movl 0x10(%ebp), %esi
	movl 0xc(%ebp), %edi
	
	testl %ecx, %ecx			/* nothing to copy, back to RM */
	jz .Lpc_rmprep

	movl %ecx,%edx				/* save if needed later */
	shrl $2, %ecx				/* 4B words to copy */
	andl $3, %edx				/* byte leftovers, if any */

	/* if ecx is 0 nothing will be copied */
	rep movsd (%esi),(%edi)			/* copy by doublewords */
	movl %edx, %ecx				/* byte leftovers */
	rep movsb (%esi),(%edi)

.Lpc_rmprep:
	movw $0x18, %ax
	movw %ax, %ds
	movw %ax, %es

	movl %cr0, %eax				/* prepare to jump to RM again */
	dec %eax
	movl %eax, %cr0
	jmp $0, $.Lpc_rmentry

.Lpc_rmentry:
	xorl %eax,%eax
	movw %ax, %ds
	movw %ax, %es

	movw %bp, %sp
	popw %bp
	popl %edi
	popl %esi
	sti
	retw
.endfunc


/* Functions that use 32b registers. */

/* char* strcpy32(char* dst, char* src)
 *
 * Copy src to dst, terminate with null byte. Dst has to be at least len(src)+1 bytes big, no
 * checks are done
*/
.global strcpy32
.func strcpy32
strcpy32:
	pushl %esi
	pushl %edi

	movl %eax, %edi
	movl %edx, %esi
	movl %eax, %edx				/* keep the dst pointer */
	cld
.Lstrcpy32_loop:
	lodsb
	test %al, %al
	jz .Lstrcpy32_end
	stosb
	jmp .Lstrcpy32_loop

.Lstrcpy32_end:
	movb %al, (%edi)
	movl %edx, %eax
	popl %edi
	popl %esi
	ret
.endfunc


/* char* strcat32(char* dst, char* src)
 *
 * append src string into dst. append nullbyte in the end
 *
 * returns pointer to dst
*/
.global strcat32
.func strcat32
strcat32:
	pushl %esi
	pushl %edi

	movl %eax, %edi				/* edi: dst */
	movl %edx, %esi				/* esi: src */
	movl %edi, %edx				/* edx: dst store for retval */

	/* find the end of the string dst */
	xorl %ecx,%ecx
	dec %ecx		/* maximum size  */
	xorl %eax, %eax
	repne scasb
	dec %edi				/* drop the null terminating byte */

.Lscat32_loop:
	lodsb
	test %al, %al
	jz .Lscat32_end
	stosb
	jmp .Lscat32_loop

.Lscat32_end:
	movb %al, (%edi)
	movl %edx, %eax

	popl %edi
	popl %esi
	ret
.endfunc

/* int32_t strlen32(char* str) */
.global strlen32
.func strlen32
strlen32:
	pushl %edi
	movl %eax, %edi			/* edi: str */

	xorl %eax,%eax			/* scasb compares against al */
	xorl %ecx,%ecx			/* set the counter to 0xffff */
	decl %ecx
	repne scasb			/* search for al in edi */

	incl %ecx			/* we had to decrease ecx by one */
	not %ecx			/* we can compensate for that by doing 1's complement */
	xchg %ecx, %eax

	popl %edi
	ret
.endfunc

/* char* strtok32_r(char* str, char* delim, char** token)
 *
*/
.global strtok32_r
.func strtok32_r
strtok32_r:
	pushl %esi
	pushl %edi
	pushl %ebx
	pushl %ebp

	cld
	movl %ecx, %ebp			/* ebp: **token */
	testl %eax,%eax			/* check if str == NULL */
	jz .Lstrtok32r_loadptr

	movl %eax, %esi			/* esi: str */
	xorl %eax, %eax
	jmp .Lstrtok32r_1

.Lstrtok32r_loadptr:
	movl (%ebp), %esi

.Lstrtok32r_1:
	testl %esi,%esi
	jz .Lstrtok32r_retnull

	movl %esi, %ecx			/* save str */
	movl %edx, %ebx			/* save delim */

	movl %edx, %edi			/* load di with delim */
.Lstrtok32r_trim:			/* trim any delims from the start of the string */
	lodsb
	testb %al, %al
	jz .Lstrtok32r_retnull		/* we hit end of str when parsing delims */

.Lstrtok32r_trim.inner:			/* go through all delim[] */
	movb (%edi), %dl
	testb %dl, %dl			/* did we hit end of delim */
	jz .Lstrtok32r_trim_end		/* if yes we're done with the trimming */

	cmpb (%edi), %al
	je .Lstrtok32r_trim		/* continue with trimming */

	incl %edi			/* next delim char */
	jmp .Lstrtok32r_trim.inner

.Lstrtok32r_trim_end:
	decl %esi			/* lodsb increments si automatically */
	movl %esi,%ecx			/* esi has correct start of str, store it */

.Lstrtok32r_main:
	lodsb
	testb %al, %al
	jz .Lstrtok32r_final_done	/* end of string, we're completely done */

	movl %ebx, %edi			/* reset edi back to start of delim */
.Lstrtok32r_main_inner:			/* check all delims */
	movb (%edi), %dl
	testb %dl, %dl
	jz .Lstrtok32r_main		/* end of delims, try next char in str */
	cmpb %dl, %al
	je .Lstrtok32r_main_done
	incl %edi
	jmp .Lstrtok32r_main_inner

.Lstrtok32r_main_done:
	xorl %eax, %eax
	movl %esi, (%ebp)		/* ext ptr will start in place of esi+1 */
	decl %esi
	movb %al,(%esi)			/* mark the end of str where delim was */

	cmpb $0, (%ebp)
	jz .Lstrtok32r_retnull		/* if we don't have any next token return null */

	movl %ecx, %eax			/* return val is the orig trimmed str */
	jmp .Lstok32r_end

.Lstrtok32r_final_done:
	xorl %eax, %eax
	movl %eax, (%ebp)
	movl %ecx, %eax
	jmp .Lstok32r_end

.Lstrtok32r_retnull:
	xorl %eax, %eax

.Lstok32r_end:
	popl %ebp
	popl %ebx
	popl %edi
	popl %esi
	ret
.endfunc


.section .data
	.align 2
	__strtok_nextptr:		.word	0	/* used for internal tracking of str with strtok16() */

	.global b_have_serial_com0
	b_have_serial_com0:		.byte 0

	/* GDT used during PM copy */
	.align 8
	sa_gdt_desc:	.word sa_gdt_end-sa_gdt-1		/* size */
			.word sa_gdt, 0				/* linear address, ptr to gdt */
	.align 8
	sa_gdt:
		/* base:	32b value, linear address where the segment begins
		 * limit:	20b value, maximum addressable unit, either 1B units or 4k pages
		 * access:	description of segment: P | DPL  | S | E | DC | RW | A
		 * flags:	granularity, db (size flag, 1B or 4k pages), long mode flag, reserved (0)
		 */
		.space	8		/* NULL desc */

		/* %cs in 16b protected mode */
		.word 0xffff		/* limit bits 0-15 */
		.word 0			/* base 0-15 */
		.byte 0x0		/* base 16-23 */
		.byte 0x9a		/* access: RTL: present, ring0, code segment, executable, grows up, rx, accessed=0 */
		.byte 0xf		/* RTL: flags-limit 16-19: , flags: 16b protected mode segment, byte granularity */
		.byte 0			/* base 24-31 */

		/* data in full 32b PM mode */
		.word 0xffff		/* limit bits 0-15 */
		.word 0			/* base 0-15 */
		.byte 0x0		/* base 16-23 */
		.byte 0x92		/* access: RTL: present, ring0, data segment, non-exec, grows up, rw, accessed=0 */
		.byte 0xcf		/* RTL: flags-limit 16-19: , flags: 32b protected mode segment, page granularity */
		.byte 0			/* base 24-31 */

		/* data in real mode */
		.word 0xffff		/* limit bits 0-15 */
		.word 0			/* base 0-15 */
		.byte 0x0		/* base 16-23 */
		.byte 0x92		/* access: RTL: present, ring0, data segment, non-exec, grows up, rw, accessed=0 */
		.byte 0x0		/* RTL: flags-limit 16-19: , flags: 16b protected mode segment, byte granularity */
		.byte 0			/* base 24-31 */

	sa_gdt_end:

	/* dump without tabs */
	dbg_regs_notabs:
		.ascii	"--------\r\n"
		.ascii	"ax:        0x%x\r\n"
		.ascii	"cx:        0x%x\r\n"
		.ascii	"dx:        0x%x\r\n"
		.ascii	"bx:        0x%x\r\n"
		.ascii	"sp:        0x%x\r\n"
		.ascii	"bp:        0x%x\r\n"
		.ascii	"si:        0x%x\r\n"
		.ascii	"di:        0x%x\r\n"
		.ascii	"ip:        0x%x\r\n"
		.ascii	"flags:     0x%x\r\n"
		.ascii	"cs:        0x%x\r\n"
		.ascii	"ss:        0x%x\r\n"
		.ascii	"ds:        0x%x\r\n"
		.ascii	"es:        0x%x\r\n"
		.ascii	"fs:        0x%x\r\n"
		.ascii	"gs:        0x%x\r\n"
		.asciz	"--DUMP--\r\n"

	/* dump with tabs */
	dbg_regs:
		.ascii	"-- regs --\r\n"
		.ascii	"ax: 0x%p\tcx: 0x%p\tdx: 0x%p\tbx: 0x%p\r\n"
		.ascii	"sp: 0x%p\tbp: 0x%p\tsi: 0x%p\tdi: 0x%p\r\n"
		.ascii	"ip: 0x%p\tflags: 0x%p\r\n"
		.ascii	"cs: 0x%p\tss: 0x%p\tds: 0x%p\tes: 0x%p\r\n"
		.asciz	"fs: 0x%p\tgs: 0x%p\r\n"

	e820_err_entries:	.asciz	"Too many memory entries (64+) detected!\r\nMemory map is not complete.\r\n"

	.ifdef DEBUG_A20
		dbg_a20_test:	.asciz	"%p:%p    0x%x\r\n%p:%p    0x%x\r\nax: 0x%x\r\n"
	.endif

	dump_mem_addr:		.asciz	"0x%x\t"
	dump_mem_addr_32:	.asciz	"0x%lx\t"

	dump_mem_addrnl:	.asciz	"\r\n0x%x\t"
	dump_mem_addrnl_32:	.asciz	"\r\n0x%lx\t"

	dump_mem_addr_end:	.asciz	"\r\n0x%x\r\n"
	dump_mem_addr_end_32:	.asciz	"\r\n0x%lx\r\n"
	dump_mem_val:		.asciz	"\t%p"
	dump_mem_val_32:	.asciz	"\t0x%lx"

	.global errno16
	errno16:	.byte 0
