// FloatingWidgetBootstrap.m
//
// The +load method is called by dyld when this image is first loaded, before
// main() and before any Swift code runs. It registers for UIApplicationDidFinish-
// LaunchingNotification so the widget is set up once the app is fully running.
//
// Uses ObjC runtime (NSClassFromString / NSSelectorFromString / objc_msgSend)
// to call the @objc Swift class — no generated header import needed, which
// avoids the PRODUCT_MODULE_NAME ambiguity after app renaming.

#import <UIKit/UIKit.h>
#import <objc/message.h>

@interface FloatingWidgetBootstrap : NSObject
@end

@implementation FloatingWidgetBootstrap

+ (void)load {
    [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                   object:nil
                    queue:NSOperationQueue.mainQueue
               usingBlock:^(NSNotification * _Nonnull note) {
        // At this point every UIWindow/UIWindowScene is live.
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (!scene) return;

        // Resolve @objc(FloatingWidgetManager) at runtime — no header needed.
        // The explicit @objc(...) annotation in Swift guarantees this name.
        Class cls = NSClassFromString(@"FloatingWidgetManager");
        id mgr = ((id (*)(id, SEL))objc_msgSend)(
            (id)cls, NSSelectorFromString(@"shared")
        );
        if (mgr) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                mgr, NSSelectorFromString(@"bootWithScene:"), scene
            );
        }
    }];
}

@end
