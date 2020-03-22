//
//  HLHotReloadClient.m
//  HLHotReloadBundle
//
//  Created by 刘华龙 on 2020/3/22.
//  Copyright © 2020 刘华龙. All rights reserved.
//

#import "HLHotReloadClient.h"
#import "HLHotReloadInjector.h"

typedef NS_ENUM(NSInteger, HLHotReloadCommond) {
    // 打印log
    HLHotReloadCommondLog = 0,
    // 注入
    HLHotReloadCommondInject,
};

@interface HLHotReloadClient() <GCDAsyncSocketDelegate>

@property (nonatomic) GCDAsyncSocket *socket;

@end

@implementation HLHotReloadClient

+ (void)load {
    HLHotReloadClient *client = [HLHotReloadClient sharedInstance];
    GCDAsyncSocket *socket = [[GCDAsyncSocket alloc] initWithDelegate:client delegateQueue:dispatch_get_main_queue()];
    client.socket = socket;
    NSError *err = nil;
    [socket connectToHost:@"127.0.0.1" onPort:10000 viaInterface:nil withTimeout:-1 error:&err];
}

+ (instancetype)sharedInstance {
    static HLHotReloadClient *client;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[HLHotReloadClient alloc] init];
    });
    return client;
}

#pragma mark - GCDAsyncSocket Delegate
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    if (tag == HLHotReloadCommondLog) {
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"%@", str);
    } else if (tag == HLHotReloadCommondInject) {
        NSDictionary *dict =[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:nil];
        [HLHotReloadInjector sharedInstance].classSymbolNames = dict[@"classSymbolNames"];
        [[HLHotReloadInjector sharedInstance] loadAndInject:[dict[@"libPath"] stringByAppendingString:@".dylib"]];
        [self.socket readDataWithTimeout:-1 tag:1];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    NSLog(@"已成功连接HLHotReload👍");
    [self.socket readDataWithTimeout:-1 tag:0];
    [self.socket readDataWithTimeout:-1 tag:1];
}

@end
