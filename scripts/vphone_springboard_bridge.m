#include <dlfcn.h>
#include <errno.h>
#include <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <notify.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#define CY_VPHONE_SB_MAGIC 0x43595342u /* CYSB */
#define CY_VPHONE_SB_VERSION 1u
#define CY_VPHONE_SB_SOCKET "/private/var/mobile/Library/Caches/com.zeroxjf.cyanide.vphone-springboard.sock"
#define CY_VPHONE_SB_LOG "/private/var/mobile/Library/Caches/com.zeroxjf.cyanide.vphone-springboard.log"

enum {
    CY_VPHONE_SB_CMD_PING = 1,
    CY_VPHONE_SB_CMD_CALL_NAME = 2,
    CY_VPHONE_SB_CMD_CALL_ADDR = 3,
    CY_VPHONE_SB_CMD_READ = 4,
    CY_VPHONE_SB_CMD_WRITE = 5,
};

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t cmd;
    uint64_t addr;
    uint64_t len;
    uint64_t args[8];
    char name[128];
} cy_vphone_sb_req_t;

typedef struct __attribute__((packed)) {
    uint32_t magic;
    int32_t status;
    uint64_t value;
    uint64_t len;
} cy_vphone_sb_resp_t;

typedef uint64_t (*cy_vphone_fn8_t)(uint64_t,
                                    uint64_t,
                                    uint64_t,
                                    uint64_t,
                                    uint64_t,
                                    uint64_t,
                                    uint64_t,
                                    uint64_t);

static void *cy_resolve_symbol(const char *name)
{
    if (!name || !name[0]) return NULL;

    void *fn = dlsym(RTLD_DEFAULT, name);
    if (fn) return fn;

    static const char *const libraries[] = {
        "/usr/lib/libSystem.B.dylib",
        "/usr/lib/system/libsystem_malloc.dylib",
        "/usr/lib/system/libsystem_kernel.dylib",
        "/usr/lib/libobjc.A.dylib",
        "/System/Library/Frameworks/IOKit.framework/IOKit",
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
        "/System/Library/Frameworks/Foundation.framework/Foundation",
        "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore",
        NULL,
    };

    for (size_t i = 0; libraries[i]; i++) {
        void *handle = dlopen(libraries[i], RTLD_LAZY | RTLD_GLOBAL);
        if (!handle) continue;
        fn = dlsym(handle, name);
        if (fn) return fn;
    }

    return NULL;
}

static void cy_log(const char *fmt, ...)
{
    int fd = open(CY_VPHONE_SB_LOG, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;

    dprintf(fd, "[cyanide-sb-bridge pid=%d] ", getpid());
    va_list ap;
    va_start(ap, fmt);
    vdprintf(fd, fmt, ap);
    va_end(ap);
    dprintf(fd, "\n");
    close(fd);
}

static bool cy_read_full(int fd, void *buf, size_t len)
{
    uint8_t *p = (uint8_t *)buf;
    while (len > 0) {
        ssize_t n = read(fd, p, len);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        p += (size_t)n;
        len -= (size_t)n;
    }
    return true;
}

static bool cy_write_full(int fd, const void *buf, size_t len)
{
    const uint8_t *p = (const uint8_t *)buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        p += (size_t)n;
        len -= (size_t)n;
    }
    return true;
}

static void cy_send_status(int fd, int32_t status, uint64_t value, uint64_t len)
{
    cy_vphone_sb_resp_t resp = {
        .magic = CY_VPHONE_SB_MAGIC,
        .status = status,
        .value = value,
        .len = len,
    };
    (void)cy_write_full(fd, &resp, sizeof(resp));
}

static uint64_t cy_call8(void *fn, uint64_t args[8])
{
    cy_vphone_fn8_t f = (cy_vphone_fn8_t)fn;
    return f(args[0], args[1], args[2], args[3],
             args[4], args[5], args[6], args[7]);
}

static bool cy_is_unsafe_addr_call_name(const char *name)
{
    if (!name || !name[0]) return false;
    return strcmp(name, "IOServiceMatching") == 0 ||
           strcmp(name, "IOServiceGetMatchingService") == 0 ||
           strcmp(name, "IORegistryEntryCreateCFProperty") == 0 ||
           strcmp(name, "IOObjectRelease") == 0;
}

