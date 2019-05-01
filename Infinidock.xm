/* License {{{ */

/*
 * Copyright (c) 2010-2014, Xuzz Productions, LLC
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* }}} */

/* Configuration and Preferences {{{ */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "iPhonePrivate.h"
#import "Preferences.h"

/* }}} */

/* Configuration Macros {{{ */

#define IFMacroQuote_(x) #x
#define IFMacroQuote(x) IFMacroQuote_(x)

#define IFMacroConcat_(x, y) x ## y
#define IFMacroConcat(x, y) IFMacroConcat_(x, y)

/* Flags {{{ */

// Custom control structure for managing flags safely.
// Usage: IFFlag(IFFlagNamedThis) { /* code with flag enabled */ }
// Do not return out of this structure, or the flag is stuck.
#define IFFlag_(flag, c) \
    if (1) { \
        flag += 1; \
        goto IFMacroConcat(body, c); \
    } else \
        while (1) \
            if (1) { \
                flag -= 1; \
                break; \
            } else \
                IFMacroConcat(body, c):
#define IFFlag(flag) IFFlag_(flag, __COUNTER__)

static NSUInteger IFFlagExpandedFrame = 0;
static NSUInteger IFFlagDefaultDimensions = 0;

/* }}} */

#ifndef IFConfigurationListClassObject
    #define IFConfigurationListClassObject NSClassFromString(@IFMacroQuote(SBDockIconListView))
#endif

__attribute__((unused)) static SBIconController *IFIconControllerSharedInstance() {
    return (SBIconController *) [NSClassFromString(@"SBIconController") sharedInstance];
}

static NSInteger IFFlagDefaultIconsPerPage = 0;
static NSUInteger IFVeryDefaultIconColumns() {
    // Both default for Infinilist and for Infinidock.
    UIInterfaceOrientation orientation = [IFIconControllerSharedInstance() orientation];

    NSUInteger icons = 0;
    IFFlag(IFFlagDefaultDimensions) {
        IFFlag(IFFlagDefaultIconsPerPage) {
            icons = [IFConfigurationListClassObject iconColumnsForInterfaceOrientation:orientation];
        }
    }

    return icons;
}

#define IFConfigurationExpandHorizontally YES
#define IFConfigurationExpandVertically NO
#define IFConfigurationDynamicColumns YES
#define IFConfigurationExpandWhenEditing NO

#define IFPreferencesPagingEnabled @"IFPagingEnabled", NO
#define IFPreferencesScrollEnabled @"IFScrollEnabled", YES
#define IFPreferencesScrollBounce @"IFScrollBounce", kIFScrollBounceEnabled
#define IFPreferencesScrollbarStyle @"IFScrollbarStyle", kIFScrollbarStyleNone

#define IFPreferencesIconsPerPage @"IFIconsPerPage", (IFVeryDefaultIconColumns())
#define IFPreferencesRestorePage @"IFRestoreEnabled", 0
#define IFPreferencesSnapEnabled @"IFSnapEnabled", NO
#define IFPreferencesClipsToBounds @"IFClipsToBounds", NO

#define IFConfigurationScrollViewClass UIScrollView
#define IFConfigurationFullPages NO
#define IFConfigurationExpandedDimension 10000

/* }}} */

/* Conveniences {{{ */

__attribute__((unused)) static NSUInteger IFMinimum(NSUInteger x, NSUInteger y) {
    return (x < y ? x : y);
}

__attribute__((unused)) static NSUInteger IFMaximum(NSUInteger x, NSUInteger y) {
    return (x > y ? x : y);
}

__attribute__((unused)) static SBIconView *IFIconViewForIcon(SBIcon *icon) {
    SBIconController *iconController = IFIconControllerSharedInstance();
    if ([iconController respondsToSelector:@selector(homescreenIconViewMap)]) {
        SBIconViewMap *iconViewMap = [iconController homescreenIconViewMap];
        return [iconViewMap iconViewForIcon:icon];
    } else {
        SBIconViewMap *iconViewMap = [NSClassFromString(@"SBIconViewMap") homescreenMap];
        return [iconViewMap iconViewForIcon:icon];
    }
}

__attribute__((unused)) static BOOL IFIconListIsValid(SBIconListView *listView) {
    return [listView isKindOfClass:IFConfigurationListClassObject];
}

__attribute__((unused)) static BOOL IFIconListIsCompletelyValid(SBIconListView *listView) {
    return [listView isMemberOfClass:IFConfigurationListClassObject];
}

__attribute__((unused)) static NSUInteger IFIconListLastIconIndex(SBIconListView *listView) {
    NSArray *icons = [listView icons];
    SBIcon *lastIcon = NULL;

    for (SBIcon *icon in [icons reverseObjectEnumerator]) {
        if ([icon respondsToSelector:@selector(isPlaceholder)] && ![icon isPlaceholder]) {
            lastIcon = icon;
            break;
        } else if ([icon respondsToSelector:@selector(isNullIcon)] && ![icon isNullIcon]) {
            lastIcon = icon;
            break;
        } else if ([icon respondsToSelector:@selector(isDestinationHole)] && ![icon isDestinationHole]) {
            lastIcon = icon;
            break;
        }
    }

    SBIconListModel *model = [listView model];
    return [model indexForIcon:lastIcon];
}

__attribute__((unused)) static UIInterfaceOrientation IFIconListOrientation(SBIconListView *listView) {
    UIInterfaceOrientation orientation = MSHookIvar<UIInterfaceOrientation>(listView, "_orientation");
    return orientation;
}

__attribute__((unused)) static CGSize IFIconDefaultSize() {
    CGSize size = [NSClassFromString(@"SBIconView") defaultIconSize];
    return size;
}

__attribute__((unused)) static SBRootFolder *IFRootFolderSharedInstance() {
    SBIconController *iconController = IFIconControllerSharedInstance();
    SBRootFolder *rootFolder = MSHookIvar<SBRootFolder *>(iconController, "_rootFolder");
    return rootFolder;
}

