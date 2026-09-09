/*
 * Copyright (c) Sakion Team. All rights reserved.
 *
 * File name: rekernel_binder_alloc.c
 * Description: Legacy binder buffer copy for Linux < 6.0 (5.10 / 5.15).
 *              Ported from android14-6.1 drivers/android/binder_alloc.c
 *              (get_page / buffer_size / check_buffer / do_buffer_copy).
 *              Newer kernels use in-kernel binder_alloc_copy_from_buffer.
 */

#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/mm.h>
#include <linux/highmem.h>
#include <linux/list.h>
#include <linux/err.h>
#include <linux/version.h>
#include "rekernel_binder_alloc.h"

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 0, 0)

static inline void rekernel_memcpy_from_page(char *to, struct page *page,
	size_t offset, size_t len)
{
	char *from;

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)
	from = kmap_local_page(page);
	memcpy(to, from + offset, len);
	kunmap_local(from);
#else
	from = kmap_atomic(page);
	memcpy(to, from + offset, len);
	kunmap_atomic(from);
#endif
}

static struct binder_buffer *rekernel_binder_buffer_next(struct binder_buffer *buffer)
{
	return list_entry(buffer->entry.next, struct binder_buffer, entry);
}

static size_t rekernel_binder_alloc_buffer_size(struct binder_alloc *alloc,
	struct binder_buffer *buffer)
{
	if (list_is_last(&buffer->entry, &alloc->buffers))
		return (size_t)((uintptr_t)alloc->buffer + alloc->buffer_size -
			(uintptr_t)buffer->user_data);
	return (size_t)((uintptr_t)rekernel_binder_buffer_next(buffer)->user_data -
		(uintptr_t)buffer->user_data);
}

static inline bool rekernel_check_buffer(struct binder_alloc *alloc,
	struct binder_buffer *buffer, binder_size_t offset, size_t bytes)
{
	size_t buffer_size = rekernel_binder_alloc_buffer_size(alloc, buffer);

	return buffer_size >= bytes &&
		offset <= buffer_size - bytes &&
		IS_ALIGNED(offset, sizeof(u32)) &&
		!buffer->free &&
		(!buffer->allow_user_free || !buffer->transaction);
}

static struct page *rekernel_binder_alloc_get_page(struct binder_alloc *alloc,
	struct binder_buffer *buffer, binder_size_t buffer_offset, pgoff_t *pgoffp)
{
	binder_size_t buffer_space_offset = buffer_offset +
		((uintptr_t)buffer->user_data - (uintptr_t)alloc->buffer);
	pgoff_t pgoff = buffer_space_offset & ~PAGE_MASK;
	size_t index = buffer_space_offset >> PAGE_SHIFT;
	struct binder_lru_page *lru_page;

	lru_page = &alloc->pages[index];
	*pgoffp = pgoff;
	return lru_page->page_ptr;
}

static int rekernel_binder_alloc_do_buffer_copy(struct binder_alloc *alloc,
	bool to_buffer, struct binder_buffer *buffer,
	binder_size_t buffer_offset, void *ptr, size_t bytes)
{
	if (!rekernel_check_buffer(alloc, buffer, buffer_offset, bytes))
		return -EINVAL;

	while (bytes) {
		unsigned long size;
		struct page *page;
		pgoff_t pgoff;

		page = rekernel_binder_alloc_get_page(alloc, buffer, buffer_offset, &pgoff);
		size = min_t(size_t, bytes, PAGE_SIZE - pgoff);
		if (to_buffer)
			return -EINVAL;
		else
			rekernel_memcpy_from_page(ptr, page, pgoff, size);
		bytes -= size;
		ptr = (u8 *)ptr + size;
		buffer_offset += size;
	}
	return 0;
}

int rekernel_binder_copy_from_buffer(struct binder_alloc *alloc, void *dest,
	struct binder_buffer *buffer, binder_size_t buffer_offset, size_t bytes)
{
	return rekernel_binder_alloc_do_buffer_copy(alloc, false, buffer,
		buffer_offset, dest, bytes);
}

#else

static int rekernel_binder_alloc_legacy_unused __maybe_unused;

#endif
