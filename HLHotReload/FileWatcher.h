//
//  FileWatcher.h
//  HLHotReload
//
//  Created by 刘华龙 on 2020/3/21.
//  Copyright © 2020 刘华龙. All rights reserved.
//

#import <Foundation/Foundation.h>

#define INJECTABLE_PATTERN @"[^~]\\.(mm?|swift|storyboard|xib)$"

typedef void (^InjectionCallback)(NSArray *filesChanged);

@interface FileWatcher : NSObject

@property(copy) InjectionCallback callback;

- (instancetype)initWithRoot:(NSString *)projectRoot plugin:(InjectionCallback)callback;

@end