__attribute__((unused)) static SBIconListView *IFIconListContainingIcon(SBIcon *icon) {
    SBIconController *iconController = IFIconControllerSharedInstance();
    SBRootFolder *rootFolder = IFRootFolderSharedInstance();

    SBIconListModel *listModel = [rootFolder listContainingIcon:icon];

    if ([listModel isKindOfClass:NSClassFromString(@"SBDockIconListModel")]) {
        if ([iconController respondsToSelector:@selector(dockListView)]) {
            return [iconController dockListView];
        } else {
            return [iconController dock];
        }
    } else {
        NSUInteger index = [rootFolder indexOfList:listModel];
        return [iconController rootIconListAtIndex:index];
    }
}

/* }}} */

/* List Management {{{ */

static NSMutableArray *IFListsListViews = NULL;
static NSMutableArray *IFListsScrollViews = NULL;

__attribute__((constructor)) static void IFListsInitialize() {
    // Non-retaining mutable arrays, since we don't want to own these objects.
    CFArrayCallBacks callbacks = { 0, NULL, NULL, CFCopyDescription, CFEqual };
    IFListsListViews = (NSMutableArray *) CFBridgingRelease(CFArrayCreateMutable(NULL, 0, &callbacks));
    IFListsScrollViews = (NSMutableArray *) CFBridgingRelease(CFArrayCreateMutable(NULL, 0, &callbacks));
}

__attribute__((unused)) static void IFListsIterateViews(void (^block)(SBIconListView *, UIScrollView *)) {
    for (NSUInteger i = 0; i < IFMinimum([IFListsListViews count], [IFListsScrollViews count]); i++) {
        block([IFListsListViews objectAtIndex:i], [IFListsScrollViews objectAtIndex:i]);
    }
}

__attribute__((unused)) static SBIconListView *IFListsListViewForScrollView(UIScrollView *scrollView) {
    NSInteger index = [IFListsScrollViews indexOfObject:scrollView];

    if (index == NSNotFound) {
        return NULL;
    }

    return [IFListsListViews objectAtIndex:index];
}

__attribute__((unused)) static UIScrollView *IFListsScrollViewForListView(SBIconListView *listView) {
    NSInteger index = [IFListsListViews indexOfObject:listView];

    if (index == NSNotFound) {
        return NULL;
    }

    return [IFListsScrollViews objectAtIndex:index];
}

__attribute__((unused)) static void IFListsRegister(SBIconListView *listView, UIScrollView *scrollView) {
    [IFListsListViews addObject:listView];
    [IFListsScrollViews addObject:scrollView];
}

__attribute__((unused)) static void IFListsUnregister(SBIconListView *listView, UIScrollView *scrollView) {
    [IFListsListViews removeObject:listView];
    [IFListsScrollViews removeObject:scrollView];
}

/* }}} */

/* Preferences {{{ */

typedef enum {
    kIFScrollbarStyleBlack,
    kIFScrollbarStyleWhite,
    kIFScrollbarStyleNone
} IFScrollbarStyle;

typedef enum {
    kIFScrollBounceEnabled,
    kIFScrollBounceExtra,
    kIFScrollBounceDisabled
} IFScrollBounce;

#ifndef IFPreferencesPagingEnabled
    #define IFPreferencesPagingEnabled @"PagingEnabled", NO
#endif

#ifndef IFPreferencesScrollEnabled
    #define IFPreferencesScrollEnabled @"ScrollEnabled", YES
#endif

#ifndef IFPreferencesScrollBounce
    #define IFPreferencesScrollBounce @"ScrollBounce", kIFScrollBounceEnabled
#endif

#ifndef IFPreferencesScrollbarStyle
    #define IFPreferencesScrollbarStyle @"ScrollbarStyle", kIFScrollbarStyleBlack
#endif

#ifndef IFPreferencesClipsToBounds
    #define IFPreferencesClipsToBounds @"ClipsToBounds", YES
#endif

static void IFPreferencesApplyToList(SBIconListView *listView) {
    UIScrollView *scrollView = IFListsScrollViewForListView(listView);

    BOOL scroll = IFPreferencesBoolForKey(IFPreferencesScrollEnabled);
    IFScrollBounce bounce = (IFScrollBounce) IFPreferencesIntForKey(IFPreferencesScrollBounce);
    IFScrollbarStyle bar = (IFScrollbarStyle) IFPreferencesIntForKey(IFPreferencesScrollbarStyle);
    BOOL page = IFPreferencesBoolForKey(IFPreferencesPagingEnabled);
    BOOL clips = IFPreferencesBoolForKey(IFPreferencesClipsToBounds);

    [scrollView setShowsVerticalScrollIndicator:YES];
    [scrollView setShowsHorizontalScrollIndicator:YES];
    if (bar == kIFScrollbarStyleBlack) {
        [scrollView setIndicatorStyle:UIScrollViewIndicatorStyleDefault];
    } else if (bar == kIFScrollbarStyleWhite) {
        [scrollView setIndicatorStyle:UIScrollViewIndicatorStyleWhite];
    } else if (bar == kIFScrollbarStyleNone) {
        [scrollView setShowsVerticalScrollIndicator:NO];
        [scrollView setShowsHorizontalScrollIndicator:NO];
    }

    [scrollView setAlwaysBounceVertical:IFConfigurationExpandVertically && (bounce == kIFScrollBounceEnabled)];
    [scrollView setAlwaysBounceHorizontal:IFConfigurationExpandHorizontally && (bounce == kIFScrollBounceEnabled)];
    [scrollView setBounces:(bounce != kIFScrollBounceDisabled)];

    [scrollView setScrollEnabled:scroll];
    [scrollView setPagingEnabled:page];
    [scrollView setClipsToBounds:clips];
    [listView setClipsToBounds:clips];

    if (bounce == kIFScrollBounceExtra) {
        NSUInteger idx = 0;
        NSUInteger max = 0;

        IFFlag(IFFlagDefaultDimensions) {
            idx = IFIconListLastIconIndex(listView);
            max = [listView iconRowsForCurrentOrientation] * [listView iconColumnsForCurrentOrientation];
        }

        [scrollView setAlwaysBounceVertical:IFConfigurationExpandVertically && (idx > max)];
        [scrollView setAlwaysBounceHorizontal:IFConfigurationExpandHorizontally && (idx > max)];
    }
}