static bool cy_launch_application_with_bundle_id(uint64_t bundleID, uint64_t *retOut)
{
    if (!bundleID || !retOut) return false;

    id (*msgSend_id)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id (*msgSend_id_id)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
    BOOL (*msgSend_bool_id)(id, SEL, id) = (BOOL (*)(id, SEL, id))objc_msgSend;

    // Preferred: SBMainWorkspace activateApplication: creates a proper
    // FBScene that SBSceneManagerCoordinator can resolve immediately.
    Class sbAppCtrlCls = objc_getClass("SBApplicationController");
    if (sbAppCtrlCls) {
        SEL sharedSel = sel_registerName("sharedInstance");
        SEL appForBidSel = sel_registerName("applicationWithBundleIdentifier:");
        if (class_respondsToSelector(sbAppCtrlCls, sharedSel)) {
            id ctrl = msgSend_id((id)sbAppCtrlCls, sharedSel);
            if (ctrl && [ctrl respondsToSelector:appForBidSel]) {
                id app = msgSend_id_id(ctrl, appForBidSel, (id)(uintptr_t)bundleID);
                if (app) {
                    Class wsCls = objc_getClass("SBMainWorkspace");
                    if (wsCls) {
                        SEL sharedWsSel = sel_registerName("sharedInstance");
                        if (class_respondsToSelector(wsCls, sharedWsSel)) {
                            id ws = msgSend_id((id)wsCls, sharedWsSel);
                            SEL activateSel = sel_registerName("activateApplication:");
                            if (ws && [ws respondsToSelector:activateSel]) {
                                msgSend_id_id(ws, activateSel, app);
                                *retOut = 1;
                                return true;
                            }
                        }
                    }
                }
            }
        }
    }

    // Fallback: LSApplicationWorkspace (less reliable for scene creation).
    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    if (!workspaceClass) {
        (void)dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
                     RTLD_LAZY | RTLD_GLOBAL);
        (void)dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",
                     RTLD_LAZY | RTLD_GLOBAL);
        workspaceClass = objc_getClass("LSApplicationWorkspace");
    }

    SEL defaultWorkspaceSel = sel_registerName("defaultWorkspace");
    SEL openBundleSel = sel_registerName("openApplicationWithBundleID:");
    if (!workspaceClass || !class_respondsToSelector(workspaceClass, defaultWorkspaceSel)) {
        *retOut = 0;
        return true;
    }

    id workspace = msgSend_id((id)workspaceClass, defaultWorkspaceSel);
    if (!workspace || ![workspace respondsToSelector:openBundleSel]) {
        *retOut = 0;
        return true;
    }

    *retOut = msgSend_bool_id(workspace, openBundleSel, (id)(uintptr_t)bundleID) ? 1 : 0;
    return true;
}

typedef char *(*cy_sandbox_extension_issue_file_fn)(const char *, const char *, uint32_t);
typedef char *(*cy_sandbox_extension_issue_mach_fn)(const char *, const char *, uint32_t);

