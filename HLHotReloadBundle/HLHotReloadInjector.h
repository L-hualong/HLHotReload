//
//  HLHotReloadInjector.h
//  HLHotReloadBundle
//
//  Created by 刘华龙 on 2020/3/22.
//  Copyright © 2020 刘华龙. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HLHotReloadInjector : NSObject

@property (nonatomic) NSMutableArray <NSString *> *classSymbolNames;

+ (instancetype)sharedInstance;

- (void)loadAndInject:(NSString *)libPath;

@end

NS_ASSUME_NONNULL_END
