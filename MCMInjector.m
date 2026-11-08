#import "MCMInjector.h"
#import <Security/Security.h>
#import <dlfcn.h>
#import <fcntl.h>

// ---- ContainerManager private API function pointers ----

static void *_MCMSharedAPI_api;
static dispatch_once_t _MCMSharedAPI_once;

typedef void* container_query_t;
typedef void* container_object_t;
typedef void* container_error_t;

static container_query_t (*_container_query_create)(void);
static void (*_container_query_set_class)(container_query_t, int);
static void (*_container_query_set_identifiers)(container_query_t, CFArrayRef);
static void (*_container_query_set_group_identifiers)(container_query_t, CFArrayRef);
static void (*_container_query_operation_set_flags)(container_query_t, uint64_t);
static void (*_container_query_operation_set_part)(container_query_t, int);
static void (*_container_query_operation_set_part_domain)(container_query_t, int);
static container_object_t (*_container_query_get_single_result)(container_query_t);
static container_error_t (*_container_query_get_last_error)(container_query_t);
static void (*_container_query_iterate_results_sync)(container_query_t, void(^)(container_object_t, bool *));
static void (*_container_query_free)(container_query_t);
static CFStringRef (*_container_object_get_path)(container_object_t);
static CFStringRef (*_container_object_get_identifier)(container_object_t);
static container_object_t (*_container_object_copy)(container_object_t);
static CFDataRef (*_container_copy_sandbox_token)(container_object_t, container_error_t *);
static bool (*_container_object_sandbox_extension_activate)(container_object_t, container_error_t *);
static void (*_container_object_free)(container_object_t);
static int (*_container_error_get_posix_errno)(container_error_t);
static const char *(*_container_error_get_message)(container_error_t);

static void _MCMLoadAPI(void) {
    dispatch_once(&_MCMSharedAPI_once, ^{
        _MCMSharedAPI_api = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
        void *lib = _MCMSharedAPI_api ?: (void *)-2;
        _container_query_create                        = dlsym(lib, "container_query_create");
        _container_query_set_class                     = dlsym(lib, "container_query_set_class");
        _container_query_set_identifiers               = dlsym(lib, "container_query_set_identifiers");
        _container_query_set_group_identifiers         = dlsym(lib, "container_query_set_group_identifiers");
        _container_query_operation_set_flags           = dlsym(lib, "container_query_operation_set_flags");
        _container_query_operation_set_part            = dlsym(lib, "container_query_operation_set_part");
        _container_query_operation_set_part_domain     = dlsym(lib, "container_query_operation_set_part_domain");
        _container_query_get_single_result             = dlsym(lib, "container_query_get_single_result");
        _container_query_get_last_error                = dlsym(lib, "container_query_get_last_error");
        _container_query_iterate_results_sync          = dlsym(lib, "container_query_iterate_results_sync");
        _container_query_free                          = dlsym(lib, "container_query_free");
        _container_object_get_path                     = dlsym(lib, "container_object_get_path");
        _container_object_get_identifier               = dlsym(lib, "container_object_get_identifier");
        _container_object_copy                         = dlsym(lib, "container_object_copy");
        _container_copy_sandbox_token                  = dlsym(lib, "container_copy_sandbox_token");
        _container_object_sandbox_extension_activate   = dlsym(lib, "container_object_sandbox_extension_activate");
        _container_object_free                         = dlsym(lib, "container_object_free");
        _container_error_get_posix_errno               = dlsym(lib, "container_error_get_posix_errno");
        _container_error_get_message                   = dlsym(lib, "container_error_get_message");
    });
}

BOOL _MCMBridgeAvailable(void) {
    _MCMLoadAPI();
    if (!_container_query_create) return NO;
    return YES;
}

// ---- Signed-identity check (once) ----
static dispatch_once_t _sigId_once;
static NSString *_sigId_identifier;

static void _MCMLoadSignedIdentifier(void) {
    dispatch_once(&_sigId_once, ^{
        SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
        if (task) {
            CFErrorRef err = NULL;
            CFStringRef id = SecTaskCopySigningIdentifier(task, &err);
            if (id) {
                _sigId_identifier = [(__bridge NSString *)id copy];
                CFRelease(id);
            }
            if (err) CFRelease(err);
            CFRelease(task);
        }
    });
}

// ---- Global last-error ----
static NSString *_gLastError;

NSString *_MCMInjectorLastError(void) { return _gLastError; }

// ---- Lease cache ----
static NSMutableDictionary *_leaseCache;
static dispatch_once_t _leaseCacheOnce;

// ---- MCMLease ----

@interface MCMLease ()
@property (nonatomic, strong) id _queryResult;
@end

@implementation MCMLease