static bool cy_call_builtin(const char *name, uint64_t args[8], uint64_t *retOut)
{
    if (!name || !retOut) return false;

    if (strcmp(name, "getpid") == 0) {
        *retOut = (uint64_t)getpid();
        return true;
    }
    if (strcmp(name, "pthread_exit") == 0) {
        /* Bridge mode has no synthetic trojan thread to tear down. */
        *retOut = 0;
        return true;
    }
    if (strcmp(name, "malloc") == 0) {
        *retOut = (uint64_t)(uintptr_t)malloc((size_t)args[0]);
        return true;
    }
    if (strcmp(name, "calloc") == 0) {
        *retOut = (uint64_t)(uintptr_t)calloc((size_t)args[0], (size_t)args[1]);
        return true;
    }
    if (strcmp(name, "free") == 0) {
        free((void *)(uintptr_t)args[0]);
        *retOut = 0;
        return true;
    }
    if (strcmp(name, "realloc") == 0) {
        *retOut = (uint64_t)(uintptr_t)realloc((void *)(uintptr_t)args[0],
                                               (size_t)args[1]);
        return true;
    }
    if (strcmp(name, "mmap") == 0) {
        void *p = mmap((void *)(uintptr_t)args[0],
                       (size_t)args[1],
                       (int)args[2],
                       (int)args[3],
                       (int)args[4],
                       (off_t)args[5]);
        *retOut = (uint64_t)(uintptr_t)p;
        return true;
    }
    if (strcmp(name, "munmap") == 0) {
        *retOut = (uint64_t)munmap((void *)(uintptr_t)args[0],
                                   (size_t)args[1]);
        return true;
    }
    if (strcmp(name, "memset") == 0) {
        *retOut = (uint64_t)(uintptr_t)memset((void *)(uintptr_t)args[0],
                                              (int)args[1],
                                              (size_t)args[2]);
        return true;
    }
    if (strcmp(name, "memcpy") == 0) {
        *retOut = (uint64_t)(uintptr_t)memcpy((void *)(uintptr_t)args[0],
                                              (const void *)(uintptr_t)args[1],
                                              (size_t)args[2]);
        return true;
    }
    if (strcmp(name, "strdup") == 0) {
        *retOut = (uint64_t)(uintptr_t)strdup((const char *)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "open") == 0) {
        *retOut = (uint64_t)(int64_t)open((const char *)(uintptr_t)args[0],
                                          (int)args[1],
                                          (mode_t)args[2]);
        return true;
    }
    if (strcmp(name, "read") == 0) {
        *retOut = (uint64_t)(int64_t)read((int)args[0],
                                          (void *)(uintptr_t)args[1],
                                          (size_t)args[2]);
        return true;
    }
    if (strcmp(name, "write") == 0) {
        *retOut = (uint64_t)(int64_t)write((int)args[0],
                                           (const void *)(uintptr_t)args[1],
                                           (size_t)args[2]);
        return true;
    }
    if (strcmp(name, "close") == 0) {
        *retOut = (uint64_t)(int64_t)close((int)args[0]);
        return true;
    }
    if (strcmp(name, "dlopen") == 0) {
        *retOut = (uint64_t)(uintptr_t)dlopen((const char *)(uintptr_t)args[0],
                                              (int)args[1]);
        return true;
    }
    if (strcmp(name, "dlsym") == 0) {
        void *handle = (void *)(uintptr_t)args[0];
        if (args[0] == (uint64_t)-2) handle = RTLD_DEFAULT;
        *retOut = (uint64_t)(uintptr_t)cy_resolve_symbol((const char *)(uintptr_t)args[1]);
        if (!*retOut) {
            *retOut = (uint64_t)(uintptr_t)dlsym(handle,
                                                 (const char *)(uintptr_t)args[1]);
        }
        return true;
    }
    if (strcmp(name, "notify_post") == 0) {
        *retOut = (uint64_t)notify_post((const char *)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "CFStringCreateWithCString") == 0) {
        *retOut = (uint64_t)(uintptr_t)CFStringCreateWithCString((CFAllocatorRef)(uintptr_t)args[0],
                                                                 (const char *)(uintptr_t)args[1],
                                                                 (CFStringEncoding)args[2]);
        return true;
    }
    if (strcmp(name, "CFNumberGetValue") == 0) {
        *retOut = (uint64_t)CFNumberGetValue((CFNumberRef)(uintptr_t)args[0],
                                             (CFNumberType)args[1],
                                             (void *)(uintptr_t)args[2]);
        return true;
    }
    if (strcmp(name, "CFRelease") == 0) {
        if (args[0]) CFRelease((CFTypeRef)(uintptr_t)args[0]);
        *retOut = 0;
        return true;
    }
    if (strcmp(name, "NSStringFromClass") == 0) {
        *retOut = (uint64_t)(uintptr_t)NSStringFromClass((Class)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "sel_registerName") == 0) {
        *retOut = (uint64_t)(uintptr_t)sel_registerName((const char *)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "objc_getClass") == 0) {
        *retOut = (uint64_t)(uintptr_t)objc_getClass((const char *)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "objc_lookUpClass") == 0) {
        *retOut = (uint64_t)(uintptr_t)objc_lookUpClass((const char *)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "object_getClass") == 0) {
        *retOut = (uint64_t)(uintptr_t)object_getClass((id)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "object_setClass") == 0) {
        *retOut = (uint64_t)(uintptr_t)object_setClass((id)(uintptr_t)args[0],
                                                       (Class)(uintptr_t)args[1]);
        return true;
    }
    if (strcmp(name, "class_getName") == 0) {
        *retOut = (uint64_t)(uintptr_t)class_getName((Class)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "class_getSuperclass") == 0) {
        *retOut = (uint64_t)(uintptr_t)class_getSuperclass((Class)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "class_getInstanceMethod") == 0) {
        *retOut = (uint64_t)(uintptr_t)class_getInstanceMethod((Class)(uintptr_t)args[0],
                                                               (SEL)(uintptr_t)args[1]);
        return true;
    }
    if (strcmp(name, "class_getMethodImplementation") == 0) {
        *retOut = (uint64_t)(uintptr_t)class_getMethodImplementation((Class)(uintptr_t)args[0],
                                                                     (SEL)(uintptr_t)args[1]);
        return true;
    }
    if (strcmp(name, "method_getImplementation") == 0) {
        *retOut = (uint64_t)(uintptr_t)method_getImplementation((Method)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "method_setImplementation") == 0) {
        *retOut = (uint64_t)(uintptr_t)method_setImplementation((Method)(uintptr_t)args[0],
                                                               (IMP)(uintptr_t)args[1]);
        return true;
    }
    if (strcmp(name, "class_addMethod") == 0) {
        *retOut = (uint64_t)class_addMethod((Class)(uintptr_t)args[0],
                                            (SEL)(uintptr_t)args[1],
                                            (IMP)(uintptr_t)args[2],
                                            (const char *)(uintptr_t)args[3]);
        return true;
    }
    if (strcmp(name, "class_getInstanceVariable") == 0) {
        *retOut = (uint64_t)(uintptr_t)class_getInstanceVariable((Class)(uintptr_t)args[0],
                                                                (const char *)(uintptr_t)args[1]);
        return true;
    }
    if (strcmp(name, "ivar_getOffset") == 0) {
        *retOut = (uint64_t)ivar_getOffset((Ivar)(uintptr_t)args[0]);
        return true;
    }
    if (strcmp(name, "objc_allocateClassPair") == 0) {
        *retOut = (uint64_t)(uintptr_t)objc_allocateClassPair((Class)(uintptr_t)args[0],
                                                             (const char *)(uintptr_t)args[1],
                                                             (size_t)args[2]);
        return true;
    }
    if (strcmp(name, "objc_registerClassPair") == 0) {
        objc_registerClassPair((Class)(uintptr_t)args[0]);
        *retOut = 0;
        return true;
    }
    if (strcmp(name, "objc_getAssociatedObject") == 0) {
        *retOut = (uint64_t)(uintptr_t)objc_getAssociatedObject((id)(uintptr_t)args[0],
                                                               (const void *)(uintptr_t)args[1]);
        return true;
    }
    if (strcmp(name, "objc_setAssociatedObject") == 0) {
        objc_setAssociatedObject((id)(uintptr_t)args[0],
                                 (const void *)(uintptr_t)args[1],
                                 (id)(uintptr_t)args[2],
                                 (objc_AssociationPolicy)args[3]);
        *retOut = 0;
        return true;
    }
    if (strcmp(name, "objc_msgSend") == 0) {
        *retOut = cy_call8((void *)objc_msgSend, args);
        return true;
    }
    if (strcmp(name, "SBSLaunchApplicationWithIdentifier") == 0) {
        return cy_launch_application_with_bundle_id(args[0], retOut);
    }
    if (strcmp(name, "sandbox_extension_issue_file") == 0) {
        cy_sandbox_extension_issue_file_fn fn =
            (cy_sandbox_extension_issue_file_fn)cy_resolve_symbol("sandbox_extension_issue_file");
        if (!fn) return false;
        *retOut = (uint64_t)(uintptr_t)fn((const char *)(uintptr_t)args[0],
                                         (const char *)(uintptr_t)args[1],
                                         (uint32_t)args[2]);
        return true;
    }
    if (strcmp(name, "sandbox_extension_issue_mach") == 0) {
        cy_sandbox_extension_issue_mach_fn fn =
            (cy_sandbox_extension_issue_mach_fn)cy_resolve_symbol("sandbox_extension_issue_mach");
        if (!fn) return false;
        *retOut = (uint64_t)(uintptr_t)fn((const char *)(uintptr_t)args[0],
                                         (const char *)(uintptr_t)args[1],
                                         (uint32_t)args[2]);
        return true;
    }

    return false;
}

