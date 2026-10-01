#import "BrowserWebPushBridge.h"
#if TARGET_OS_OSX
#import <Security/Security.h>
#import <dlfcn.h>

static BOOL AstraHasWebPushEntitlement(void) {
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *);
    CreateTask create = (CreateTask)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CopyEntitlement copy = (CopyEntitlement)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!create || !copy) {
        return NO;
    }
    CFTypeRef task = create(kCFAllocatorDefault);
    if (!task) {
        return NO;
    }
    CFTypeRef value = copy(task, CFSTR("com.apple.private.webkit.webpush"), NULL);
    BOOL allowed = value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
    if (value) {
        CFRelease(value);
    }
    CFRelease(task);
    return allowed;
}

// These selectors match WebKit's Cocoa SPI. Every entry point checks availability.
// Sources: WKWebsiteDataStorePrivate.h, WKPreferencesPrivate.h, and MiniBrowser/mac.
@interface WKWebsiteDataStore (AstraWebPushPrivate)
- (NSObject *)_configuration;
- (instancetype)_initWithConfiguration:(NSObject *)configuration;
- (void)set_delegate:(id)delegate;
- (void)_getPendingPushMessages:(void (^)(NSArray<NSDictionary *> *))completion;
- (void)_processPushMessage:(NSDictionary *)message completionHandler:(void (^)(bool))completion;
- (void)_processPersistentNotificationClick:(NSDictionary *)notification completionHandler:(void (^)(bool))completion;
- (void)_processPersistentNotificationClose:(NSDictionary *)notification completionHandler:(void (^)(bool))completion;
- (void)_setServiceWorkerOverridePreferences:(WKPreferences *)preferences;
@end

@interface WKPreferences (AstraWebPushPrivate)
- (void)_setPushAPIEnabled:(BOOL)enabled;
- (void)_setNotificationsEnabled:(BOOL)enabled;
- (void)_setNotificationEventEnabled:(BOOL)enabled;
@end

WKWebsiteDataStore *AstraCreateWebPushDataStore(void) {
    if (!AstraHasWebPushEntitlement()) {
        return nil;
    }
    WKWebsiteDataStore *original = WKWebsiteDataStore.defaultDataStore;
    if (![original respondsToSelector:@selector(_configuration)] ||
        ![WKWebsiteDataStore instancesRespondToSelector:@selector(_initWithConfiguration:)]) {
        return nil;
    }
    NSObject *configuration = original._configuration;
    if (![configuration respondsToSelector:NSSelectorFromString(@"setWebPushMachServiceName:")]) {
        return nil;
    }
    // Copy the default store's paths so existing cookies and workers remain in place.
    [configuration setValue:@"com.apple.webkit.webpushd.service" forKey:@"webPushMachServiceName"];
    if ([configuration respondsToSelector:NSSelectorFromString(@"setIsDeclarativeWebPushEnabled:")]) {
        [configuration setValue:@NO forKey:@"isDeclarativeWebPushEnabled"];
    }
    return [[WKWebsiteDataStore alloc] _initWithConfiguration:configuration];
}

BOOL AstraConfigureWebPushPreferences(WKPreferences *preferences, BOOL enabled) {
    if (![preferences respondsToSelector:@selector(_setPushAPIEnabled:)] ||
        ![preferences respondsToSelector:@selector(_setNotificationsEnabled:)] ||
        ![preferences respondsToSelector:@selector(_setNotificationEventEnabled:)]) {
        return NO;
    }
    [preferences _setPushAPIEnabled:enabled];
    [preferences _setNotificationsEnabled:enabled];
    [preferences _setNotificationEventEnabled:enabled];
    return YES;
}

BOOL AstraInstallWebPushHost(WKWebsiteDataStore *store, id delegate) {
    if (!AstraHasWebPushEntitlement() || !store.isPersistent || ![store respondsToSelector:@selector(set_delegate:)] ||
        ![store respondsToSelector:@selector(_getPendingPushMessages:)] ||
        ![store respondsToSelector:@selector(_processPushMessage:completionHandler:)] ||
        ![store respondsToSelector:@selector(_processPersistentNotificationClick:completionHandler:)] ||
        ![store respondsToSelector:@selector(_processPersistentNotificationClose:completionHandler:)] ||
        ![store respondsToSelector:@selector(_setServiceWorkerOverridePreferences:)]) {
        return NO;
    }
    WKPreferences *preferences = [[WKPreferences alloc] init];
    if (!AstraConfigureWebPushPreferences(preferences, YES)) {
        return NO;
    }
    [store set_delegate:delegate];
    [store _setServiceWorkerOverridePreferences:preferences];
    return YES;
}

void AstraReadPendingWebPush(WKWebsiteDataStore *store, void (^completion)(NSArray<NSDictionary *> *)) {
    if (![store respondsToSelector:@selector(_getPendingPushMessages:)]) {
        completion(@[]);
        return;
    }
    [store _getPendingPushMessages:completion];
}

void AstraProcessWebPush(WKWebsiteDataStore *store, NSDictionary *message, void (^completion)(BOOL)) {
    if (![store respondsToSelector:@selector(_processPushMessage:completionHandler:)]) {
        completion(NO);
        return;
    }
    [store _processPushMessage:message completionHandler:^(bool processed) {
        completion(processed);
    }];
}

void AstraProcessWebNotificationResponse(WKWebsiteDataStore *store, NSDictionary *notification, BOOL clicked, void (^completion)(BOOL)) {
    SEL selector = clicked ? @selector(_processPersistentNotificationClick:completionHandler:)
                           : @selector(_processPersistentNotificationClose:completionHandler:);
    if (![store respondsToSelector:selector]) {
        completion(NO);
        return;
    }
    void (^handler)(bool) = ^(bool processed) {
        completion(processed);
    };
    if (clicked) {
        [store _processPersistentNotificationClick:notification completionHandler:handler];
    } else {
        [store _processPersistentNotificationClose:notification completionHandler:handler];
    }
}
#endif
