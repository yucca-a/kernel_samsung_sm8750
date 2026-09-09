#ifndef REKERNEL_BINDER_ALLOC_H
#define REKERNEL_BINDER_ALLOC_H

#include <linux/types.h>
#include <linux/version.h>
#include <../android/binder_internal.h>

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 0, 0)
int rekernel_binder_copy_from_buffer(struct binder_alloc *alloc, void *dest,
	struct binder_buffer *buffer, binder_size_t buffer_offset, size_t bytes);
#endif

#endif
