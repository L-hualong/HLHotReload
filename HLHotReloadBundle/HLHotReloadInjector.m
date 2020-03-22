//
//  HLHotReloadInjector.m
//  HLHotReloadBundle
//
//  Created by 刘华龙 on 2020/3/22.
//  Copyright © 2020 刘华龙. All rights reserved.
//

#import "HLHotReloadInjector.h"
#import <objc/runtime.h>
#include <dlfcn.h>

@implementation HLHotReloadInjector

+ (instancetype)sharedInstance {
    static HLHotReloadInjector *injector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        injector = [[HLHotReloadInjector alloc] init];
    });
    return injector;
}

- (void)loadAndInject:(NSString *)libPath {
    
    const char *cString = [libPath cStringUsingEncoding:NSASCIIStringEncoding];
    void *handle = dlopen(cString, RTLD_NOW);
    if (!handle) {
        NSLog(@"Error: cannot find <%@>", libPath);
        return;
    }
    for (NSString *classSymbol in self.classSymbolNames) {
        const char *cString = [[classSymbol substringFromIndex:1] cStringUsingEncoding:NSASCIIStringEncoding];
        void *class = dlsym(handle, cString);
        Class newClass = [(__bridge NSObject *)class class];
        NSString *newClassStr = NSStringFromClass(newClass);
        Class oldClass = NSClassFromString(newClassStr);
        [self inject:newClass oldClass:oldClass];
    }
}


- (void)inject:(Class)newClass oldClass:(Class)oldClass {
    uint32_t methodCount = 0;
    Method *methods = class_copyMethodList(newClass, &methodCount);
    if (methods) {
        for (int i = 0; i < methodCount; i++) {
            class_replaceMethod(oldClass, method_getName(methods[i]), method_getImplementation(methods[i]), method_getTypeEncoding(methods[i]));
        }
        free(methods);
        NSLog(@"👍 %@ -- 注入成功", NSStringFromClass(newClass));
    }
}




@end
