.syntax unified
.thumb
.arch armv7-a

/* v6: przeplyw ladowania modulu zgodny z DFRoot (libcxx.S).
 * - mutex /dev/df: tylko openat(O_CREAT|O_EXCL), BEZ wczesniejszego unlink
 *   (unlink przed O_EXCL zjadal mutex, drugi run wchodzil ponownie)
 * - worker klonuje wnuka; wnuk zapisuje "u:r:vendor_modprobe:s0" do
 *   /proc/self/attr/exec i wykonuje execve("/vendor/bin/insmod", ...).
 *   Kontekst zaczyna dzialac dopiero przy execve, a init_module z domeny
 *   init nie ma module_load (plat_sepolicy.cil: init tylko na rootfs).
 * - worker czeka na wnuka i zapisuje status jako markery /dev/dxs oraz
 *   /dev/dxb0..3 (diagnostyka, bity kodu wyjscia insmod).
 * - dd magisk-boot.img robi bootstrap uruchamiany przez UMH z modulu.
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
    mov     r7, #5          /* open */
    svc     #0
    cmp     r0, #0
    blt     .Lrestore
    mov     r7, #6          /* close */
    svc     #0

    /* fork: rodzic wraca do init, dziecko = worker */
    mov     r7, #2
    svc     #0
    cmp     r0, #0
    bne     .Lrestore

    /* ===== Worker ===== */
    adr     r0, .Ldxw
    bl      .Ltouch

    /* fork wnuka */
    mov     r7, #2
    svc     #0
    cmp     r0, #0
    beq     .Lgrandchild
    mov     r4, r0          /* pid wnuka */

    /* wait4(pid, &status, 0, NULL) */
    sub     sp, sp, #4
    mov     r0, r4
    mov     r1, sp
    mov     r2, #0
    mov     r3, #0
    mov     r7, #114
    svc     #0
    ldr     r4, [sp]
    add     sp, sp, #4

    /* diagnostyka: kod wyjscia wnuka -> /dev/dxs i /dev/dxb0..3 */
    adr     r0, .Ldxs
    bl      .Ltouch
    lsr     r6, r4, #8
    and     r6, r6, #0xff
    tst     r6, #1
    beq     1f
    adr     r0, .Ldxb0
    bl      .Ltouch
1:  tst     r6, #2
    beq     2f
    adr     r0, .Ldxb1
    bl      .Ltouch
2:  tst     r6, #4
    beq     3f
    adr     r0, .Ldxb2
    bl      .Ltouch
3:  tst     r6, #8
    beq     4f
    adr     r0, .Ldxb3
    bl      .Ltouch
4:
    mov     r0, #0
    mov     r7, #1          /* exit */
    svc     #0

    /* ===== Wnuk: przejscie domeny + insmod ===== */
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
    /* argv = [insmod, KO, NULL] — na stosie w tej kolejnosci */
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

/* Tryb Thumb ustawia dyrektywa .thumb na poczatku pliku; bez drugiego
 * .thumb_func, bo ten psuje uklad sekcji przy -Ttext=0 (lld). */
.Ltouch:
    push    {lr}
    movw    r1, #0xC1
    movw    r2, #0x1A4
    mov     r7, #5
    svc     #0
    cmp     r0, #0
    blt     1f
    mov     r7, #6
    svc     #0
1:  pop     {pc}

.Lrestore:
    pop     {r0-r7, lr}
    b       .Lreturn

.align 2
.Ldev_df:        .asciz "/dev/df"
.align 2
.Ldxw:           .asciz "/dev/dxw"
.align 2
.Ldxs:           .asciz "/dev/dxs"
.align 2
.Ldxb0:          .asciz "/dev/dxb0"
.align 2
.Ldxb1:          .asciz "/dev/dxb1"
.align 2
.Ldxb2:          .asciz "/dev/dxb2"
.align 2
.Ldxb3:          .asciz "/dev/dxb3"
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
