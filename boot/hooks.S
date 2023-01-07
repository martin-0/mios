
	.set	IDT_OFST_UD2, 	0x18

.section .text
	.code16

.func init_ud2
h_isr_init_ud2:
	pushw %bx
	xorw %bx,%bx

	cli

	movw IDT_OFST_UD2(%bx), %ax			/* save old vector */
	movw %ax, (orig_vec_ud2)
	movw (IDT_OFST_UD2+2)(%bx), %ax
	movw %ax, (orig_vec_ud2+2)

	movw (h_isr_init_ud2), %ax
	movw %ax, (orig_vec_ud2)			/* cs is 0, no need to update */

	sti
	popw %bx
	ret
.endfunc

.func hook_isr_ud2
h_isr_ud2:
	iret
.endfunc

.section .data
	
	orig_vec_ud2:	.long 0