static void IFPreferencesApply() {
    IFListsIterateViews(^(SBIconListView *listView, UIScrollView *scrollView) {
        IFPreferencesApplyToList(listView);
    });
}

/* }}} */

/* List Sizing {{{ */

typedef struct {
    NSUInteger rows;
    NSUInteger columns;
} IFIconListDimensions;

static IFIconListDimensions IFIconListDimensionsZero = { 0, 0 };

/* Defaults {{{ */

static IFIconListDimensions _IFSizingDefaultDimensionsForOrientation(UIInterfaceOrientation orientation) {
    IFIconListDimensions dimensions = IFIconListDimensionsZero;

    IFFlag(IFFlagDefaultDimensions) {
        dimensions.rows = [IFConfigurationListClassObject iconRowsForInterfaceOrientation:orientation];
        dimensions.columns = [IFConfigurationListClassObject iconColumnsForInterfaceOrientation:orientation];
    }

    return dimensions;
}

static IFIconListDimensions _IFSizingDefaultDimensions(SBIconListView *listView) {
    return _IFSizingDefaultDimensionsForOrientation(IFIconListOrientation(listView));
}

static CGSize _IFSizingDefaultPadding(SBIconListView *listView) {
    CGSize padding = CGSizeZero;

    IFFlag(IFFlagDefaultDimensions) {
        padding.width = [listView horizontalIconPadding];
        padding.height = [listView verticalIconPadding];
    }

    return padding;
}

static UIEdgeInsets _IFSizingDefaultInsets(SBIconListView *listView) {
    UIEdgeInsets insets = UIEdgeInsetsZero;

    IFFlag(IFFlagDefaultDimensions) {
        insets.top = [listView topIconInset];
        insets.bottom = [listView bottomIconInset];
        insets.left = [listView sideIconInset];
        insets.right = [listView sideIconInset];
    }

    return insets;
}

/* }}} */

/* Dimensions {{{ */

static IFIconListDimensions IFSizingMaximumDimensionsForOrientation(UIInterfaceOrientation orientation) {
    IFIconListDimensions dimensions = _IFSizingDefaultDimensionsForOrientation(orientation);

    if (IFConfigurationExpandVertically) {
        dimensions.rows = IFConfigurationExpandedDimension;
    }

    if (IFConfigurationExpandHorizontally) {
        dimensions.columns = IFConfigurationExpandedDimension;
    }

    return dimensions;
}

static IFIconListDimensions IFSizingContentDimensions(SBIconListView *listView) {
    IFIconListDimensions dimensions = IFIconListDimensionsZero;
    UIInterfaceOrientation orientation = IFIconListOrientation(listView);

    if ([[listView icons] count] > 0) {
        NSUInteger idx = IFIconListLastIconIndex(listView);

        if (IFConfigurationExpandWhenEditing && [IFIconControllerSharedInstance() isEditing]) {
            // Add room to drop the icon into.
            idx += 1;
        }

        IFIconListDimensions maximumDimensions = IFSizingMaximumDimensionsForOrientation(orientation);
        dimensions.columns = (idx % maximumDimensions.columns);
        dimensions.rows = (idx / maximumDimensions.columns);

        // Convert from index to sizing information.
        dimensions.rows += 1;
        dimensions.columns += 1;

        if (!IFConfigurationDynamicColumns) {
            // If we have more than one row, we necessarily have the
            // maximum number of columns at some point above the bottom.
            dimensions.columns = maximumDimensions.columns;
        }
    } else {
        dimensions = _IFSizingDefaultDimensionsForOrientation(orientation);
    }

    IFIconListDimensions defaultDimensions = _IFSizingDefaultDimensions(listView);

    if (IFConfigurationFullPages || IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
        // This is ugly, but we need to round up here.
        dimensions.rows = ceilf((float) dimensions.rows / (float) defaultDimensions.rows) * defaultDimensions.rows;
        dimensions.columns = ceilf((float) dimensions.columns / (float) defaultDimensions.columns) * defaultDimensions.columns;
    }

    // Make sure we have at least the default number of icons.
    dimensions.rows = (dimensions.rows > defaultDimensions.rows) ? dimensions.rows : defaultDimensions.rows;
    dimensions.columns = (dimensions.columns > defaultDimensions.columns) ? dimensions.columns : defaultDimensions.columns;

    return dimensions;
}

/* }}} */

/* Information {{{ */

// Prevent conflicts between multiple users of Infinilist.
#define IFIconListSizingInformation IFMacroConcat(IFIconListSizingInformation, Infinidock)

@interface IFIconListSizingInformation : NSObject {
    IFIconListDimensions defaultDimensions;
    CGSize defaultPadding;
    UIEdgeInsets defaultInsets;
    IFIconListDimensions contentDimensions;
}

@property (nonatomic, assign) IFIconListDimensions defaultDimensions;
@property (nonatomic, assign) CGSize defaultPadding;
@property (nonatomic, assign) UIEdgeInsets defaultInsets;
@property (nonatomic, assign) IFIconListDimensions contentDimensions;

@end

@implementation IFIconListSizingInformation

@synthesize defaultDimensions;
@synthesize defaultPadding;
@synthesize defaultInsets;
@synthesize contentDimensions;

- (NSString *)description {
    return [NSString stringWithFormat:@"<IFIconListSizingInformation:%p defaultDimensions = {%ld, %ld} defaultPadding = %@ defaultInsets = %@ contentDimensions = {%ld, %ld}>", self, (unsigned long)defaultDimensions.rows, (unsigned long)defaultDimensions.columns, NSStringFromCGSize(defaultPadding), NSStringFromUIEdgeInsets(defaultInsets), (unsigned long)contentDimensions.rows, (unsigned long)contentDimensions.columns];
}

