//
//  FileWatcher.m
//  HLHotReload
//
//  Created by 刘华龙 on 2020/3/21.
//  Copyright © 2020 刘华龙. All rights reserved.
//

#import "FileWatcher.h"

@implementation FileWatcher {
    FSEventStreamRef fileEvents;
}

static void fileCallback(ConstFSEventStreamRef streamRef,
                         void *clientCallBackInfo,
                         size_t numEvents, void *eventPaths,
                         const FSEventStreamEventFlags eventFlags[],
                         const FSEventStreamEventId eventIds[]) {
    FileWatcher *self = (__bridge FileWatcher *)clientCallBackInfo;
    
    BOOL shouldRespondToFileChange = NO;
    for (int i = 0; i < numEvents; i++) {
        uint32 flag = eventFlags[i];
        if (flag & (kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified)) {
            shouldRespondToFileChange = YES;
            break;
        }
    }

    if (shouldRespondToFileChange == YES) {
        [self performSelectorOnMainThread:@selector(filesChanged:)
                               withObject:(__bridge id)eventPaths waitUntilDone:NO];
    }
}

- (instancetype)initWithRoot:(NSString *)projectRoot plugin:(InjectionCallback)callback;
{
    if ((self = [super init])) {
        self.callback = callback;
        static struct FSEventStreamContext context;
        context.info = (__bridge void *)self;
        fileEvents = FSEventStreamCreate(kCFAllocatorDefault,//要用于为流分配内存的CFAllocator。传递NULL或kCFAllocatorDefault以使用当前默认分配器。
                                         fileCallback,//一个FSEventStreamCallback，当FS事件发生时将调用它。
                                         &context,//指向客户端希望与此流关联的FSEventStreamContext结构的指针
                                         (__bridge CFArrayRef) @[ projectRoot ],//CFStringRefs的CFArray，每个CFArray指定一个目录的路径，表示要监视文件系统层次结构的根以进行修改。
                                         kFSEventStreamEventIdSinceNow,//传入常量kFSEventStreamEventIdSinceNow，表示“从现在开始”要请求事件。
                                         .1,//服务在从内核听到事件后应该等待的秒数
                                         kFSEventStreamCreateFlagUseCFTypes |//修改正在创建的流的行为的标志
                                         kFSEventStreamCreateFlagFileEvents);
        //调用者负责确保流被调度在至少一个RunLoop上，并且被调度的流正在至少一个RunLoop上运行。
        FSEventStreamScheduleWithRunLoop(fileEvents, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        //尝试向FS Events服务注册，以便根据流中的参数接收事件。即开始监控
        FSEventStreamStart(fileEvents);
    }

    return self;
}

- (void)filesChanged:(NSArray *)changes;
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableSet *changed = [NSMutableSet new];

    for (NSString *path in changes) {
        if ([path rangeOfString:INJECTABLE_PATTERN
                        options:NSRegularExpressionSearch].location != NSNotFound &&
            [path rangeOfString:@"DerivedData/|InjectionProject/|main.mm?$"
                        options:NSRegularExpressionSearch].location == NSNotFound &&
            [fileManager fileExistsAtPath:path]) {

            [changed addObject:path];
        }
    }

    if (changed.count) {
        self.callback([[changed objectEnumerator] allObjects]);
    }
}

- (void)dealloc;
{
    FSEventStreamStop(fileEvents);
    FSEventStreamInvalidate(fileEvents);
    FSEventStreamRelease(fileEvents);
}

@end
