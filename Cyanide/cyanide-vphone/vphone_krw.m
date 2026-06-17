#import "vphone_krw.h"
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach/host_special_ports.h>
#import <mach-o/loader.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <unistd.h>
#import <string.h>
#import <dlfcn.h>
#import <errno.h>
#import <pthread.h>
#import <spawn.h>
#import <Foundation/Foundation.h>
#import "../kexploit/offsets.h"
#import "../kexploit/kutils.h"
#import "../kexploit/kexploit_opa334.h"
#import "../kexploit/xpaci.h"
#import "../LogTextView.h"

bool g_vphone_mode = false;
static mach_port_t g_vphone_tfp0 = MACH_PORT_NULL;

typedef int (*vphone_libkrw_kbase_t)(uint64_t *addr);
typedef int (*vphone_libkrw_kread_t)(uint64_t from, void *to, size_t len);
typedef int (*vphone_libkrw_kwrite_t)(void *from, uint64_t to, size_t len);

static void *g_vphone_libkrw = NULL;
static vphone_libkrw_kbase_t g_vphone_libkrw_kbase = NULL;
static vphone_libkrw_kread_t g_vphone_libkrw_kread = NULL;
static vphone_libkrw_kwrite_t g_vphone_libkrw_kwrite = NULL;

#define CY_VPHONE_KRW_MAGIC 0x43594B57u /* CYKW */
#define CY_VPHONE_KRW_VERSION 1u
#define CY_VPHONE_KRW_SOCKET "/private/var/mobile/Library/Caches/com.zeroxjf.cyanide.vphone-krw.sock"

enum {
    CY_VPHONE_KRW_CMD_PING = 1,
    CY_VPHONE_KRW_CMD_KBASE = 2,
    CY_VPHONE_KRW_CMD_KREAD = 3,
    CY_VPHONE_KRW_CMD_KWRITE = 4,
    CY_VPHONE_KRW_CMD_SHUTDOWN = 5,
};

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t cmd;
    uint64_t addr;
    uint64_t len;
} cy_vphone_krw_req_t;

typedef struct __attribute__((packed)) {
    uint32_t magic;
    int32_t status;
    uint64_t value;
    uint64_t len;
} cy_vphone_krw_resp_t;

static int g_vphone_helper_fd = -1;
static bool g_vphone_helper_ready = false;
static pthread_mutex_t g_vphone_helper_lock = PTHREAD_MUTEX_INITIALIZER;

extern char **environ;

static bool vphone_read_full(int fd, void *buf, size_t len) {
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

static bool vphone_write_full(int fd, const void *buf, size_t len) {
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

static void vphone_helper_close_locked(void) {
    if (g_vphone_helper_fd >= 0) {
        close(g_vphone_helper_fd);
        g_vphone_helper_fd = -1;
    }
    g_vphone_helper_ready = false;
}

static NSString *vphone_helper_binary_path(void) {
    NSString *externalPath = @"/var/jb/usr/local/libexec/cyanide/vphone_krw_helper";
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:externalPath]) {
        return externalPath;
    }

    NSString *path = [NSBundle.mainBundle pathForResource:@"vphone_krw_helper" ofType:nil];
    if (path.length > 0) return path;
    return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"vphone_krw_helper"];
}

static bool vphone_helper_connect_locked(void) {
    if (g_vphone_helper_fd >= 0) return true;

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return false;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, CY_VPHONE_KRW_SOCKET, sizeof(addr.sun_path));

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        return false;
    }

    g_vphone_helper_fd = fd;
    return true;
}