@end

static NSMutableDictionary *IFIconListSizingStore = [[NSMutableDictionary alloc] init];

static IFIconListSizingInformation *IFIconListSizingInformationForIconList(SBIconListView *listView) {
    IFIconListSizingInformation *information = [IFIconListSizingStore objectForKey:[NSValue valueWithNonretainedObject:listView]];
    return information;
}

static IFIconListDimensions IFSizingDefaultDimensionsForIconList(SBIconListView *listView) {
    return [IFIconListSizingInformationForIconList(listView) defaultDimensions];
}

static void IFIconListSizingSetInformationForIconList(IFIconListSizingInformation *information, SBIconListView *listView) {
    [IFIconListSizingStore setObject:information forKey:[NSValue valueWithNonretainedObject:listView]];
}

static void IFIconListSizingRemoveInformationForIconList(SBIconListView *listView) {
    [IFIconListSizingStore removeObjectForKey:[NSValue valueWithNonretainedObject:listView]];
}

static IFIconListSizingInformation *IFIconListSizingComputeInformationForIconList(SBIconListView *listView) {
    IFIconListSizingInformation *info = [[IFIconListSizingInformation alloc] init];
    [info setDefaultDimensions:_IFSizingDefaultDimensions(listView)];
    [info setDefaultPadding:_IFSizingDefaultPadding(listView)];
    [info setDefaultInsets:_IFSizingDefaultInsets(listView)];
    [info setContentDimensions:IFSizingContentDimensions(listView)];
    return info;
}

/* }}} */

/* Content Size {{{ */

static CGSize IFIconListSizingEffectiveContentSize(SBIconListView *listView) {
    IFIconListSizingInformation *info = IFIconListSizingInformationForIconList(listView);

    IFIconListDimensions effectiveDimensions = [info contentDimensions];
    CGSize contentSize = CGSizeZero;

    if (IFConfigurationFullPages || IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
        IFIconListDimensions defaultDimensions = [info defaultDimensions];
        CGSize size = [listView frame].size;

        IFIconListDimensions result = IFIconListDimensionsZero;
        result.columns = (effectiveDimensions.columns / defaultDimensions.columns);
        result.rows = (effectiveDimensions.rows / defaultDimensions.rows);

        contentSize = CGSizeMake(size.width * result.columns, size.height * result.rows);
    } else {
        CGSize padding = [info defaultPadding];
        UIEdgeInsets insets = [info defaultInsets];
        CGSize iconSize = IFIconDefaultSize();

        contentSize.width = insets.left + effectiveDimensions.columns * (iconSize.width + padding.width) - padding.width + insets.right;
        contentSize.height = insets.top + effectiveDimensions.rows * (iconSize.height + padding.height) - padding.height + insets.bottom;
    }

    return contentSize;
}

static void IFIconListSizingUpdateContentSize(SBIconListView *listView, UIScrollView *scrollView) {
    CGPoint offset = [scrollView contentOffset];
    CGSize scrollSize = [scrollView bounds].size;
    CGSize oldSize = [scrollView contentSize];
    CGSize newSize = IFIconListSizingEffectiveContentSize(listView);


    if (IFConfigurationExpandHorizontally) {
        // Be sure not to have two-dimensional scrolling.
        if (newSize.height > scrollSize.height) {
            newSize.height = scrollSize.height;
        }

        // Make sure the content offset is never outside the scroll view.
        if (offset.x + scrollSize.width > newSize.width) {
            // But not if the scroll view is only a few columns.
            if (newSize.width >= scrollSize.width) {
                offset.x = newSize.width - scrollSize.width;
            }
        }
    } else if (IFConfigurationExpandVertically) {
        // Be sure not to have two-dimensional scrolling.
        if (newSize.width > scrollSize.width) {
            newSize.width = scrollSize.width;
        }

        // Make sure the content offset is never outside the scroll view.
        if (offset.y + scrollSize.height > newSize.height) {
            // But not if the scroll view is only a few rows.
            if (newSize.height >= scrollSize.height) {
                offset.y = newSize.height - scrollSize.height;
            }
        }
    }

    if (!CGSizeEqualToSize(oldSize, newSize)) {
        [UIView animateWithDuration:0.3f animations:^{
            [scrollView setContentSize:newSize];
            [scrollView setContentOffset:offset animated:NO];
        }];
    }
}

/* }}} */

static void IFIconListSizingUpdateIconList(SBIconListView *listView) {
    UIScrollView *scrollView = IFListsScrollViewForListView(listView);

    IFIconListSizingSetInformationForIconList(IFIconListSizingComputeInformationForIconList(listView), listView);
    IFIconListSizingUpdateContentSize(listView, scrollView);
}

/* }}} */

%group IFBasic

%hook SBDockIconListView

/* View Hierarchy {{{ */

static void IFIconListInitialize(SBIconListView *listView) {
    NSLog(@"Infinidock: IFIconListInitialize");
    UIScrollView *scrollView = [[IFConfigurationScrollViewClass alloc] initWithFrame:[listView frame]];
    [scrollView setDelegate:(id<UIScrollViewDelegate>) listView];
    [scrollView setDelaysContentTouches:NO];

    IFListsRegister(listView, scrollView);
    [listView addSubview:scrollView];

    IFIconListSizingUpdateIconList(listView);
    IFPreferencesApplyToList(listView);
}

- (id)initWithModel:(id)arg1 orientation:(long long)arg2 viewMap:(id)arg3 {
    if ((self = %orig)) {
        // Avoid hooking a sub-initializer when we hook the base initializer, but otherwise do hook it.
        if (IFIconListIsValid(self)) {
            IFIconListInitialize(self);
        }
    }

    return self;
}

