#import <UIKit/UIKit.h>

@interface InjectorViewController : UIViewController
    <UITableViewDataSource, UITableViewDelegate,
     NSURLSessionDownloadDelegate>

@property (nonatomic, weak)   UITableView             *tableView;
@property (nonatomic, weak)   UISegmentedControl      *gameSegment;
@property (nonatomic, weak)   UIButton                *injectButton;
@property (nonatomic, weak)   UIButton                *bypassButton;
@property (nonatomic, weak)   UIProgressView          *progressView;
@property (nonatomic, weak)   UILabel                 *progressLabel;
@property (nonatomic, strong) NSURLSession            *session;
@property (nonatomic, strong) NSDictionary            *aimMap;       // key -> asset path
@property (nonatomic, copy)   NSString                *chamsFile;    // default: Assembly-CSharp-patch.bytes
@property (nonatomic, strong) NSData                  *chamsJson;
@property (nonatomic, strong) NSMutableArray          *ops;          // download queue
@property (nonatomic, copy)   NSString                *currentCachePath;
@property (nonatomic, assign) NSInteger               opsDone;
@property (nonatomic, assign) NSInteger               opsTotal;
@property (nonatomic, copy)   NSString                *gameKey;      // "ffth" | "ffmax"
@property (nonatomic, copy)   NSString                *containerPath;
@property (nonatomic, assign) BOOL                    isBypass;
@property (nonatomic, strong) NSString                *apiToken;
@property (nonatomic, weak)   UIView                  *overlayView;
@end
