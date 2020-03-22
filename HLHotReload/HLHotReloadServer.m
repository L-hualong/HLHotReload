//
//  HLHotReloadServer.m
//  HLHotReload
//
//  Created by 刘华龙 on 2020/3/21.
//  Copyright © 2020 刘华龙. All rights reserved.
//

#import "HLHotReloadServer.h"
#import "FileWatcher.h"
#import "AppDelegate.h"
#import <dlfcn.h>
#import "HLHotReload-Swift.h"

typedef NS_ENUM(NSInteger, HLHotReloadCommond) {
    // 打印log
    HLHotReloadCommondLog = 0,
    // 注入
    HLHotReloadCommondInject,
};

@interface HLHotReloadServer() <GCDAsyncSocketDelegate>

@property (nonatomic) GCDAsyncSocket *server;
@property (nonatomic) GCDAsyncSocket *client;
@property (nonatomic) FileWatcher *fileWatcher;
@property (nonatomic, copy) void (^injector)(NSArray *changed);
@property (nonatomic) NSMutableArray *pending;

@end

@implementation HLHotReloadServer

- (void)startServer {
    [self performSelectorInBackground:@selector(runServer) withObject:nil];
}

- (void)runServer {
    if (self.server.isConnected) {
        [self.server disconnect];
    }
    uint16_t port = 10000;
    NSError *error = nil;
    GCDAsyncSocket *server = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    self.server = server;
    [server acceptOnPort:port error:&error];
    
    self.pending = @[].mutableCopy;
    __weak typeof(self) wself = self;
    self.injector = ^(NSArray *changed) {
        __strong typeof(wself) self = wself;
        NSMutableArray *changedFiles = [NSMutableArray arrayWithArray:changed];
        for (NSString *source in changedFiles) {
            if (![self.pending containsObject:source]) {
                [self.pending addObject:source];
            }
        }
        [self inject];
    };
}

- (void)inject {
    for (NSString *source in self.pending) {
        NSString * tmpfile = [[HLHotReloadInjector sharedInstance] rebuildClassWithSourceFile:source error:nil];
        NSArray<NSString *> *classSymbolNames = @[].mutableCopy;
        classSymbolNames = [[HLHotReloadInjector sharedInstance] extractClasSymbolsWithTmpfile:tmpfile error:nil];
        NSMutableDictionary *dict = @{}.mutableCopy;
        [dict setValue:tmpfile forKey:@"libPath"];
        [dict setValue:classSymbolNames forKey:@"classSymbolNames"];
        NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
        [self.client writeData:data withTimeout:-1 tag:HLHotReloadCommondInject];
    }
    [self.pending removeAllObjects];
}

- (void)watchDirectory:(NSString *)directory {
    self.fileWatcher = [[FileWatcher alloc] initWithRoot:directory plugin:self.injector];
    NSData *data = [[NSString stringWithFormat:@"👍已开始监听该工程：%@",directory] dataUsingEncoding:NSUTF8StringEncoding];
    [self.client writeData:data withTimeout:-1 tag:HLHotReloadCommondLog];
}

#pragma mark - GCDAsyncSocket Delegate
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    self.client = newSocket;
    NSOpenPanel *open = [NSOpenPanel new];
    open.canChooseDirectories = YES;
    open.canChooseFiles = NO;
    if ([open runModal] == NSModalResponseOK)  {
        NSString *directory = open.URL.path;
        [self watchDirectory:directory];
    }
}

@end