- (void)dealloc {
    if (IFIconListIsValid(self)) {
        UIScrollView *scrollView = IFListsScrollViewForListView(self);

        IFListsUnregister(self, scrollView);
        IFIconListSizingRemoveInformationForIconList(self);
    }

    %orig;
}

- (void)setFrame:(CGRect)frame {
    if (IFIconListIsValid(self)) {
        UIScrollView *scrollView = IFListsScrollViewForListView(self);

        NSUInteger pagex = 0;
        NSUInteger pagey = 0;

        if (IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
            CGPoint offset = [scrollView contentOffset];
            CGRect bounds = [self bounds];

            pagex = (offset.x / bounds.size.width);
            pagey = (offset.y / bounds.size.height);
        }

        %orig;

        [scrollView setFrame:[self bounds]];
        IFIconListSizingUpdateIconList(self);

        [self layoutIconsNow];

        if (IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
            CGPoint offset = [scrollView contentOffset];
            CGRect bounds = [self bounds];

            offset.x = (pagex * bounds.size.width);
            offset.y = (pagey * bounds.size.height);
            [scrollView setContentOffset:offset animated:NO];
        }
    } else {
        %orig;
    }
}

- (void)addSubview:(UIView *)view {
    if (IFIconListIsValid(self)) {
        UIScrollView *scrollView = IFListsScrollViewForListView(self);

        if (view == scrollView) {
            %orig;
        } else {
            [scrollView addSubview:view];

            IFIconListSizingUpdateIconList(self);
        }
    } else {
        %orig;
    }
}

- (void)setOrientation:(UIInterfaceOrientation)orientation {
    %orig;

    if (IFIconListIsValid(self)) {
        IFIconListSizingUpdateIconList(self);
    }
}

- (void)cleanupAfterRotation {
    %orig;

    if (IFIconListIsValid(self)) {
        [self layoutIconsNow];
    }
}

/* }}} */

/* Icon Layout {{{ */
/* Dimensions {{{ */

+ (NSUInteger)maxIcons {
    if (self == IFConfigurationListClassObject) {
        if (IFFlagDefaultDimensions) {
            return %orig;
        } else {
            return IFConfigurationExpandedDimension * IFConfigurationExpandedDimension;
        }
    } else {
        return %orig;
    }
}

+ (NSUInteger)maxVisibleIconRowsInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (self == IFConfigurationListClassObject) {
        NSUInteger rows = 0;

        IFFlag(IFFlagDefaultDimensions) {
            rows = %orig;
        }

        return rows;
    } else {
        return %orig;
    }
}

+ (NSUInteger)iconRowsForInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (self == IFConfigurationListClassObject) {
        if (IFFlagDefaultDimensions) {
            return %orig;
        } else {
            IFIconListDimensions dimensions = IFSizingMaximumDimensionsForOrientation(interfaceOrientation);
            return dimensions.rows;
        }
    } else {
        return %orig;
    }
}

+ (NSUInteger)iconColumnsForInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (self == IFConfigurationListClassObject) {
        if (IFFlagDefaultDimensions) {
            return %orig;
        } else {
            IFIconListDimensions dimensions = IFSizingMaximumDimensionsForOrientation(interfaceOrientation);
            return dimensions.columns;
        }
    } else {
        return %orig;
    }
}

- (NSUInteger)iconRowsForCurrentOrientation {
    if (IFIconListIsValid(self)) {
        if (IFFlagExpandedFrame) {
            IFIconListDimensions dimensions = [IFIconListSizingInformationForIconList(self) contentDimensions];
            return dimensions.rows;
        } else {
            return %orig;
        }
    } else {
        return %orig;
    }
}

- (NSUInteger)iconColumnsForCurrentOrientation {
    if (IFIconListIsValid(self)) {
        if (IFFlagExpandedFrame) {
            IFIconListDimensions dimensions = [IFIconListSizingInformationForIconList(self) contentDimensions];
            return dimensions.columns;
        } else {
            return %orig;
        }
    } else {
        return %orig;
    }
}

- (CGRect)bounds {
    if (IFIconListIsValid(self)) {
        // This check breaks icon positions on iOS 7.0+, but is needed on iOS 5.x and 6.x.
        if (kCFCoreFoundationVersionNumber < 800.0 && IFFlagExpandedFrame) {
            CGRect bounds = %orig;
            bounds.size = IFIconListSizingEffectiveContentSize(self);
            return bounds;
        } else {
            return %orig;
        }
    } else {
        return %orig;
    }
}

/* }}} */

/* Positioning {{{ */

static CGPoint IFIconListOriginForIconAtXY(SBIconListView *self, NSUInteger x, NSUInteger y, CGPoint (^orig)(NSUInteger, NSUInteger)) {
    CGPoint origin = CGPointZero;

    IFFlag(IFFlagExpandedFrame) {
        UIScrollView *scrollView = IFListsScrollViewForListView(self);

        if (IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
            IFIconListDimensions dimensions = IFSizingDefaultDimensionsForIconList(self);

            NSUInteger px = (x / dimensions.columns), py = (y / dimensions.rows);
            NSUInteger ix = (x % dimensions.columns), iy = (y % dimensions.rows);

            origin = orig(ix, iy);

            CGSize size = [scrollView frame].size;
            origin.x += (size.width) * px;
            origin.y += (size.height) * py;
        } else {
            origin = orig(x, y);
        }
    }

    return origin;
}

- (CGPoint)originForIconAtCoordinate:(SBIconCoordinate)coordinate {
    if (IFIconListIsValid(self)) {
        return IFIconListOriginForIconAtXY(self, coordinate.col - 1, coordinate.row - 1, ^(NSUInteger x, NSUInteger y) {
            SBIconCoordinate innerCoordinate = { .row = y + 1, .col = x + 1 };
            return %orig(innerCoordinate);
        });
    } else {
        return %orig;
    }
}