+ (instancetype)leaseForClass:(int)cls
                   identifier:(NSString *)identifier
                        group:(id)group
                         part:(int)part
                        flags:(uint64_t)flags
                        error:(NSString **)error {
    return [self leaseForClass:cls identifier:identifier group:group
                          part:part partDomain:nil flags:flags error:error];
}

+ (instancetype)leaseForClass:(int)cls
                   identifier:(NSString *)identifier
                        group:(id)group
                         part:(int)part
                   partDomain:(id)partDomain
                        flags:(uint64_t)flags
                        error:(NSString **)error {
    _MCMLoadAPI();
    if (!_container_query_create) {
        if (error) *error = @"part API unavailable on this OS";
        return nil;
    }
    container_query_t q = _container_query_create();
    if (!q) {
        if (error) *error = @"container_query_create returned NULL";
        return nil;
    }
    _container_query_set_class(q, cls);
    CFStringRef cfId = (__bridge CFStringRef)identifier;
    CFArrayRef ids = CFArrayCreate(NULL, (const void **)&cfId, 1, &kCFTypeArrayCallBacks);
    _container_query_set_identifiers(q, ids);
    CFRelease(ids);
    _container_query_operation_set_flags(q, flags);
    if (part) _container_query_operation_set_part(q, part);
    if (partDomain) _container_query_operation_set_part_domain(q, (int)(intptr_t)partDomain);

    container_object_t obj = _container_query_get_single_result(q);
    container_error_t err = _container_query_get_last_error(q);
    if (!obj) {
        if (error && err) {
            int en = _container_error_get_posix_errno(err);
            const char *msg = _container_error_get_message(err);
            *error = [NSString stringWithFormat:@"lookup denied posix=%d message=%s", en, msg];
        }
        _container_query_free(q);
        return nil;
    }

    MCMLease *lease = [[MCMLease alloc] init];
    lease.identifier = identifier;
    lease._queryResult = (__bridge id)obj;

    CFStringRef path = _container_object_get_path(obj);
    if (path) lease.rootPath = (__bridge NSString *)path;

    _container_query_free(q);
    return lease;
}

- (BOOL)activate:(NSString **)error {
    if (!self._queryResult) return NO;
    container_object_t obj = (__bridge container_object_t)self._queryResult;
    container_error_t err = NULL;
    BOOL ok = _container_object_sandbox_extension_activate(obj, &err);
    if (!ok) {
        if (error && err) {
            int en = _container_error_get_posix_errno(err);
            const char *msg = _container_error_get_message(err);
            *error = [NSString stringWithFormat:@"%s (errno=%d)", msg, en];
        }
    }
    self.activated = ok;
    return ok;
}

- (void)invalidate {
    self.activated = NO;
}

- (void)dealloc { [self invalidate]; }

@end

// ---- _MCMInjectorDataContainerPath ----

NSString *_MCMInjectorDataContainerPath(NSString *bundleId) {
    _MCMLoadAPI();
    _MCMLoadSignedIdentifier();

    if (![_sigId_identifier isEqualToString:@"com.apple.mobile.MobileHouseArrest"]) {
        _gLastError = [NSString stringWithFormat:
            @"identidade assinada '%@' != com.apple.mobile.MobileHouseArrest", _sigId_identifier];
        return nil;
    }
    if (bundleId.length == 0) { _gLastError = @"bundleId vazio"; return nil; }

    dispatch_once(&_leaseCacheOnce, ^{ _leaseCache = [NSMutableDictionary dictionary]; });

    NSString *result = nil;
    @synchronized(_leaseCache) {
        MCMLease *cached = _leaseCache[bundleId];
        if (cached.rootPath.length > 0) return cached.rootPath;

        NSString *leaseErr = nil;
        MCMLease *lease = [MCMLease leaseForClass:2
                                       identifier:bundleId
                                            group:nil
                                             part:0
                                            flags:0x900000000ULL
                                            error:&leaseErr];
        if (!lease) {
            _gLastError = leaseErr ?: @"lease MCM falhou";
            return;
        }
        NSString *activateErr = nil;
        BOOL activated = [lease activate:&activateErr];
        NSString *rootPath = lease.rootPath;

        int fd = open(rootPath.fileSystemRepresentation, O_RDONLY | O_DIRECTORY);
        if (fd < 0) {
            _gLastError = activated
                ? [NSString stringWithFormat:@"open container errno=%d", errno]
                : [NSString stringWithFormat:@"%@ (errno=%d)", activateErr ?: @"sandbox extension activation failed", errno];
            [lease invalidate];
            return;
        }
        close(fd);
        _leaseCache[bundleId] = lease;
        _gLastError = nil;
        result = rootPath;
    }
    return result;
}
