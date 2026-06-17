//
//  PatreonAuth.m
//  Cyanide
//

#import "PatreonAuth.h"
#import "LogTextView.h"
#import <AuthenticationServices/AuthenticationServices.h>
#import <Security/Security.h>


static NSString * const kWorkerBaseURL   = @"https://cyanide-patreon-auth.hackerboii.workers.dev";
static NSString * const kClientID        = @"OmxCv5I3o6-STTChSezarjQ8-3g74Lytuojfk3c8a9e7g9Ze63cuxhnANzYyG914";
static NSString * const kCallbackScheme  = @"com.zeroxjf.ios-cyanide1";
static NSString * const kRedirectURI     = @"https://cyanide-patreon-auth.hackerboii.workers.dev/patreon/callback";

static const uint8_t kPatreonPubKey[65] = {
    0x04,
    0xbc,0x0c,0xe0,0x59,0xbd,0x1d,0xf8,0x6d, 0x3d,0xf1,0x3c,0x4a,0xae,0x4b,0x56,0x56,
    0xff,0x07,0x91,0xb7,0xaa,0x92,0x86,0x15, 0x3e,0x40,0xaa,0x57,0x89,0xc4,0x32,0x34,
    0xe7,0x49,0x88,0x2e,0xc2,0x7a,0x5b,0x99, 0xe5,0xd4,0x69,0x6f,0xfc,0x27,0x94,0x05,
    0xad,0x6c,0xdf,0x24,0x15,0xbc,0x50,0xc4, 0x8e,0xe3,0xa4,0x46,0x7b,0x96,0x4e,0xc8,
};

static NSString * const kKeychainService = @"com.zeroxjf.cyanide.patreon";
static NSString * const kKeychainToken   = @"signed_token";

static NSString * const kDefaultsLinked      = @"CyanidePatreonLinked";
static NSString * const kDefaultsDisplayName = @"CyanidePatreonDisplayName";
static NSString * const kDefaultsTierTitle   = @"CyanidePatreonTierTitle";
static NSString * const kDefaultsPledgeCents = @"CyanidePatreonPledgeCents";
static NSString * const kDefaultsLastRefresh = @"CyanidePatreonLastRefresh";

static NSString * const kPatreonCompedUsername = @"AppleAttack";

NSString * const kCyanidePatreonStatusDidChangeNotification = @"CyanidePatreonStatusDidChangeNotification";

static NSString * const kPatreonJoinURL = @"https://www.patreon.com/zeroxjf";

NSURL *cyanide_patreon_join_url(void)
{
    return [NSURL URLWithString:kPatreonJoinURL];
}

#pragma mark - Keychain helpers

static NSDictionary *keychain_base_query(NSString *account)
{
    return @{ (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: kKeychainService,
              (__bridge id)kSecAttrAccount: account };
}

static NSString *defaults_fallback_key(NSString *account)
{
    return [@"CyanidePatreonFallback_" stringByAppendingString:account];
}

static void keychain_set_string(NSString *account, NSString *_Nullable value)
{
    NSDictionary *query = keychain_base_query(account);
    SecItemDelete((__bridge CFDictionaryRef)query);

    if (value.length == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:defaults_fallback_key(account)];
        return;
    }

    NSMutableDictionary *add = [query mutableCopy];
    add[(__bridge id)kSecValueData] = [value dataUsingEncoding:NSUTF8StringEncoding];
    add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    OSStatus s = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    if (s == errSecSuccess) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:defaults_fallback_key(account)];
        return;
    }
    printf("[PATREON] keychain SecItemAdd(%s) failed: %d; using defaults fallback\n",
           account.UTF8String, (int)s);
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:defaults_fallback_key(account)];
}

static NSString *_Nullable keychain_get_string(NSString *account)
{
    NSMutableDictionary *q = [keychain_base_query(account) mutableCopy];
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    q[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef out = NULL;
    OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (s == errSecSuccess && out != NULL) {
        NSData *data = (__bridge_transfer NSData *)out;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return [[NSUserDefaults standardUserDefaults] stringForKey:defaults_fallback_key(account)];
}

#pragma mark - Notification + cached display helpers

static void post_status_changed(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:kCyanidePatreonStatusDidChangeNotification
                          object:nil];
    });
}