- (CGPoint)originForIconAtX:(NSUInteger)x Y:(NSUInteger)y {
    if (IFIconListIsValid(self)) {
        return IFIconListOriginForIconAtXY(self, x, y, ^(NSUInteger x, NSUInteger y) {
            return %orig(x, y);
        });
    } else {
        return %orig;
    }
}

- (NSUInteger)rowAtPoint:(CGPoint)point {
    if (IFIconListIsValid(self)) {
        NSUInteger row = 0;

        IFFlag(IFFlagExpandedFrame) {
            UIScrollView *scrollView = IFListsScrollViewForListView(self);
            CGPoint offset = [scrollView contentOffset];
            CGSize size = [scrollView frame].size;

            if (IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
                row = %orig;

                NSUInteger page = (offset.y / size.height);
                IFIconListDimensions dimensions = IFSizingDefaultDimensionsForIconList(self);
                row += page * dimensions.rows;
            } else {
                point.x += offset.x;
                point.y += offset.y;

                row = %orig;
            }
        }

        return row;
    } else {
        return %orig;
    }
}

- (NSUInteger)columnAtPoint:(CGPoint)point {
    if (IFIconListIsValid(self)) {
        NSUInteger column = 0;

        IFFlag(IFFlagExpandedFrame) {
            UIScrollView *scrollView = IFListsScrollViewForListView(self);
            CGPoint offset = [scrollView contentOffset];
            CGSize size = [scrollView frame].size;

            if (IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
                column = %orig;

                NSUInteger page = (offset.x / size.width);
                IFIconListDimensions dimensions = IFSizingDefaultDimensionsForIconList(self);
                column += page * dimensions.columns;
            } else {
                point.x += offset.x;
                point.y += offset.y;

                column = %orig;
            }
        }

        return column;
    } else {
        return %orig;
    }
}

/* }}} */
/* }}} */

%end

/* Fixes {{{ */

%hook UIScrollView

// FIXME: this is an ugly hack
static id grabbedIcon = NULL;
- (void)setContentOffset:(CGPoint)offset {
    if (grabbedIcon != NULL && [IFListsScrollViews containsObject:self]) {
        // Prevent weird auto-scrolling behavior while dragging icons.
        return;
    } else {
        %orig;
    }
}

%end

%hook SBIconController

// TODO: this method does not exist
- (CGRect)_contentViewRelativeFrameForIcon:(SBIcon *)icon {
    SBIconListView *listView = IFIconListContainingIcon(icon);
    UIScrollView *scrollView = IFListsScrollViewForListView(listView);

    CGRect ret = %orig;

    // The list could, in theory, be in another list that
    // we don't care about. If it is, we won't have a scroll
    // view for it, and can safely ignore moving the icon.
    if (scrollView != NULL) {
        ret.origin.x -= [scrollView contentOffset].x;
        ret.origin.y -= [scrollView contentOffset].y;
    }

    return ret;
}

// TODO: this method does not exist
- (void)moveIconFromWindow:(SBIcon *)icon toIconList:(SBIconListView *)listView {
    %orig;

    if (IFIconListIsValid(listView)) {
        UIScrollView *scrollView = IFListsScrollViewForListView(listView);
        SBIconView *iconView = IFIconViewForIcon(icon);

        CGRect frame = [iconView frame];
        frame.origin.x += [scrollView contentOffset].x;
        frame.origin.y += [scrollView contentOffset].y;
        [iconView setFrame:frame];
    }
}

- (void)_moveIconViewToContentView:(SBIconView *)iconView {
    %orig;

    SBIconListView *listView = [self dockListView];
    if (IFIconListIsValid(listView)) {
        UIScrollView *scrollView = IFListsScrollViewForListView(listView);

        CGRect frame = [iconView frame];
        frame.origin.x += [scrollView contentOffset].x;
        frame.origin.y += [scrollView contentOffset].y;
        [iconView setFrame:frame];
    }
}

// TODO: this method does not exist
- (void)_dropIconIntoOpenFolder:(SBIcon *)icon withInsertionPath:(NSIndexPath *)path {
    %orig;

    SBFolderIconListView *listView = [self currentFolderIconList];

    if (IFIconListIsValid(listView)) {
        UIScrollView *scrollView = IFListsScrollViewForListView(listView);
        SBIconView *iconView = IFIconViewForIcon(icon);

        CGRect frame = [iconView frame];
        frame.origin.x -= [scrollView contentOffset].x;
        frame.origin.y -= [scrollView contentOffset].y;
        [iconView setFrame:frame];
    }
}

// TODO: this method does not exist
- (void)setGrabbedIcon:(id)icon {
    IFListsIterateViews(^(SBIconListView *listView, UIScrollView *scrollView) {
        [scrollView setScrollEnabled:(icon == NULL)];
    });

    %orig;

    if (icon != NULL) {
        grabbedIcon = icon;
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            grabbedIcon = NULL;
        });
    }
}

- (void)setIsEditing:(BOOL)editing {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        IFListsIterateViews(^(SBIconListView *listView, UIScrollView *scrollView) {
            IFIconListSizingUpdateIconList(listView);
        });
    });
}

%end

/* }}} */

%end


/* }}} */

%group IFInfinidock

/* Layout {{{ */

%hook SBDockIconListView

typedef enum {
    kIFIconLayoutMethodDefault, // Handles up to default number of icons, positions as if built-in.
    kIFIconLayoutMethodGrow, // Handles any number of icons, positions as if built-in but grows from the left.
    kIFIconLayoutMethodEven // Handles any number of icons, positions with equal spacing.
} IFIconLayoutMethod;