static void cy_handle_client(int fd)
{
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));

    cy_vphone_sb_req_t req;
    while (cy_read_full(fd, &req, sizeof(req))) {
        if (req.magic != CY_VPHONE_SB_MAGIC) {
            cy_send_status(fd, EPROTO, 0, 0);
            return;
        }

        switch (req.cmd) {
            case CY_VPHONE_SB_CMD_PING:
                cy_send_status(fd, 0, CY_VPHONE_SB_VERSION, 0);
                break;

            case CY_VPHONE_SB_CMD_CALL_NAME: {
                if (req.name[sizeof(req.name) - 1] != '\0') {
                    req.name[sizeof(req.name) - 1] = '\0';
                }
                if (!req.name[0]) {
                    cy_send_status(fd, EINVAL, 0, 0);
                    break;
                }
                uint64_t ret = 0;
                if (cy_call_builtin(req.name, req.args, &ret)) {
                    cy_send_status(fd, 0, ret, 0);
                    break;
                }
                void *fn = cy_resolve_symbol(req.name);
                if (!fn) {
                    cy_log("symbol not found: %s", req.name);
                    cy_send_status(fd, ENOENT, 0, 0);
                    break;
                }
                ret = cy_call8(fn, req.args);
                cy_send_status(fd, 0, ret, 0);
                break;
            }

            case CY_VPHONE_SB_CMD_CALL_ADDR: {
                if (!req.addr) {
                    cy_send_status(fd, EINVAL, 0, 0);
                    break;
                }
                if (req.name[sizeof(req.name) - 1] != '\0') {
                    req.name[sizeof(req.name) - 1] = '\0';
                }
                if (cy_is_unsafe_addr_call_name(req.name)) {
                    cy_log("refusing unsafe addr-call: %s addr=0x%llx",
                           req.name, (unsigned long long)req.addr);
                    cy_send_status(fd, ENOTSUP, 0, 0);
                    break;
                }
                uint64_t ret = cy_call8((void *)(uintptr_t)req.addr, req.args);
                cy_send_status(fd, 0, ret, 0);
                break;
            }

            case CY_VPHONE_SB_CMD_READ: {
                if (req.len == 0 || req.len > 0x100000) {
                    cy_send_status(fd, EINVAL, 0, 0);
                    break;
                }
                void *buf = calloc(1, (size_t)req.len);
                if (!buf) {
                    cy_send_status(fd, ENOMEM, 0, 0);
                    break;
                }
                memcpy(buf, (const void *)(uintptr_t)req.addr, (size_t)req.len);
                cy_send_status(fd, 0, 0, req.len);
                (void)cy_write_full(fd, buf, (size_t)req.len);
                free(buf);
                break;
            }

            case CY_VPHONE_SB_CMD_WRITE: {
                if (req.len == 0 || req.len > 0x100000) {
                    cy_send_status(fd, EINVAL, 0, 0);
                    break;
                }
                void *buf = malloc((size_t)req.len);
                if (!buf) {
                    cy_send_status(fd, ENOMEM, 0, 0);
                    break;
                }
                if (!cy_read_full(fd, buf, (size_t)req.len)) {
                    free(buf);
                    return;
                }
                memcpy((void *)(uintptr_t)req.addr, buf, (size_t)req.len);
                free(buf);
                cy_send_status(fd, 0, 0, 0);
                break;
            }

            default:
                cy_send_status(fd, ENOTSUP, 0, 0);
                break;
        }
    }
}

