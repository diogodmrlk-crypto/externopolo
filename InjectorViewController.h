#import <UIKit/UIKit.h>

@interface InjectorViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, NSURLSessionDownloadDelegate>

// Elementos de UI (Mudados para 'strong' para não serem desalocados na memória)
@property (nonatomic, strong) UITableView        *tableView;
@property (nonatomic, strong) UISegmentedControl *gameSegment;
@property (nonatomic, strong) UIButton           *injectButton;
@property (nonatomic, strong) UIButton           *bypassButton;
@property (nonatomic, strong) UIProgressView     *progressView;
@property (nonatomic, strong) UILabel            *progressLabel;
@property (nonatomic, strong) UIView             *overlayView;

// Propriedades de lógica e rede
@property (nonatomic, strong) NSURLSession       *session;
@property (nonatomic, strong) NSDictionary       *aimMap;       // key -> asset path
@property (nonatomic, copy)   NSString           *chamsFile;    // default: Assembly-CSharp-patch.bytes
@property (nonatomic, strong) NSData             *chamsJson;
@property (nonatomic, strong) NSMutableArray     *ops;          // download queue
@property (nonatomic, copy)   NSString           *currentCachePath;
@property (nonatomic, assign) NSInteger          opsDone;
@property (nonatomic, assign) NSInteger          opsTotal;
@property (nonatomic, copy)   NSString           *gameKey;      // "ffth" | "ffmax"
@property (nonatomic, copy)   NSString           *containerPath;
@property (nonatomic, assign) BOOL               isBypass;
@property (nonatomic, strong) NSString           *apiToken;

@end