static bool vphone_helper_spawn_locked(void) {
    NSString *path = vphone_helper_binary_path();
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        printf("[VPHONE] KRW helper missing or not executable at %s\n", path.UTF8String);
        return false;
    }

    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) == 0) {
        if ((st.st_mode & S_ISUID) == 0 || st.st_uid != 0) {
            printf("[VPHONE] KRW helper is not root setuid yet uid=%u mode=%#o path=%s\n",
                   (unsigned)st.st_uid,
                   st.st_mode & 07777,
                   path.UTF8String);
        }
    }

    unlink(CY_VPHONE_KRW_SOCKET);

    pid_t pid = 0;
    char *argv[] = { (char *)path.fileSystemRepresentation, NULL };
    int err = posix_spawn(&pid, path.fileSystemRepresentation, NULL, NULL, argv, environ);
    if (err != 0) {
        printf("[VPHONE] posix_spawn(%s) failed errno=%d\n", path.UTF8String, err);
        return false;
    }

    printf("[VPHONE] spawned KRW helper pid=%d\n", pid);
    return true;
}

static bool vphone_helper_ensure_locked(void) {
    if (vphone_helper_connect_locked()) return true;

    if (!vphone_helper_spawn_locked()) return false;
    for (int i = 0; i < 60; i++) {
        if (vphone_helper_connect_locked()) return true;
        usleep(50000);
    }
    return false;
}

static bool vphone_helper_request_locked(uint32_t cmd,
                                         uint64_t addr,
                                         const void *writeData,
                                         size_t writeLen,
                                         void *readData,
                                         size_t readLen,
                                         uint64_t *valueOut) {
    if (!vphone_helper_ensure_locked()) return false;

    cy_vphone_krw_req_t req = {
        .magic = CY_VPHONE_KRW_MAGIC,
        .cmd = cmd,
        .addr = addr,
        .len = (uint64_t)(writeData ? writeLen : readLen),
    };

    if (!vphone_write_full(g_vphone_helper_fd, &req, sizeof(req)) ||
        (writeData && writeLen > 0 &&
         !vphone_write_full(g_vphone_helper_fd, writeData, writeLen))) {
        vphone_helper_close_locked();
        return false;
    }

    cy_vphone_krw_resp_t resp;
    if (!vphone_read_full(g_vphone_helper_fd, &resp, sizeof(resp)) ||
        resp.magic != CY_VPHONE_KRW_MAGIC ||
        resp.status != 0) {
        vphone_helper_close_locked();
        return false;
    }

    if (valueOut) *valueOut = resp.value;

    if (readData && readLen > 0) {
        if (resp.len != readLen ||
            !vphone_read_full(g_vphone_helper_fd, readData, readLen)) {
            vphone_helper_close_locked();
            return false;
        }
    }

    return true;
}

static bool vphone_helper_ping(void) {
    uint64_t version = 0;
    pthread_mutex_lock(&g_vphone_helper_lock);
    bool ok = vphone_helper_request_locked(CY_VPHONE_KRW_CMD_PING, 0, NULL, 0, NULL, 0, &version);
    pthread_mutex_unlock(&g_vphone_helper_lock);
    if (!ok || version != CY_VPHONE_KRW_VERSION) return false;
    g_vphone_helper_ready = true;
    return true;
}

static bool vphone_helper_kbase(uint64_t *baseOut) {
    uint64_t base = 0;
    pthread_mutex_lock(&g_vphone_helper_lock);
    bool ok = vphone_helper_request_locked(CY_VPHONE_KRW_CMD_KBASE, 0, NULL, 0, NULL, 0, &base);
    pthread_mutex_unlock(&g_vphone_helper_lock);
    if (ok && baseOut) *baseOut = base;
    return ok && base != 0;
}

static bool vphone_helper_kread(uint64_t kaddr, void *buf, size_t len) {
    if (!g_vphone_helper_ready) return false;
    pthread_mutex_lock(&g_vphone_helper_lock);
    bool ok = vphone_helper_request_locked(CY_VPHONE_KRW_CMD_KREAD, kaddr, NULL, 0, buf, len, NULL);
    pthread_mutex_unlock(&g_vphone_helper_lock);
    return ok;
}

static bool vphone_helper_kwrite(uint64_t kaddr, const void *buf, size_t len) {
    if (!g_vphone_helper_ready) return false;
    pthread_mutex_lock(&g_vphone_helper_lock);
    bool ok = vphone_helper_request_locked(CY_VPHONE_KRW_CMD_KWRITE, kaddr, buf, len, NULL, 0, NULL);
    pthread_mutex_unlock(&g_vphone_helper_lock);
    return ok;
}

