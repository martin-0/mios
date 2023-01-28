#ifndef HAVE_TYPES_H
#define	HAVE_TYPES_H

#include <stdint.h>

#define	RINGBUF32_SIZE		32

#define	DEFINE_RING32(name, type)			\
	struct { 					\
		unsigned int ri:5; /* read index */	\
		unsigned int fi:5; /* free index */	\
		type buf[RINGBUF32_SIZE];		\
	} name

#ifdef DEBUG
	#define RING32_FETCH(str, rb) \
		(rb)->buf[(rb)->ri]; \
		do { \
			printk("RING32_FETCH: %s: ri: %d, val: 0x%x\n", (str), (rb)->ri, (rb)->buf[(rb)->ri]); \
			(rb)->ri++; \
		} while (0)

	#define RING32_STORE(str, rb, item) do {						\
			printk("RING32_STORE: %s: fi: %d, val: 0x%x\n", (str), (rb)->fi, item);	\
			(rb)->buf[(rb)->fi++] = (item);					\
		} while(0)
#else
	#define	RING32_FETCH(rb)	(rb)->buf[(rb)->ri++]

	#define RING32_STORE(rb, item) do {			\
			(rb)->buf[(rb)->fi++] = (item);		\
		} while(0)
#endif

#define	RING32_DATA_READY(rb)	((rb)->ri != (rb)->fi)

#define	RING32_PEEK_FI(rb)		(&(rb)->buf[(rb)->fi])
#define	RING32_PEEK_RI(rb)		(&(rb)->buf[(rb)->ri])

#define	RING32_RI_ADD(rb)		((rb)->ri++)
#define	RING32_RI_SUB(rb)		((rb)->ri--)
#define	RING32_FI_ADD(rb)		((rb)->fi++)
#define	RING32_FI_SUB(rb)		((rb)->fi--)

#endif /* ifndef HAVE_TYPES_H */