static IFIconLayoutMethod IFIconListCurrentLayoutMethod(SBIconListView *listView) {
    if (IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
        // We never simulate more than the default count of icons
        // when paging, so this layout method always works.
        return kIFIconLayoutMethodDefault;
    } else {
        NSInteger icons = [[listView icons] count];
        NSInteger selectedIcons = [IFIconListSizingInformationForIconList(listView) defaultDimensions].columns;

        if (icons < selectedIcons) {
            // When we have less than the selected number of icons,
            // we need to center them as with the built-in spacing.
            return kIFIconLayoutMethodDefault;
        } else {
            if (kCFCoreFoundationVersionNumber < 800.0f) {
                if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone && selectedIcons == IFVeryDefaultIconColumns()) {
                    // On the iPhone, special case 4 icons to use an grow method
                    // as it looks much more natural and the spacing works out.
                    return kIFIconLayoutMethodGrow;
                }
            }

            // Growing creates oversized/undersized margins with
            // non-standard icon icon counts, and can cause a set
            // of icons to not fall on exactly one page of screen.
            // So instead use the even layout method, which does.
            return kIFIconLayoutMethodEven;
        }
    }
}

+ (NSUInteger)iconColumnsForInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (self == IFConfigurationListClassObject && !IFFlagDefaultIconsPerPage) {
        NSUInteger icons = IFPreferencesIntForKey(IFPreferencesIconsPerPage);
        return icons;
    } else {
        return %orig;
    }
}

static NSInteger IFFlagDisableVisibleIcons = 0;

static NSUInteger IFDockIconListVisibleIconsCount(SBDockIconListView *self, NSUInteger orig) {
    if (IFIconListIsValid(self) && !IFFlagDisableVisibleIcons) {
        if (IFIconListCurrentLayoutMethod(self) == kIFIconLayoutMethodDefault) {
            NSInteger icons = orig;
            NSInteger defaultIcons = [IFIconListSizingInformationForIconList(self) defaultDimensions].columns;

            return IFMinimum(icons, defaultIcons);
        } else {
            return orig;
        }
    } else {
        return orig;
    }
}

- (NSArray *)visibleIcons {
    NSArray *visibleIcons = %orig;

    if (![self respondsToSelector:@selector(visibleIconsInDock)]) {
        NSUInteger count = IFDockIconListVisibleIconsCount(self, [visibleIcons count]);
        return [visibleIcons subarrayWithRange:NSMakeRange(0, count)];
    } else {
        return visibleIcons;
    }
}

// TODO: this method does not exist
- (NSUInteger)visibleIconsInDock {
    return IFDockIconListVisibleIconsCount(self, %orig);
}

// On iOS 7, the background of folder icons is derived from their position over the wallpaper.
// That works fine for icons on the first page, but after that, they're not on the wallpaper,
// so the icons turn black. To prevent that, we always return the center from the first icons.
- (CGPoint)_wallpaperRelativeIconCenterForIconView:(SBIconView *)iconView {
    SBIcon *icon = [iconView icon];
    NSInteger index = [[self icons] indexOfObject:icon];

    NSInteger columns = [IFIconListSizingInformationForIconList(self) defaultDimensions].columns;
    index = (index % columns);

    icon = [[self icons] objectAtIndex:index];
    iconView = IFIconViewForIcon(icon);

    return %orig(iconView);
}

- (NSUInteger)iconsInRowForSpacingCalculation {
    if (IFIconListIsValid(self)) {
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone || kCFCoreFoundationVersionNumber >= 800.0f) {
            if (IFIconListCurrentLayoutMethod(self) == kIFIconLayoutMethodDefault) {
                NSInteger defaultIcons = [IFIconListSizingInformationForIconList(self) defaultDimensions].columns;

                return IFMaximum(defaultIcons, IFVeryDefaultIconColumns());
            } else {
                return %orig;
            }
        } else {
            return %orig;
        }
    } else {
        return %orig;
    }
}

- (CGFloat)horizontalIconPadding {
    if (IFIconListIsValid(self)) {
        if (IFIconListCurrentLayoutMethod(self) == kIFIconLayoutMethodDefault) {
            // This is unfortunate, but currently required. Otherwise, the original
            // implementation will use the expanded frame, and will return an
            // incorrect value and icons will appear positioned very strangely.
            IFFlagExpandedFrame -= 1;
            CGFloat additional = %orig;
            IFFlagExpandedFrame += 1;
            return additional;
        } else if (IFIconListCurrentLayoutMethod(self) == kIFIconLayoutMethodEven) {
            // This is valid because with even spacing, all icons are the same
            // distance apart, and so the side edge distance is also the spacing.

            // This is required because the default spacing algorithm will not
            // work for one icon per page, as there will be no need for a distance
            // beteween icons. But, there is an equivalent side inset, so use that.
            return [self sideIconInset];
        } else {
            return %orig;
        }
    } else {
        return %orig;
    }
}

- (CGFloat)sideIconInset {
    if (IFIconListIsValid(self)) {
        if (IFIconListCurrentLayoutMethod(self) == kIFIconLayoutMethodEven) {
            NSInteger defaultIcons = [IFIconListSizingInformationForIconList(self) defaultDimensions].columns;

            CGFloat iconWidth = IFIconDefaultSize().width;
            CGFloat width = [IFListsScrollViewForListView(self) bounds].size.width;

            CGFloat blankWidth = width - (iconWidth * defaultIcons);
            CGFloat singleBlank = blankWidth / (defaultIcons + 1);
            return singleBlank;
        } else if (IFIconListCurrentLayoutMethod(self) == kIFIconLayoutMethodDefault) {
            NSInteger defaultIcons = [IFIconListSizingInformationForIconList(self) defaultDimensions].columns;
            NSInteger veryDefaultIcons = IFVeryDefaultIconColumns();

            if (defaultIcons > veryDefaultIcons) {
                // With high icon counts, margins can feel
                // too big, so shrink them a little bit.
                return %orig * 0.5f;
            } else {
                return %orig;
            }
        } else {
            return %orig;
        }
    } else {
        return %orig;
    }
}

- (CGFloat)_additionalHorizontalInsetToCenterIcons {
    if (IFIconListIsValid(self)) {
        if (IFIconListCurrentLayoutMethod(self) == kIFIconLayoutMethodDefault) {
            return %orig;
        } else {
            // Other methods don't want a side inset.
            return 0.0;
        }
    } else {
        return %orig;
    }
}