#pragma mark - Low-level mach_vm r/w

uint64_t vphone_kread64(uint64_t kaddr) {
    uint64_t val = 0;
    if (vphone_helper_kread(kaddr, &val, sizeof(val)))
        return val;

    if (g_vphone_libkrw_kread) {
        int ret = g_vphone_libkrw_kread(kaddr, &val, sizeof(val));
        return ret == 0 ? val : 0;
    }

    vm_size_t outsize = 0;
    kern_return_t kr = vm_read_overwrite(g_vphone_tfp0, kaddr, 8,
                                              (vm_address_t)&val, &outsize);
    return (kr == KERN_SUCCESS) ? val : 0;
}

uint32_t vphone_kread32(uint64_t kaddr) {
    uint64_t val = vphone_kread64(kaddr);
    return (uint32_t)(val & 0xFFFFFFFF);
}

void vphone_kwrite64(uint64_t kaddr, uint64_t val) {
    if (vphone_helper_kwrite(kaddr, &val, sizeof(val)))
        return;

    if (g_vphone_libkrw_kwrite) {
        g_vphone_libkrw_kwrite(&val, kaddr, sizeof(val));
        return;
    }

    vm_write(g_vphone_tfp0, kaddr, (vm_offset_t)&val, 8);
}

void vphone_kwrite32(uint64_t kaddr, uint32_t val) {
    uint64_t existing = vphone_kread64(kaddr);
    uint64_t combined = (existing & 0xFFFFFFFF00000000ULL) | (uint64_t)val;
    vphone_kwrite64(kaddr, combined);
}

void vphone_kread_buf(uint64_t kaddr, void *buf, size_t len) {
    if (vphone_helper_kread(kaddr, buf, len))
        return;

    if (g_vphone_libkrw_kread) {
        int ret = g_vphone_libkrw_kread(kaddr, buf, len);
        if (ret != 0)
            memset(buf, 0, len);
        return;
    }

    vm_size_t outsize = 0;
    kern_return_t kr = vm_read_overwrite(g_vphone_tfp0, kaddr, len,
                                              (vm_address_t)buf, &outsize);
    if (kr != KERN_SUCCESS)
        memset(buf, 0, len);
}

void vphone_kwrite_buf(uint64_t kaddr, const void *buf, size_t len) {
    if (vphone_helper_kwrite(kaddr, buf, len))
        return;

    if (g_vphone_libkrw_kwrite) {
        g_vphone_libkrw_kwrite((void *)buf, kaddr, len);
        return;
    }

    vm_write(g_vphone_tfp0, kaddr, (vm_offset_t)buf, (mach_msg_type_number_t)len);
}

#pragma mark - Detection

static NSString *vphone_current_ios_version_string(void) {
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    if (version.patchVersion > 0) {
        return [NSString stringWithFormat:@"%ld.%ld.%ld",
                                          (long)version.majorVersion,
                                          (long)version.minorVersion,
                                          (long)version.patchVersion];
    }
    return [NSString stringWithFormat:@"%ld.%ld",
                                      (long)version.majorVersion,
                                      (long)version.minorVersion];
}

bool vphone_ios_version_supported(void) {
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    return version.majorVersion == 26 &&
           version.minorVersion >= 1 &&
           version.minorVersion <= 5;
}

bool vphone_tfp0_available(void) {
    if (g_vphone_helper_ready)
        return true;

    if (g_vphone_libkrw_kread || g_vphone_libkrw_kwrite)
        return true;

    mach_port_t test_port = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), 0, &test_port);
    if (kr == KERN_SUCCESS && test_port != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), test_port);
        return true;
    }
    return false;
}

bool vphone_is_available(void) {
    if (!vphone_ios_version_supported())
        return false;
    return vphone_tfp0_available();
}

#pragma mark - Kernel base

