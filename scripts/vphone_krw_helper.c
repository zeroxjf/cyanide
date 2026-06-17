#include <errno.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

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

/*
 * iphoneos exports mach_vm_region_recurse, but mach/mach_vm.h is blocked for
 * third-party builds.  Keep a local prototype so the helper can enumerate the
 * kernel task map without blind-reading candidate slide addresses.
 */
extern kern_return_t mach_vm_region_recurse(vm_map_t target_task,
                                            mach_vm_address_t *address,
                                            mach_vm_size_t *size,
                                            natural_t *nesting_depth,
                                            vm_region_recurse_info_t info,
                                            mach_msg_type_number_t *infoCnt);

static mach_port_t g_tfp0 = MACH_PORT_NULL;
static uint64_t g_kernel_base = 0;

static bool read_full(int fd, void *buf, size_t len) {
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

static bool write_full(int fd, const void *buf, size_t len) {
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

static void send_status(int fd, int32_t status, uint64_t value, uint64_t len) {
    cy_vphone_krw_resp_t resp = {
        .magic = CY_VPHONE_KRW_MAGIC,
        .status = status,
        .value = value,
        .len = len,
    };
    (void)write_full(fd, &resp, sizeof(resp));
}

static bool helper_kread_raw(uint64_t addr, void *buf, size_t len) {
    vm_size_t out = 0;
    kern_return_t kr = vm_read_overwrite(g_tfp0,
                                         (vm_address_t)addr,
                                         (vm_size_t)len,
                                         (vm_address_t)buf,
                                         &out);
    return kr == KERN_SUCCESS && out == len;
}

static bool helper_kread(uint64_t addr, void *buf, size_t len) {
    /*
     * On vphone 26.1, vm_read_overwrite() through tfp0 can panic the guest if
     * asked to read from the low 0xfffffe... physical aperture while probing
     * for a slide.  Do not service arbitrary KREADs until KBASE has found the
     * real kernelcache mapping via the VM map.
     */
    if (!g_kernel_base) {
        return false;
    }
    return helper_kread_raw(addr, buf, len);
}

static bool helper_kwrite(uint64_t addr, const void *buf, size_t len) {
    if (!g_kernel_base) {
        return false;
    }

    kern_return_t kr = vm_write(g_tfp0,
                                (vm_address_t)addr,
                                (vm_offset_t)buf,
                                (mach_msg_type_number_t)len);
    return kr == KERN_SUCCESS;
}

static uint64_t helper_find_kernel_base(void) {
    /*
     * Disabled on vphone 26.x: kernel-map probing through tfp0/libkrw can
     * panic the guest when it touches the physical-aperture window.  Cyanide's
     * vphone path now uses a Sileo-style SpringBoard bridge for RemoteCall
     * tweaks instead of requiring app-side kernel r/w.
     */
    return 0;
}

static bool helper_init_tfp0(void) {
    if (MACH_PORT_VALID(g_tfp0)) return true;

    kern_return_t kr = task_for_pid(mach_task_self(), 0, &g_tfp0);
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(g_tfp0)) {
        fprintf(stderr,
                "cyanide vphone krw helper: task_for_pid(0) failed: %s (%d) port=0x%x uid=%d euid=%d\n",
                mach_error_string(kr),
                kr,
                g_tfp0,
                getuid(),
                geteuid());
        g_tfp0 = MACH_PORT_NULL;
        return false;
    }

    return true;
}

static void helper_dump_regions(const char *label,
                                mach_vm_address_t start,
                                unsigned int limit) {
    mach_vm_address_t addr = start;
    natural_t depth = 0;
    printf("region-dump %s start=0x%llx limit=%u\n", label, start, limit);
    for (unsigned int i = 0; i < limit; i++) {
        mach_vm_size_t size = 0;
        vm_region_submap_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = mach_vm_region_recurse(g_tfp0,
                                                  &addr,
                                                  &size,
                                                  &depth,
                                                  (vm_region_recurse_info_t)&info,
                                                  &count);
        if (kr != KERN_SUCCESS || size == 0) {
            printf("region[%u] kr=%d addr=0x%llx size=0x%llx depth=%u stop\n",
                   i, kr, addr, size, depth);
            return;
        }

        printf("region[%u] addr=0x%llx size=0x%llx depth=%u prot=%x max=%x sub=%d tag=%u share=%u obj=0x%llx res=%u dirty=%u ref=%u shadow=%u\n",
               i,
               addr,
               size,
               depth,
               info.protection,
               info.max_protection,
               info.is_submap,
               info.user_tag,
               info.share_mode,
               (unsigned long long)info.object_id,
               info.pages_resident,
               info.pages_dirtied,
               info.ref_count,
               info.shadow_depth);

        if (info.is_submap && depth < 32) {
            depth++;
            continue;
        }

        if (UINT64_MAX - addr <= size) {
            return;
        }
        addr += size;
    }
}

static void handle_client(int fd) {
    cy_vphone_krw_req_t req;
    while (read_full(fd, &req, sizeof(req))) {
        if (req.magic != CY_VPHONE_KRW_MAGIC) {
            send_status(fd, EPROTO, 0, 0);
            return;
        }

        switch (req.cmd) {
            case CY_VPHONE_KRW_CMD_PING:
                send_status(fd, 0, CY_VPHONE_KRW_VERSION, 0);
                break;

            case CY_VPHONE_KRW_CMD_KBASE: {
                uint64_t base = helper_find_kernel_base();
                send_status(fd, base ? 0 : ENOENT, base, 0);
                break;
            }

            case CY_VPHONE_KRW_CMD_KREAD: {
                if (req.len == 0 || req.len > 0x100000) {
                    send_status(fd, EINVAL, 0, 0);
                    break;
                }
                void *buf = calloc(1, (size_t)req.len);
                if (!buf) {
                    send_status(fd, ENOMEM, 0, 0);
                    break;
                }
                bool ok = helper_kread(req.addr, buf, (size_t)req.len);
                send_status(fd, ok ? 0 : EIO, 0, ok ? req.len : 0);
                if (ok) (void)write_full(fd, buf, (size_t)req.len);
                free(buf);
                break;
            }

            case CY_VPHONE_KRW_CMD_KWRITE: {
                if (req.len == 0 || req.len > 0x100000) {
                    send_status(fd, EINVAL, 0, 0);
                    break;
                }
                void *buf = malloc((size_t)req.len);
                if (!buf) {
                    send_status(fd, ENOMEM, 0, 0);
                    break;
                }
                if (!read_full(fd, buf, (size_t)req.len)) {
                    free(buf);
                    return;
                }
                bool ok = helper_kwrite(req.addr, buf, (size_t)req.len);
                free(buf);
                send_status(fd, ok ? 0 : EIO, 0, 0);
                break;
            }

            case CY_VPHONE_KRW_CMD_SHUTDOWN:
                send_status(fd, 0, 0, 0);
                close(fd);
                unlink(CY_VPHONE_KRW_SOCKET);
                exit(0);

            default:
                send_status(fd, ENOTSUP, 0, 0);
                break;
        }
    }
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);

    /*
     * vphone's jailbreak honors setuid on helper tools.  The app launches this
     * as uid=mobile/euid=root; commit to root so task_for_pid(0) follows the
     * same root-service model Sileo/dpkg helpers use.
     */
    (void)setgid(0);
    (void)setuid(0);

    if (!helper_init_tfp0()) return 2;

    if (argc > 1 && strcmp(argv[1], "--dump-regions") == 0) {
        printf("kernel region probing disabled on vphone; use SpringBoard bridge\n");
        return 6;
    }

    if (argc > 1 && (strcmp(argv[1], "--self-test") == 0 ||
                     strcmp(argv[1], "--self-test-verbose") == 0)) {
        uint64_t base = helper_find_kernel_base();
        printf("uid=%d euid=%d tfp0=0x%x kbase=0x%llx\n",
               getuid(), geteuid(), g_tfp0, base);
        printf("kernel read self-test disabled on vphone; use SpringBoard bridge\n");
        return 6;
    }

    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) return 3;

    unlink(CY_VPHONE_KRW_SOCKET);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, CY_VPHONE_KRW_SOCKET, sizeof(addr.sun_path));

    if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(server);
        return 4;
    }
    chmod(CY_VPHONE_KRW_SOCKET, 0666);

    if (listen(server, 4) != 0) {
        close(server);
        unlink(CY_VPHONE_KRW_SOCKET);
        return 5;
    }

    for (;;) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(server, &fds);
        struct timeval tv = { .tv_sec = 300, .tv_usec = 0 };
        int ready = select(server + 1, &fds, NULL, NULL, &tv);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0) break;

        int client = accept(server, NULL, NULL);
        if (client < 0) continue;
        handle_client(client);
        close(client);
    }

    close(server);
    unlink(CY_VPHONE_KRW_SOCKET);
    return 0;
}
