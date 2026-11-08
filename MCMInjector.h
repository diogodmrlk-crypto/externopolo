#import <Foundation/Foundation.h>

// Private ContainerManager API wrapper.
// Signs as com.apple.mobile.MobileHouseArrest ("Exploit de Filza by ditx").

@interface MCMLease : NSObject
@property (nonatomic, copy) NSString *containerClass;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *rootPath;
@property (nonatomic, copy) NSString *groupIdentifier;
@property (nonatomic, assign) BOOL tokenPresent;
@property (nonatomic, assign) BOOL activated;

+ (instancetype)leaseForClass:(int)cls
                   identifier:(NSString *)identifier
                        group:(id)group
                         part:(int)part
                        flags:(uint64_t)flags
                        error:(NSString **)error;

+ (instancetype)leaseForClass:(int)cls
                   identifier:(NSString *)identifier
                        group:(id)group
                         part:(int)part
                   partDomain:(id)partDomain
                        flags:(uint64_t)flags
                        error:(NSString **)error;

- (BOOL)activate:(NSString **)error;
- (void)invalidate;
@end

// Returns the data container path for bundleId; nil on failure.
// Sets _MCMInjectorLastError() on failure.
NSString *_MCMInjectorDataContainerPath(NSString *bundleId);
NSString *_MCMInjectorLastError(void);
BOOL _MCMBridgeAvailable(void);
