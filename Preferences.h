#import "iPhonePrivate.h"

/* Preferences {{{ */
static NSDictionary *preferences = NULL;
static NSString *identifier = NULL;
static void (*callback)() = NULL;

__attribute__((unused)) static void IFPreferencesLoad() {
    preferences = [[NSDictionary alloc] initWithContentsOfFile:[NSString stringWithFormat:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/%@.plist"], identifier]];
}

__attribute__((unused)) static BOOL IFPreferencesBoolForKey(NSString *key, BOOL def) {
    id obj = [preferences objectForKey:key];

    if (obj != NULL) return [obj boolValue];
    else return def;
}

__attribute__((unused)) static int IFPreferencesIntForKey(NSString *key, int def) {
    id obj = [preferences objectForKey:key];

    if (obj != NULL) return [obj intValue];
    else return def;
}

__attribute__((unused)) static id IFPreferencesObjectForKey(NSString *key, id def) {
    return [preferences objectForKey:key] ?: def;
}

__attribute__((unused)) static SBIconModel *IFPreferencesSharedIconModel() {
    Class modelClass = NSClassFromString(@"SBIconModel");

    if ([modelClass respondsToSelector:@selector(sharedInstance)]) {
        return [modelClass sharedInstance];
    } else {
        Class controllerClass = NSClassFromString(@"SBIconController");
        SBIconController *controller = [controllerClass sharedInstance];

        return [controller model];
    }
}

__attribute__((unused)) static void IFPreferencesIconModelLayout(SBIconModel *model) {
    if ([model respondsToSelector:@selector(relayout)]) {
        [model relayout];
    } else {
        [model layout];
    }
}

__attribute__((unused)) static void IFPreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    IFPreferencesLoad();

    if (callback != NULL) {
        callback();
    }

    IFPreferencesIconModelLayout(IFPreferencesSharedIconModel());
}

__attribute__((unused)) static void IFPreferencesInitialize(NSString *bundleIdentifier, void (*cb)()) {
    identifier = [bundleIdentifier copy];
    callback = cb;

    IFPreferencesLoad();

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, IFPreferencesChangedCallback, (CFStringRef) [NSString stringWithFormat:@"%@.preferences-changed", bundleIdentifier], NULL, CFNotificationSuspensionBehaviorCoalesce);
}