static void update_cached_display(BOOL linked,
                                  NSString *_Nullable displayName,
                                  NSString *_Nullable tierTitle,
                                  NSInteger pledgeCents)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL changed = NO;

    if ([d boolForKey:kDefaultsLinked] != linked) {
        [d setBool:linked forKey:kDefaultsLinked]; changed = YES;
    }
    NSString *prevName = [d stringForKey:kDefaultsDisplayName] ?: @"";
    NSString *newName  = displayName ?: @"";
    if (![prevName isEqualToString:newName]) {
        [d setObject:newName forKey:kDefaultsDisplayName]; changed = YES;
    }
    NSString *prevTier = [d stringForKey:kDefaultsTierTitle] ?: @"";
    NSString *newTier  = tierTitle ?: @"";
    if (![prevTier isEqualToString:newTier]) {
        [d setObject:newTier forKey:kDefaultsTierTitle]; changed = YES;
    }
    if ([d integerForKey:kDefaultsPledgeCents] != pledgeCents) {
        [d setInteger:pledgeCents forKey:kDefaultsPledgeCents]; changed = YES;
    }
    [d setDouble:[[NSDate date] timeIntervalSince1970] forKey:kDefaultsLastRefresh];

    post_status_changed();
}

#pragma mark - Token

static NSData *_Nullable b64url_decode(NSString *s)
{
    if (s.length == 0) return nil;
    NSMutableString *m = [s mutableCopy];
    [m replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, m.length)];
    while (m.length % 4) [m appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:m options:0];
}

static NSDictionary *_Nullable verify_signed_token(NSString *token)
{
    if (token.length == 0) return nil;
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 2) return nil;

    NSData *payloadData = b64url_decode(parts[0]);
    NSData *sigData     = b64url_decode(parts[1]);
    if (!payloadData || !sigData) return nil;

    NSData *pubKeyData = [NSData dataWithBytes:kPatreonPubKey length:sizeof(kPatreonPubKey)];
    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType:      (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass:     (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @256,
    };
    CFErrorRef cfErr = NULL;
    SecKeyRef pubKey = SecKeyCreateWithData((__bridge CFDataRef)pubKeyData,
                                            (__bridge CFDictionaryRef)attrs, &cfErr);
    if (!pubKey) {
        if (cfErr) CFRelease(cfErr);
        return nil;
    }
    BOOL ok = SecKeyVerifySignature(pubKey,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)payloadData,
        (__bridge CFDataRef)sigData,
        &cfErr);
    CFRelease(pubKey);
    if (cfErr) CFRelease(cfErr);
    if (!ok) return nil;

    NSError *jerr = nil;
    id json = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&jerr];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    return json;
}

static NSDictionary *_Nullable current_payload(void)
{
    NSString *tok = keychain_get_string(kKeychainToken);
    NSDictionary *p = verify_signed_token(tok);
    if (!p) return nil;
    NSNumber *exp = p[@"exp"];
    if ([exp isKindOfClass:[NSNumber class]]) {
        if (exp.doubleValue < [[NSDate date] timeIntervalSince1970]) return nil;
    }
    return p;
}

static BOOL patreon_string_matches_comped_username(NSString *_Nullable value)
{
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed caseInsensitiveCompare:kPatreonCompedUsername] == NSOrderedSame;
}

static BOOL patreon_payload_bool(NSDictionary *payload, NSString *key)
{
    id value = payload[key];
    return [value isKindOfClass:[NSNumber class]] && [value boolValue];
}

static BOOL patreon_payload_is_comped_username(NSDictionary *payload)
{
    return patreon_string_matches_comped_username(payload[@"username"]);
}

#pragma mark - Public accessors

BOOL cyanide_patreon_is_linked(void)
{
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsLinked]) return NO;
    return verify_signed_token(keychain_get_string(kKeychainToken)) != nil;
}

BOOL cyanide_is_patron(void)
{
    NSDictionary *p = current_payload();
    if (!p) return NO;
    if (patreon_payload_bool(p, @"is_comped")) return YES;
    if (patreon_payload_is_comped_username(p)) return YES;
    id v = p[@"is_patron"];
    return [v isKindOfClass:[NSNumber class]] && [v boolValue];
}

BOOL cyanide_is_creator(void)
{
    NSDictionary *p = current_payload();
    NSString *tier = [p[@"tier"] isKindOfClass:[NSString class]] ? p[@"tier"] : nil;
    return [tier isEqualToString:@"Creator"];
}

