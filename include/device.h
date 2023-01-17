#ifndef HAVE_DEVICE_H
#define	HAVE_DEVICE_H

/* I'm missing a bigger picture here. Maybe I should actually draw
   this down on paper and try to come up with some sort of design.

   Problem is I don't know what all I need to design. General idea
   is these devices are connected to some sort of bus, should be
   identified somehow, etc..

   Let's start simple and see where we get..
*/

#define	DEVNAME_SIZE	32
#define	MAXLEN_DEVNAME	(DEVNAME_SIZE-1)

/* abstract form of device structure */
typedef struct device {
	char devname[DEVNAME_SIZE];
	void* dev;
} device_t;



#endif /* ifndef HAVE_DEVICE_H */
