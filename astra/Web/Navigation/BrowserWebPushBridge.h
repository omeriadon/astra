#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT WKWebsiteDataStore * _Nullable AstraCreateWebPushDataStore(void);
FOUNDATION_EXPORT BOOL AstraInstallWebPushHost(WKWebsiteDataStore *store, id delegate);
FOUNDATION_EXPORT BOOL AstraConfigureWebPushPreferences(WKPreferences *preferences, BOOL enabled);
FOUNDATION_EXPORT void AstraReadPendingWebPush(WKWebsiteDataStore *store, void (^completion)(NSArray<NSDictionary *> *messages));
FOUNDATION_EXPORT void AstraProcessWebPush(WKWebsiteDataStore *store, NSDictionary *message, void (^completion)(BOOL processed));
FOUNDATION_EXPORT void AstraProcessWebNotificationResponse(WKWebsiteDataStore *store, NSDictionary *notification, BOOL clicked, void (^completion)(BOOL processed));
NS_ASSUME_NONNULL_END
#endif
