/*
 * splicehelper — ARM32 port for Galaxy Watch 4 (crash_dump32 bridge)
 *
 * argv[0] = program name
 * argv[1] = file offset (decimal string)
 * argv[2] = file path (vendor .so)
 * argv[3] = optional "r" — read mode: read 16 bytes → fd 0 (OUT_FD)
 *           if absent — splice mode: splice 16 bytes → fd 1 (PIPE_FD)
 *
 * Runs in crash_dump SELinux domain (can read vendor_file).
 * No libc — raw syscalls only.
 */

#define OUT_FD  0
#define PIPE_FD 1

/* ARM32 (EABI) syscall: r7=nr, r0-r5=args */
__attribute__((naked)) static long mysyscall1(unsigned long a0, unsigned long nr) {
    asm volatile("mov r7, r1\nsvc 0\nbx lr\n":::"r7");
}

__attribute__((naked)) static long mysyscall3(
    unsigned long a0, unsigned long a1, unsigned long a2, unsigned long nr) {
    asm volatile("mov r7, r3\nsvc 0\nbx lr\n":::"r7");
}

__attribute__((naked)) static long mysyscall6(
    unsigned long a0, unsigned long a1, unsigned long a2,
    unsigned long a3, unsigned long a4, unsigned long a5, unsigned long nr) {
    /* ARM32 EABI: r0-r3 from regs, r4-r6 from stack.
     * C ABI puts a3..a6,nr at [sp+0],[sp+4],[sp+8],[sp+12].
     * We need: r4=a4(sp+4), r5=a5(sp+8), r7=nr(sp+12). */
    asm volatile(
        "push {r4, r5, r7}\n"
        "ldr r4, [sp, #12]\n"   /* a4: 3 pushes × 4 = 12, so old [sp+0] */
        "ldr r5, [sp, #16]\n"   /* a5: old [sp+4] */
        "ldr r7, [sp, #20]\n"   /* nr: old [sp+8] */
        "svc 0\n"
        "pop {r4, r5, r7}\n"
        "bx lr\n"
        :::"memory");
}

static unsigned long parse_int(char *s) {
    unsigned long val = 0;
    while (*s) { val = val * 10 + (unsigned long)(*s - '0'); s++; }
    return val;
}

static int streq(const char *a, const char *b) {
    while (*a && *b && *a == *b) { a++; b++; }
    return *a == *b;
}

/* ARM32 syscall numbers */
#define NR_exit_group 248
#define NR_openat     322
#define NR_read         3
#define NR_write        4
#define NR_lseek       19
#define NR_splice     340

#define AT_FDCWD     (-100)
#define O_RDONLY       0
#define SEEK_SET       0
#define SEEK_CUR       1
#define SPLICE_F_MOVE  1

void start_c(void *argblock) {
    int argc = *(int *)argblock;
    char **argv = (char **)((int *)argblock + 1);

    if (argc < 3)
        mysyscall1(10, NR_exit_group);
    if (argc > 4)
        mysyscall1(11, NR_exit_group);

    unsigned long off = parse_int(argv[1]);
    char *target = argv[2];
    char *mode = (argc >= 4) ? argv[3] : (char *)0;

    int file_fd = (int)mysyscall3(
        (unsigned long)AT_FDCWD,
        (unsigned long)target,
        (unsigned long)O_RDONLY,
        NR_openat);
    if (file_fd < 0)
        mysyscall1(20, NR_exit_group);

    if (mode && streq(mode, "r")) {
        mysyscall3((unsigned long)file_fd, off, SEEK_SET, NR_lseek);
        unsigned char buf[16];
        long n = mysyscall3((unsigned long)file_fd, (unsigned long)buf, 16, NR_read);
        if (n != 16)
            mysyscall1(21, NR_exit_group);
        /* Verify OUT_FD is a pipe (lseek returns -ESPIPE = -29) */
        if (mysyscall3(OUT_FD, 0, SEEK_CUR, NR_lseek) != (long)-29L)
            mysyscall1(3, NR_exit_group);
        long w = mysyscall3(OUT_FD, (unsigned long)buf, 16, NR_write);
        mysyscall1((unsigned long)(w == 16 ? 0 : 2), NR_exit_group);
    }

    /* Splice mode */
    long ret = mysyscall6(
        (unsigned long)file_fd,
        (unsigned long)&off,
        PIPE_FD,
        (unsigned long)0,
        16,
        SPLICE_F_MOVE,
        NR_splice);
    mysyscall1((unsigned long)(ret == 16 ? 0 : 30), NR_exit_group);
}

__attribute__((naked)) void _start() {
    /* ARM32: sp points to argc on entry */
    asm(".extern start_c\nmov r0, sp\nb start_c\n");
}
