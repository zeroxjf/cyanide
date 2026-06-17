//
//  RemoteCall.h
//  Cyanide
//
//  Created by seo on 3/29/26.
//

#ifndef RemoteCall_h
#define RemoteCall_h

#import <mach/mach.h>
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

struct VMShmem {
    uint64_t port;
    uint64_t remoteAddress;
    uint64_t localAddress;
    bool     used;
};

// from Duy Tran's TaskPortHaxxApp
// https://github.com/khanhduytran0/TaskPortHaxxApp/blob/pacbypass/TaskPortHaxxApp/Header.h#L83
typedef struct {
    uint64_t __x[29];       /* General purpose registers x0-x28 */
    uint64_t __fp; /* Frame pointer x29 */
    uint64_t __lr; /* Link register x30 */
    uint64_t __sp; /* Stack pointer x31 */
    uint64_t __pc; /* Program counter */
    uint32_t __cpsr;        /* Current program status register */
    uint32_t __flags; /* Flags describing structure format */
} arm_thread_state64_internal;

typedef enum {
    RemoteCallInitFailureNone = 0,
    RemoteCallInitFailureKRWUnavailable,
    RemoteCallInitFailureProcessMissing,
    RemoteCallInitFailureInvalidTask,
    RemoteCallInitFailureExceptionPort,
    RemoteCallInitFailureTaskGuard,
    RemoteCallInitFailureLocalThread,
    RemoteCallInitFailureNoTargetThreads,
    RemoteCallInitFailureFirstExceptionTimeout,
    RemoteCallInitFailureOther,
} RemoteCallInitFailure;

mach_port_t create_exception_port(void);
int disable_excguard_kill(uint64_t task);
// One-shot override consumed by the next call to init_remote_call. When
// non-zero, init_remote_call skips its proc_find_by_name lookup and uses
// this kernel proc address directly. Useful when there are multiple
// processes with the same name (e.g. system vs per-user cfprefsd) and we
// need to target a specific one. Reset to 0 by init_remote_call.
extern uint64_t g_RC_targetProcOverride;
int init_remote_call(const char* process, bool useMigFilterBypass);
int init_remote_call_with_first_exception_timeout(const char* process, bool useMigFilterBypass, int firstExceptionTimeoutMS);
int init_remote_call_original_thread_only_with_first_exception_timeout(const char* process, bool useMigFilterBypass, int firstExceptionTimeoutMS);
uint64_t do_remote_call_stable(int timeout, const char *name, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3, uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7);
uint64_t do_remote_call_stable_addr(int timeout, uint64_t pcAddr, const char *name, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3, uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7);
void sign_state(uint64_t signingThread, arm_thread_state64_internal *state, uint64_t pc, uint64_t lr);
uint64_t remote_pac(uint64_t remoteThreadAddr, uint64_t address, uint64_t modifier);
bool remote_read(uint64_t src, void *dst, uint64_t size);
uint64_t remote_read64(uint64_t src);
void remote_hexdump(uint64_t remoteAddr, size_t size);
bool remote_write(uint64_t dst, const void *src, uint64_t size);
bool remote_write64(uint64_t dst, uint64_t val);
bool remote_writeStr(uint64_t dst, const char *str);
uint64_t remote_call_trojan_mem(void);
int destroy_remote_call(void);
// Drop every piece of local RemoteCall state without trying to IPC the remote
// task. Use this when the remote task is known dead (e.g. SpringBoard just
// crashed and respawned) — destroy_remote_call would otherwise hang for
// 100s on its munmap/pthread_exit calls into a vanished trojan thread.
void abandon_remote_call(void);
bool remote_call_has_local_state(void);
bool remote_call_current_success(void);
int remote_call_current_pid(void);
int remote_call_set_stable_timeout_floor_ms(int timeoutMS);
bool remote_call_vphone_springboard_bridge_available(void);
RemoteCallInitFailure remote_call_last_init_failure(void);
uint32_t remote_call_last_init_failure_pid(void);
const char *remote_call_init_failure_description(RemoteCallInitFailure failure);

#ifdef __OBJC__
@class RemotePointer;

@interface RemoteCallSession : NSObject

@property(nonatomic, readonly) uint64_t taskAddr;
@property(nonatomic, readonly) uint64_t trojanMem;
@property(nonatomic, readonly) int pid;

- (instancetype)initWithProcess:(NSString *)process useMigFilterBypass:(BOOL)useMigFilterBypass;
- (instancetype)initWithProcess:(NSString *)process
              useMigFilterBypass:(BOOL)useMigFilterBypass
         firstExceptionTimeoutMS:(int)firstExceptionTimeoutMS;
- (instancetype)initWithProcess:(NSString *)process
              useMigFilterBypass:(BOOL)useMigFilterBypass
         firstExceptionTimeoutMS:(int)firstExceptionTimeoutMS
              originalThreadOnly:(BOOL)originalThreadOnly;
- (uint64_t)doRemoteCallStableWithTimeout:(int)timeout
                             functionName:(const char *)name
                                       x0:(uint64_t)x0
                                       x1:(uint64_t)x1
                                       x2:(uint64_t)x2
                                       x3:(uint64_t)x3
                                       x4:(uint64_t)x4
                                       x5:(uint64_t)x5
                                       x6:(uint64_t)x6
                                       x7:(uint64_t)x7;
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
                                       x7:(uint64_t)x7;
- (BOOL)remoteRead:(uint64_t)src to:(void *)dst size:(uint64_t)size;
- (uint64_t)remoteRead64:(uint64_t)src;
- (BOOL)remoteWrite:(uint64_t)dst from:(const void *)src size:(uint64_t)size;
- (BOOL)remoteWrite64:(uint64_t)dst value:(uint64_t)val;
- (BOOL)remoteWriteString:(uint64_t)dst value:(const char *)str;
- (int)destroyRemoteCall;
- (void)abandonRemoteCall;
- (BOOL)hasLocalState;
- (RemotePointer *)objectAtIndexedSubscript:(NSUInteger)address;

@end

@interface RemotePointer : NSObject

@property(nonatomic, strong, readonly) RemoteCallSession *session;
@property(nonatomic, readonly) uint64_t address;

@property(nonatomic, copy) NSString *string;
@property(nonatomic) uint8_t value8;
@property(nonatomic) uint16_t value16;
@property(nonatomic) uint32_t value32;
@property(nonatomic) uint64_t value64;

- (instancetype)initWithSession:(RemoteCallSession *)session address:(uint64_t)address;
- (BOOL)writeCString:(const char *)string;
- (BOOL)readTo:(void *)dst size:(uint64_t)size;
- (BOOL)writeFrom:(const void *)src size:(uint64_t)size;
- (NSString *)stringWithMaxLength:(size_t)maxLength;

@end

void remote_call_with_session(RemoteCallSession *session, void (^block)(void));
#endif

#endif /* RemoteCall_h */