NSString *cyanide_patreon_display_name(void)
{
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsDisplayName];
    return s.length > 0 ? s : nil;
}

NSString *cyanide_patreon_tier_title(void)
{
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsTierTitle];
    return s.length > 0 ? s : nil;
}

NSInteger cyanide_patreon_pledge_cents(void)
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultsPledgeCents];
}

NSDate *cyanide_patreon_last_refresh_date(void)
{
    double t = [[NSUserDefaults standardUserDefaults] doubleForKey:kDefaultsLastRefresh];
    return t > 0 ? [NSDate dateWithTimeIntervalSince1970:t] : nil;
}

#pragma mark - Networking

static NSURLSession *patreon_session(void)
{
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        cfg.timeoutIntervalForRequest = 20.0;
        session = [NSURLSession sessionWithConfiguration:cfg];
    });
    return session;
}

// Issues a JSON POST to a Worker /patreon/* endpoint. Drops the response
// JSON dict into `completion` (or an NSError).
static void worker_post(NSString *path,
                        NSDictionary *body,
                        void (^completion)(NSDictionary *_Nullable resp, NSError *_Nullable err))
{
    NSURL *url = [NSURL URLWithString:[kWorkerBaseURL stringByAppendingString:path]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSError *jerr = nil;
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jerr];
    if (jerr) { completion(nil, jerr); return; }

    NSURLSessionDataTask *task = [patreon_session() dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err) { completion(nil, err); return; }
            NSInteger code = ((NSHTTPURLResponse *)resp).statusCode;
            id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (code != 200 || ![json isKindOfClass:[NSDictionary class]]) {
                NSString *desc = [NSString stringWithFormat:@"Worker %@ returned %ld",
                                  path, (long)code];
                NSString *detail = [json isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
                if ([detail isKindOfClass:[NSString class]]) {
                    desc = [desc stringByAppendingFormat:@" (%@)", detail];
                }
                completion(nil, [NSError errorWithDomain:@"CyanidePatreon" code:code
                                                userInfo:@{NSLocalizedDescriptionKey: desc}]);
                return;
            }
            completion(json, nil);
        }];
    [task resume];
}

static BOOL accept_worker_response(NSDictionary *resp)
{
    NSString *token = resp[@"token"];
    if (![token isKindOfClass:[NSString class]]) return NO;
    NSDictionary *payload = verify_signed_token(token);
    if (!payload) return NO;
    keychain_set_string(kKeychainToken, token);

    NSString *name = payload[@"name"];
    if (![name isKindOfClass:[NSString class]]) name = nil;
    NSString *tier = payload[@"tier"];
    if (![tier isKindOfClass:[NSString class]]) tier = nil;
    NSNumber *cents = payload[@"cents"];
    NSInteger c = [cents isKindOfClass:[NSNumber class]] ? cents.integerValue : 0;
    update_cached_display(YES, name, tier, c);
    return YES;
}

#pragma mark - ASWebAuthenticationSession host

@interface CYPatreonAuthPresenter : NSObject <ASWebAuthenticationPresentationContextProviding>
@property (nonatomic, weak) UIViewController *anchor;
@end

@implementation CYPatreonAuthPresenter
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session
{
    UIWindow *w = self.anchor.view.window;
    if (w) return w;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *win in ((UIWindowScene *)scene).windows) {
            if (win.isKeyWindow) return win;
        }
    }
    return [[UIWindow alloc] init];
}
@end

static CYPatreonAuthPresenter *gPatreonPresenter;
static ASWebAuthenticationSession *gPatreonSession;

#pragma mark - Public API