static uint64_t vphone_kernel_unslid_base_for_kernel_base(uint64_t kernel_base) {
    static const uint64_t unslid_bases[] = {
        0xFFFFFE0007004000ULL, // vphone600 kernelcache
        0xFFFFFFF007004000ULL, // normal iPhone/iPad kernelcache
    };

    for (size_t i = 0; i < sizeof(unslid_bases) / sizeof(unslid_bases[0]); i++) {
        uint64_t unslid_base = unslid_bases[i];
        if (kernel_base >= unslid_base &&
            ((kernel_base >> 40) == (unslid_base >> 40))) {
            return unslid_base;
        }
    }
    return 0;
}

static void vphone_apply_kernel_window_for_base(uint64_t kernel_base) {
    if ((kernel_base >> 40) == 0xFFFFFEULL) {
        // vphone600 kernelcaches are linked in the 0xfffffe... window even
        // when userland identifies as an iPhone model.  offsets_init() only
        // selects this range for M-series iPads, so force it here before any
        // proc/task/IPC pointer validation happens.
        VM_MIN_KERNEL_ADDRESS = 0xFFFFFE0000000000ULL;
        VM_MAX_KERNEL_ADDRESS = 0xFFFFFE8FFFFFFFFFULL;
        t1sz_boot = 0x11;
    }
}

static bool vphone_set_kernel_base_if_valid(uint64_t kernel_base, const char *source) {
    if (!kernel_base)
        return false;

    uint32_t magic = 0;
    vphone_kread_buf(kernel_base, &magic, sizeof(magic));
    if (magic != MH_MAGIC_64)
        return false;

    uint64_t unslid_base = vphone_kernel_unslid_base_for_kernel_base(kernel_base);
    g_kernel_base = kernel_base;
    g_kernel_slide = unslid_base ? kernel_base - unslid_base : 0;
    vphone_apply_kernel_window_for_base(kernel_base);

    printf("[VPHONE] kernel base %#llx slide %#llx via %s window=[%#llx,%#llx] t1sz=0x%llx smr=0x%llx\n",
           g_kernel_base, g_kernel_slide, source,
           VM_MIN_KERNEL_ADDRESS, VM_MAX_KERNEL_ADDRESS, t1sz_boot, smr_base);
    return true;
}

static bool vphone_find_kernel_base(void) {
    if (g_vphone_helper_ready) {
        uint64_t helper_base = 0;
        if (vphone_helper_kbase(&helper_base) &&
            vphone_set_kernel_base_if_valid(helper_base, "root-helper kbase")) {
            return true;
        }
        printf("[VPHONE] root helper kbase failed; refusing unsafe blind kernel-base scan\n");
        return false;
    }

    if (g_vphone_libkrw_kbase) {
        uint64_t libkrw_base = 0;
        int ret = g_vphone_libkrw_kbase(&libkrw_base);
        if (ret == 0 && vphone_set_kernel_base_if_valid(libkrw_base, "libkrw kbase")) {
            return true;
        }
        printf("[VPHONE] libkrw kbase returned %d base %#llx; refusing unsafe blind kernel-base scan\n",
               ret, libkrw_base);
        return false;
    }

    /*
     * Do not blind-scan the 0xfffffe.../0xfffffff... unslid windows on vphone.
     * A failed probe at 0xfffffe0007004000 can panic the guest with
     * "Unexpected fault in kernel physical aperture".  The vphone path must
     * get KBASE from the root helper/libkrw provider instead.
     */
#if 0
    static const uint64_t unslid_bases[] = {
        0xFFFFFE0007004000ULL, // vphone600 kernelcache
        0xFFFFFFF007004000ULL, // normal iPhone/iPad kernelcache
    };

    for (size_t i = 0; i < sizeof(unslid_bases) / sizeof(unslid_bases[0]); i++) {
        uint64_t unslid_base = unslid_bases[i];
        for (uint64_t slide = 0; slide <= 0x20000000ULL; slide += 0x4000) {
            uint64_t candidate = unslid_base + slide;
            uint32_t magic = 0;
            vm_size_t outsize = 0;
            kern_return_t kr = vm_read_overwrite(g_vphone_tfp0, candidate, 4,
                                                 (vm_address_t)&magic, &outsize);
            if (g_vphone_libkrw_kread) {
                kr = (g_vphone_libkrw_kread(candidate, &magic, sizeof(magic)) == 0)
                    ? KERN_SUCCESS : KERN_FAILURE;
            }
            if (kr == KERN_SUCCESS && magic == MH_MAGIC_64) {
                return vphone_set_kernel_base_if_valid(candidate, "scan");
            }
        }
    }
#endif

    printf("[VPHONE] kernel base not found\n");
    return false;
}

