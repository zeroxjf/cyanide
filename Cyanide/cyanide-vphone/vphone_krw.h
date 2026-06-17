#ifndef vphone_krw_h
#define vphone_krw_h

#import <stdint.h>
#import <stdbool.h>
#import <stddef.h>

extern bool g_vphone_mode;

bool vphone_tfp0_available(void);
bool vphone_ios_version_supported(void);
bool vphone_is_available(void);
bool vphone_bootstrap(void);
bool vphone_krw_ready(void);

uint64_t vphone_kread64(uint64_t kaddr);
uint32_t vphone_kread32(uint64_t kaddr);
void vphone_kwrite64(uint64_t kaddr, uint64_t val);
void vphone_kwrite32(uint64_t kaddr, uint32_t val);
void vphone_kread_buf(uint64_t kaddr, void *buf, size_t len);
void vphone_kwrite_buf(uint64_t kaddr, const void *buf, size_t len);

#endif