void cyanide_patreon_authenticate(UIViewController *presenter,
                                  void (^completion)(BOOL success, NSError *_Nullable error))
{
    void (^finish)(BOOL, NSError *) = ^(BOOL ok, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(ok, err);
        });
    };

    NSURLComponents *c = [NSURLComponents componentsWithString:@"https://www.patreon.com/oauth2/authorize"];
    c.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
        [NSURLQueryItem queryItemWithName:@"client_id"     value:kClientID],
        [NSURLQueryItem queryItemWithName:@"redirect_uri"  value:kRedirectURI],
        [NSURLQueryItem queryItemWithName:@"scope"         value:@"identity identity.memberships"],
    ];
    NSURL *authURL = c.URL;

    gPatreonPresenter = [[CYPatreonAuthPresenter alloc] init];
    gPatreonPresenter.anchor = presenter;

    ASWebAuthenticationSession *session = [[ASWebAuthenticationSession alloc]
        initWithURL:authURL
        callbackURLScheme:kCallbackScheme
        completionHandler:^(NSURL *callbackURL, NSError *err) {
            gPatreonSession = nil;
            gPatreonPresenter = nil;

            if (err) {
                if ([err.domain isEqualToString:ASWebAuthenticationSessionErrorDomain] &&
                    err.code == ASWebAuthenticationSessionErrorCodeCanceledLogin) {
                    finish(NO, [NSError errorWithDomain:@"CyanidePatreon" code:NSUserCancelledError
                                              userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}]);
                } else {
                    finish(NO, err);
                }
                return;
            }

            NSString *code = nil, *errorStr = nil;
            NSURLComponents *comp = [NSURLComponents componentsWithURL:callbackURL resolvingAgainstBaseURL:NO];
            for (NSURLQueryItem *q in comp.queryItems) {
                if ([q.name isEqualToString:@"code"])  code = q.value;
                if ([q.name isEqualToString:@"error"]) errorStr = q.value;
            }
            if (code.length == 0) {
                NSString *desc = errorStr.length > 0
                    ? [@"Patreon: " stringByAppendingString:errorStr]
                    : @"Patreon redirect missing authorization code";
                finish(NO, [NSError errorWithDomain:@"CyanidePatreon" code:-3
                                           userInfo:@{NSLocalizedDescriptionKey: desc}]);
                return;
            }

            printf("[PATREON] authorization code received; exchanging via Worker\n");
            worker_post(@"/patreon/exchange",
                        @{ @"code": code, @"redirect_uri": kRedirectURI },
                        ^(NSDictionary *resp, NSError *werr) {
                if (werr) { finish(NO, werr); return; }
                if (!accept_worker_response(resp)) {
                    finish(NO, [NSError errorWithDomain:@"CyanidePatreon" code:-5
                                               userInfo:@{NSLocalizedDescriptionKey: @"Invalid Worker response"}]);
                    return;
                }
                printf("[PATREON] linked; is_patron=%d\n", (int)cyanide_is_patron());
                finish(YES, nil);
            });
        }];
    session.presentationContextProvider = gPatreonPresenter;
    gPatreonSession = session;

    if (![session start]) {
        gPatreonSession = nil;
        gPatreonPresenter = nil;
        finish(NO, [NSError errorWithDomain:@"CyanidePatreon" code:-6
                                   userInfo:@{NSLocalizedDescriptionKey: @"Could not start authentication session"}]);
    }
}

void cyanide_patreon_sign_out(void)
{
    NSString *tok = keychain_get_string(kKeychainToken);
    if (tok.length > 0) {
        // Fire-and-forget: Worker will delete the KV refresh-token entry.
        worker_post(@"/patreon/signout", @{ @"token": tok }, ^(NSDictionary *r, NSError *e) {
            (void)r; (void)e;
        });
    }
    keychain_set_string(kKeychainToken, nil);

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:kDefaultsLinked];
    [d removeObjectForKey:kDefaultsDisplayName];
    [d removeObjectForKey:kDefaultsTierTitle];
    [d removeObjectForKey:kDefaultsPledgeCents];
    [d removeObjectForKey:kDefaultsLastRefresh];

    post_status_changed();
}

void cyanide_patreon_refresh(void (^completion)(BOOL, NSError *_Nullable))
{
    void (^finish)(BOOL, NSError *) = ^(BOOL ok, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(ok, err);
        });
    };
    NSString *tok = keychain_get_string(kKeychainToken);
    if (tok.length == 0) {
        finish(NO, [NSError errorWithDomain:@"CyanidePatreon" code:-11
                                   userInfo:@{NSLocalizedDescriptionKey: @"Not linked"}]);
        return;
    }
    worker_post(@"/patreon/refresh", @{ @"token": tok }, ^(NSDictionary *resp, NSError *werr) {
        if (werr) { finish(NO, werr); return; }
        if (!accept_worker_response(resp)) {
            finish(NO, [NSError errorWithDomain:@"CyanidePatreon" code:-5
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid Worker response"}]);
            return;
        }
        finish(YES, nil);
    });
}