static void *cy_client_thread(void *arg)
{
    int client = (int)(intptr_t)arg;
    cy_handle_client(client);
    close(client);
    return NULL;
}

static void *cy_bridge_thread(void *unused)
{
    (void)unused;

    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) {
        cy_log("socket failed errno=%d", errno);
        return NULL;
    }

    int one = 1;
    setsockopt(server, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    unlink(CY_VPHONE_SB_SOCKET);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, CY_VPHONE_SB_SOCKET, sizeof(addr.sun_path));

    if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        cy_log("bind failed errno=%d", errno);
        close(server);
        return NULL;
    }

    chmod(CY_VPHONE_SB_SOCKET, 0666);
    if (listen(server, 8) != 0) {
        cy_log("listen failed errno=%d", errno);
        close(server);
        unlink(CY_VPHONE_SB_SOCKET);
        return NULL;
    }

    cy_log("listening at %s", CY_VPHONE_SB_SOCKET);
    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }

        pthread_t clientThread = NULL;
        int err = pthread_create(&clientThread, NULL, cy_client_thread, (void *)(intptr_t)client);
        if (err == 0) {
            pthread_detach(clientThread);
        } else {
            cy_log("client pthread_create failed err=%d; handling inline", err);
            cy_handle_client(client);
            close(client);
        }
    }

    close(server);
    unlink(CY_VPHONE_SB_SOCKET);
    return NULL;
}

__attribute__((constructor))
static void cy_bridge_init(void)
{
    const char *prog = getprogname();
    if (!prog || strcmp(prog, "SpringBoard") != 0) {
        return;
    }

    signal(SIGPIPE, SIG_IGN);

    pthread_t thread = NULL;
    int err = pthread_create(&thread, NULL, cy_bridge_thread, NULL);
    if (err != 0) {
        cy_log("pthread_create failed err=%d", err);
        return;
    }
    pthread_detach(thread);
}