#pragma mark - Proc finding

static uint64_t vphone_xpaci(uint64_t a) {
    if (!gIsPACSupported) return a;
    if ((a >> 48) == 0xFFFF) return a;
    return xpaci(a);
}

static bool vphone_is_kptr(uint64_t v) {
    if (!v) return false;
    if (VM_MIN_KERNEL_ADDRESS && VM_MAX_KERNEL_ADDRESS)
        return v >= VM_MIN_KERNEL_ADDRESS && v <= VM_MAX_KERNEL_ADDRESS;
    return (v & 0xfffff00000000000ULL) == 0xfffff00000000000ULL;
}

static bool vphone_find_self_proc(void) {
    pid_t my_pid = getpid();

    struct mach_header_64 hdr;
    vphone_kread_buf(g_kernel_base, &hdr, sizeof(hdr));
    if (hdr.magic != MH_MAGIC_64) {
        printf("[VPHONE] bad kernel Mach-O header\n");
        return false;
    }

    uint64_t cmd_off = g_kernel_base + sizeof(struct mach_header_64);
    uint64_t data_start = 0, data_end = 0;

    for (uint32_t i = 0; i < hdr.ncmds; i++) {
        struct segment_command_64 seg;
        vphone_kread_buf(cmd_off, &seg, sizeof(seg));

        if (seg.cmd == LC_SEGMENT_64) {
            bool is_data = (strncmp(seg.segname, "__DATA", 6) == 0);
            if (is_data && seg.vmsize > 0) {
                uint64_t seg_start = seg.vmaddr + g_kernel_slide;
                if (!data_start || seg_start < data_start)
                    data_start = seg_start;
                uint64_t end = seg_start + seg.vmsize;
                if (end > data_end)
                    data_end = end;
            }
        }
        cmd_off += seg.cmdsize;
    }

    if (!data_start || data_end <= data_start) {
        printf("[VPHONE] DATA segment not found\n");
        return false;
    }

    printf("[VPHONE] scanning DATA %#llx–%#llx for allproc\n", data_start, data_end);

    uint64_t scan_len = data_end - data_start;
    uint64_t chunk_sz = 0x4000;
    uint8_t *chunk = malloc(chunk_sz);
    if (!chunk) return false;

    for (uint64_t off = 0; off < scan_len; off += chunk_sz) {
        uint64_t this_chunk = (scan_len - off < chunk_sz) ? (scan_len - off) : chunk_sz;
        vphone_kread_buf(data_start + off, chunk, this_chunk);

        for (uint64_t j = 0; j + 8 <= this_chunk; j += 8) {
            uint64_t candidate_ptr;
            memcpy(&candidate_ptr, chunk + j, 8);
            candidate_ptr = vphone_xpaci(candidate_ptr);

            if (!vphone_is_kptr(candidate_ptr))
                continue;

            uint64_t le_prev = vphone_xpaci(vphone_kread64(candidate_ptr + off_proc_p_list_le_prev));
            uint64_t allproc_addr = data_start + off + j;
            if (le_prev != allproc_addr)
                continue;

            uint32_t first_pid = vphone_kread32(candidate_ptr + off_proc_p_pid);
            if (first_pid > 65535)
                continue;

            printf("[VPHONE] allproc at %#llx (first proc %#llx pid %d)\n",
                   allproc_addr, candidate_ptr, first_pid);

            uint64_t proc = candidate_ptr;
            for (int k = 0; k < 4096 && vphone_is_kptr(proc); k++) {
                uint32_t cur_pid = vphone_kread32(proc + off_proc_p_pid);
                if (cur_pid == (uint32_t)my_pid) {
                    extern uint64_t gSelfProc;
                    extern uint64_t gSelfTask;
                    gSelfProc = proc;
                    gSelfTask = proc_task(proc);
                    printf("[VPHONE] self proc %#llx task %#llx pid %d\n",
                           gSelfProc, gSelfTask, my_pid);
                    free(chunk);
                    return vphone_is_kptr(gSelfTask);
                }
                uint64_t next = vphone_xpaci(vphone_kread64(proc + off_proc_p_list_le_next));
                if (!vphone_is_kptr(next) || next == proc)
                    break;
                proc = next;
            }
        }
    }

    free(chunk);
    printf("[VPHONE] allproc scan failed; pid %d not found\n", my_pid);
    return false;
}

