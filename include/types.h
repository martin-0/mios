#ifndef HAVE_TYPES_H
#define	HAVE_TYPES_H

#include <stdint.h>

#define	RINGBUF32_SIZE		32

#define	DEFINE_RING32(name, type)		\
	struct { 				\
		unsigned int ri:5;		\
		unsigned int ci:5;		\
		type buf[RINGBUF32_SIZE];	\
	} name


#ifdef DEBUG
#define RING32_FETCH(rb) \
	(rb)->buf[(rb)->ri]; \
	do { \
		printk("RING32_FETCH: ri: %d, val: 0x%x\n", (rb)->ri, (rb)->buf[(rb)->ri]); \
		(rb)->ri++; \
	} while (0)
#else
#define	RING32_FETCH(rb)	(rb)->buf[(rb)->ri++]
#endif

#define RING32_STORE(rb, item) do {			\
		(rb)->buf[(rb)->ci++] = (item);		\
	} while(0)

#define	RING32_DATA_READY(rb)	((rb)->ri != (rb)->ci) 

#define	RING32_GET_FREE(rb)		(&(rb)->buf[(rb)->ci])
#define	RIGG32_GET_UNREAD(rb)		(&(rb)->buf[(rb)->ri])

#define	RING32_RI_ADVANCE(rb)		((rb)->ri++)
#define	RING32_CI_ADVANCE(rb)		((rb)->ci++)

#endif /* ifndef HAVE_TYPES_H */
