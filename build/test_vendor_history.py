#!/usr/bin/env python3
"""Exercise the actual BPF history compatibility code with ASan/UBSan.

This is a host-side allocation/lifetime test, not a replacement for running
the BPF verifier selftests on the target kernel.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "kernel/bpf/verifier.c").read_text()
header = (root / "include/linux/bpf_verifier.h").read_text()

def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

types = "\n".join(re.search(r"struct " + name + r" \{.*?\n\};", header, re.S)[0]
                  for name in ("bpf_idx_pair", "bpf_jmp_history_entry"))
helpers = between(source, "struct bpf_jmp_history_storage {", "static void free_verifier_state(")
push = between(source, "static int push_jmp_history(", "static struct bpf_jmp_history_entry *get_jmp_hist_entry(")
copy = between(source[source.index("static int copy_verifier_state("):],
               "\tclear_jmp_history(dst_state);", "\n\t/* if dst has more stack frames")

prefix = r"""
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
typedef uint32_t u32;
typedef uint64_t u64;
#define GFP_USER 0
#define WARN_ONCE(test, ...) assert(!(test))
#define container_of(p, type, member) ((type *)((char *)(p) - offsetof(type, member)))
#define array_size(n, s) ((n) * (s))
#define size_mul(n, s) ((n) * (s))
#define struct_size(p, member, n) (sizeof(*(p)) + sizeof((p)->member[0]) * (n))
#define kmalloc_size_roundup(n) (n)
static int fail_after = -1;
static int fail_alloc(void) { return fail_after >= 0 && fail_after-- == 0; }
static void *kmalloc(size_t n, int g) { return fail_alloc() ? NULL : malloc(n); }
static void *krealloc(void *p, size_t n, int g) { return fail_alloc() ? NULL : realloc(p, n); }
static void *kmemdup(const void *p, size_t n, int g) {
    void *r = kmalloc(n, g);
    if (r) memcpy(r, p, n);
    return r;
}
#define kfree free
"""
state = r"""
struct bpf_verifier_state {
    struct bpf_idx_pair *jmp_history;
    u32 jmp_history_cnt;
};
struct bpf_verifier_env {
    struct bpf_jmp_history_entry *cur_hist_ent;
    int insn_idx, prev_insn_idx;
};
"""
tests = r"""
static void verify(const struct bpf_verifier_state *s) {
    for (u32 i = 0; i < s->jmp_history_cnt; ++i) {
        assert(s->jmp_history[i].idx == bpf_jmp_history(s)[i].idx);
        assert(s->jmp_history[i].prev_idx == bpf_jmp_history(s)[i].prev_idx);
    }
}
int main(void) {
    struct bpf_verifier_state a = {}, b = {};
    struct bpf_verifier_env env = {};
    for (int i = 0; i < 128; ++i) {
        env.cur_hist_ent = NULL;
        env.insn_idx = i + 1;
        env.prev_insn_idx = i;
        assert(push_jmp_history(&env, &a, 1, 0) == 0);
        assert(push_jmp_history(&env, &a, 2, 0xabc) == 0);
        assert(a.jmp_history_cnt == i + 1);
        assert(bpf_jmp_history(&a)[i].flags == 3);
        assert(bpf_jmp_history(&a)[i].linked_regs == 0xabc);
        verify(&a);
    }
    assert(copy_history(&b, &a) == 0);
    verify(&b);
    assert(bpf_jmp_history(&a) != bpf_jmp_history(&b));
    for (int fail = 0; fail < 2; ++fail) {
        env.cur_hist_ent = NULL;
        fail_after = fail;
        assert(push_jmp_history(&env, &a, 0, 0) == -ENOMEM);
        assert(a.jmp_history_cnt == 128);
        verify(&a);
        fail_after = fail;
        assert(copy_history(&b, &a) == -ENOMEM);
        clear_jmp_history(&b);
        fail_after = -1;
        assert(copy_history(&b, &a) == 0);
        verify(&b);
    }
    clear_jmp_history(&a);
    assert(copy_history(&b, &a) == 0);
    assert(!b.jmp_history && !b.jmp_history_cnt);
    clear_jmp_history(&b);
    for (int fail = 0; fail < 2; ++fail) {
        env.cur_hist_ent = NULL;
        fail_after = fail;
        assert(push_jmp_history(&env, &a, 0, 0) == -ENOMEM);
        assert(a.jmp_history_cnt == 0);
        clear_jmp_history(&a);
    }
    puts("BPF legacy history: growth, coalescing, copy, OOM and cleanup passed");
}
"""
program = (prefix + types + state + helpers + push +
           "static int copy_history(struct bpf_verifier_state *dst_state, "
           "const struct bpf_verifier_state *src) {\n" + copy + "\nreturn 0;\n}\n" + tests)
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / "test.c").write_text(program)
    subprocess.run([os.environ.get("CC", "cc"), "-g", "-O1",
                    "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                    str(path / "test.c"), "-o", str(path / "test")], check=True)
    subprocess.run([str(path / "test")], check=True,
                   env={**os.environ, "ASAN_OPTIONS": "detect_leaks=1"})