#pragma mark - Bootstrap

static void vphone_reset_libkrw(void) {
    g_vphone_libkrw_kbase = NULL;
    g_vphone_libkrw_kread = NULL;
    g_vphone_libkrw_kwrite = NULL;

    if (g_vphone_libkrw) {
        dlclose(g_vphone_libkrw);
        g_vphone_libkrw = NULL;
    }
}

static bool vphone_try_libkrw(void) {
    static const char *lib_paths[] = {
        "/var/jb/usr/lib/libkrw.0.dylib",
        "/usr/lib/libkrw.0.dylib",
    };

    vphone_reset_libkrw();

    for (size_t i = 0; i < sizeof(lib_paths) / sizeof(lib_paths[0]); i++) {
        const char *path = lib_paths[i];
        void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!handle) {
            const char *err = dlerror();
            printf("[VPHONE] dlopen(%s) failed: %s\n", path, err ? err : "unknown");
            continue;
        }

        g_vphone_libkrw_kbase = (vphone_libkrw_kbase_t)dlsym(handle, "kbase");
        g_vphone_libkrw_kread = (vphone_libkrw_kread_t)dlsym(handle, "kread");
        g_vphone_libkrw_kwrite = (vphone_libkrw_kwrite_t)dlsym(handle, "kwrite");

        if (g_vphone_libkrw_kread && g_vphone_libkrw_kwrite) {
            g_vphone_libkrw = handle;
            printf("[VPHONE] using libkrw backend at %s\n", path);
            return true;
        }

        printf("[VPHONE] libkrw at %s missing required kread/kwrite exports\n", path);
        dlclose(handle);
        g_vphone_libkrw_kbase = NULL;
        g_vphone_libkrw_kread = NULL;
        g_vphone_libkrw_kwrite = NULL;
    }

    return false;
}

static bool vphone_try_root_helper(void) {
    g_vphone_helper_ready = false;
    if (!vphone_helper_ping()) {
        pthread_mutex_lock(&g_vphone_helper_lock);
        vphone_helper_close_locked();
        pthread_mutex_unlock(&g_vphone_helper_lock);
        printf("[VPHONE] root helper backend is not available\n");
        return false;
    }

    printf("[VPHONE] using root helper backend at %s\n", CY_VPHONE_KRW_SOCKET);
    return true;
}

static bool vphone_try_tfp0(void) {
    kern_return_t kr = task_for_pid(mach_task_self(), 0, &g_vphone_tfp0);
    if (kr != KERN_SUCCESS || g_vphone_tfp0 == MACH_PORT_NULL) {
        printf("[VPHONE] task_for_pid(0) failed: %s (%d)\n", mach_error_string(kr), kr);
        return false;
    }

    printf("[VPHONE] tfp0 port 0x%x\n", g_vphone_tfp0);
    return true;
}

static bool vphone_try_host_special_tfp0(void) {
    mach_port_t special = MACH_PORT_NULL;
    kern_return_t kr = host_get_special_port(mach_host_self(), HOST_LOCAL_NODE, 4, &special);
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(special)) {
        printf("[VPHONE] host special port 4 failed: %s (%d) port 0x%x\n",
               mach_error_string(kr), kr, special);
        return false;
    }

    g_vphone_tfp0 = special;
    printf("[VPHONE] tfp0 via host special port 4: 0x%x\n", g_vphone_tfp0);
    return true;
}

