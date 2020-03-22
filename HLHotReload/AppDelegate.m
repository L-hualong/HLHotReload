//
//  AppDelegate.m
//  HLHotReload
//
//  Created by 刘华龙 on 2020/3/21.
//  Copyright © 2020 刘华龙. All rights reserved.
//

#import "AppDelegate.h"
#import "HLHotReloadServer.h"
#import "HLHotReload-Swift.h"

@interface AppDelegate ()
@property (weak) IBOutlet NSMenu *statusMenu;
@property (strong) NSStatusItem *statusItem;
@property (strong) HLHotReloadServer *server;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    self.statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.menu = self.statusMenu;
    [self.statusItem.button setTitle:@"HLHotReload"];
    
    self.server = [[HLHotReloadServer alloc] init];
    [self.server startServer];
}

// 选择工程目录
- (IBAction)addProject:(id)sender {
    NSOpenPanel *open = [NSOpenPanel new];
    open.canChooseDirectories = YES;
    open.canChooseFiles = NO;
    if ([open runModal] == NSModalResponseOK)  {
        NSString *directory = open.URL.path;
        [self.server watchDirectory:directory];
    }
}

// 清理缓存
- (IBAction)clearCache:(id)sender {
    [[HLHotReloadInjector sharedInstance] shellWithCommand:@"rm -rf /tmp/HLHotRelod_cache/*"];
}

// 退出
- (IBAction)quit:(id)sender {
    [[NSApplication sharedApplication] terminate:self];
}

@end