%end

/* }}} */

/* Snap {{{ */

%hook SBDockIconListView

%new(v@:@{CGPoint=ff}^{CGPoint=ff})
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(CGPoint *)targetContentOffset {
    if (IFPreferencesBoolForKey(IFPreferencesSnapEnabled) && !IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
        SBIconListView *listView = IFListsListViewForScrollView(scrollView);

        CGPoint contentOffset = [scrollView contentOffset];
        CGSize contentSize = [scrollView contentSize];
        CGSize boundsSize = [scrollView bounds].size;

        CGFloat iconInset = [listView sideIconInset];

        CGPoint screenOffset = *targetContentOffset;
        screenOffset.x += iconInset;
        screenOffset.x -= contentOffset.x;
        screenOffset.y -= contentOffset.y;
        NSUInteger column = [listView columnAtPoint:screenOffset];

        CGPoint origin = [listView originForIconAtIndex:column];
        CGPoint nextOrigin = [listView originForIconAtIndex:column + 1];
        CGPoint offset = CGPointZero;

        // Find the icon offset to move to.
        if (fabs(targetContentOffset->x - origin.x) < fabs(targetContentOffset->x - nextOrigin.x)) {
            offset.x = origin.x;
        } else {
            offset.x = nextOrigin.x;
        }

        offset.x -= iconInset;

        if (offset.x <= 0) {
            offset.x = 0;
        } else if (offset.x + boundsSize.width >= contentSize.width) {
            offset.x = contentSize.width - boundsSize.width;
        }

        // Avoid changing the content offset if possible, as it prevents bouncing.
        if (fabs(offset.x - targetContentOffset->x) > 1.0) {
            // Work around UIScrollView bug where you cannot return values at the edges.
            if (offset.x <= 0) {
                offset.x = 0.1;
            } else if (offset.x + boundsSize.width >= contentSize.width) {
                offset.x = contentSize.width - boundsSize.width - 0.1;
            }

            *targetContentOffset = offset;
        }
    }
}

%end

/* }}} */

/* Fixes {{{ */

%hook SBIconListView

// This method checks -visibleIcons and won't affect any past the end. (On iOS 7+, we hook that instead of -visibleIconsInDock.)
- (void)updateEditingStateAnimated:(BOOL)animated {
    IFFlag(IFFlagDisableVisibleIcons) {
        %orig;
    }
}

%end

%hook SBIconZoomAnimator

- (void)prepare {
    IFFlag(IFFlagDisableVisibleIcons) {
        %orig;
    }
}

%end

%hook SBIconController

// This method checks -visibleIconsInDock and won't add any past the end. As we hook that for spacing reasons,
// this hook is necessary to disable that hook and allow moving icons past the first page when using the paging method.
- (id)insertIcon:(SBIcon *)icon intoListView:(SBIconListView *)view iconIndex:(NSUInteger)index options:(unsigned long long)options {
    if (IFIconListIsValid(view)) {
        IFFlag(IFFlagDisableVisibleIcons) {
            return %orig;
        }
    } else {
        return %orig;
    }

    return nil;
}

%end

/* }}} */

/* Restore {{{ */

%hook SBUIController

static void IFRestoreIconLists(void) {
    IFPreferencesApply();

    IFListsIterateViews(^(SBIconListView *listView, UIScrollView *scrollView) {
        NSUInteger page = IFPreferencesIntForKey(IFPreferencesRestorePage);

        if (page != 0) {
            // The actual page to restore to.
            page = (page - 1);

            CGSize size = [scrollView bounds].size;
            CGPoint offset = [scrollView contentOffset];
            CGSize content = [scrollView contentSize];

            if (IFPreferencesBoolForKey(IFPreferencesPagingEnabled)) {
                offset.x = (size.width * page);
            } else {
                NSUInteger iconsPerPage = IFPreferencesIntForKey(IFPreferencesIconsPerPage);
                NSUInteger index = (page * iconsPerPage);

                CGPoint origin = [listView originForIconAtIndex:index];
                CGFloat side = [listView sideIconInset];

                offset = CGPointMake(origin.x - side, 0);
            }

            // Constrain to the scroll view's size.
            if (offset.x + size.width > content.width) {
                offset.x = content.width - size.width;
            }

            [scrollView setContentOffset:offset animated:NO];
        }
    });
}

- (void)restoreIconList:(BOOL)animated {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreIconListAnimated:(BOOL)animated {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreIconListAnimated:(BOOL)animated animateWallpaper:(BOOL)animateWallpaper {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreIconListAnimated:(BOOL)animated animateWallpaper:(BOOL)wallpaper keepSwitcher:(BOOL)switcher {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreIconListAnimated:(BOOL)animated delay:(NSTimeInterval)delay {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreIconListAnimated:(BOOL)animated delay:(NSTimeInterval)delay animateWallpaper:(BOOL)wallpaper keepSwitcher:(BOOL)switcher {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreIconListAnimatedIfNeeded:(BOOL)needed animateWallpaper:(BOOL)wallpaper {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreContent {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreContentAndUnscatterIconsAnimated:(BOOL)animated {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreContentAndUnscatterIconsAnimated:(BOOL)animated withCompletion:(id)completion {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreContentUpdatingStatusBar:(BOOL)updateStatusBar {
    %orig;
    IFRestoreIconLists();
}

- (void)restoreIconListForSuspendGesture {
    %orig;
    IFRestoreIconLists();
}

%end

/* }}} */

%end

/* Constructor {{{ */

%ctor {
    IFPreferencesInitialize(@"com.subdiox.infinidock", IFPreferencesApply);

    dlopen("/Library/MobileSubstrate/DynamicLibraries/IconSupport.dylib", RTLD_LAZY);
    [[objc_getClass("ISIconSupport") sharedInstance] addExtension:@"infinidock"];

    %init(IFInfinidock);
    %init(IFBasic);
}

/* }}} */