static bool vphone_finish_kernel_backend(const char *backend_name) {
    g_vphone_mode = true;

    offsets_init();

    if (!vphone_find_kernel_base()) {
        printf("[VPHONE] %s backend could not read kernel base\n", backend_name);
        g_vphone_mode = false;
        return false;
    }

    if (!vphone_find_self_proc()) {
        printf("[VPHONE] %s backend found kernel base but not self proc\n", backend_name);
        g_vphone_mode = false;
        return false;
    }

    return true;
}

bool vphone_bootstrap(void) {
    printf("[VPHONE] bootstrapping jailbreak-provided kernel r/w\n");
    printf("[VPHONE] process creds uid=%d euid=%d gid=%d egid=%d\n",
           getuid(), geteuid(), getgid(), getegid());

    if (!vphone_ios_version_supported()) {
        NSString *version = vphone_current_ios_version_string();
        printf("[VPHONE] unsupported iOS %s; supported vphone versions are iOS 26.1–26.5\n",
               version.UTF8String);
        return false;
    }

    if (vphone_try_root_helper()) {
        if (vphone_finish_kernel_backend("root helper")) {
            log_user("[VPHONE] kernel r/w ready — root helper mode (Sileo-style jailbreak environment)\n");
            return true;
        }

        printf("[VPHONE] root helper backend did not work; falling back to libkrw/tfp0\n");
        pthread_mutex_lock(&g_vphone_helper_lock);
        vphone_helper_close_locked();
        pthread_mutex_unlock(&g_vphone_helper_lock);
        g_kernel_base = 0;
        g_kernel_slide = 0;
    }

    if (vphone_try_libkrw()) {
        if (vphone_finish_kernel_backend("libkrw")) {
            log_user("[VPHONE] kernel r/w ready — libkrw mode (no exploit needed)\n");
            return true;
        }

        printf("[VPHONE] libkrw exported kread/kwrite but did not work; falling back to direct tfp0\n");
        vphone_reset_libkrw();
        g_kernel_base = 0;
        g_kernel_slide = 0;
    }

    if (vphone_try_host_special_tfp0()) {
        if (vphone_finish_kernel_backend("host-special tfp0")) {
            log_user("[VPHONE] kernel r/w ready — host-special tfp0 mode (no exploit needed)\n");
            return true;
        }
        g_vphone_tfp0 = MACH_PORT_NULL;
        g_kernel_base = 0;
        g_kernel_slide = 0;
    }

    if (vphone_try_tfp0()) {
        if (vphone_finish_kernel_backend("task_for_pid tfp0")) {
            log_user("[VPHONE] kernel r/w ready — tfp0 mode (no exploit needed)\n");
            return true;
        }
        g_vphone_tfp0 = MACH_PORT_NULL;
    }

    printf("[VPHONE] no working jailbreak kernel r/w backend available\n");
    return false;
}

bool vphone_krw_ready(void) {
    if (!g_vphone_mode)
        return false;
    if (!g_vphone_helper_ready && !g_vphone_libkrw_kread && g_vphone_tfp0 == MACH_PORT_NULL)
        return false;

    uint32_t magic = 0;
    if (g_vphone_helper_ready) {
        return vphone_helper_kread(g_kernel_base, &magic, sizeof(magic)) &&
               magic == MH_MAGIC_64;
    }

    if (g_vphone_libkrw_kread) {
        int ret = g_vphone_libkrw_kread(g_kernel_base, &magic, sizeof(magic));
        return (ret == 0 && magic == MH_MAGIC_64);
    }

    vm_size_t outsize = 0;
    kern_return_t kr = vm_read_overwrite(g_vphone_tfp0, g_kernel_base, 4,
                                              (vm_address_t)&magic, &outsize);
    return (kr == KERN_SUCCESS && magic == MH_MAGIC_64);
}
