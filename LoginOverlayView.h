#import <UIKit/UIKit.h>

@interface LoginOverlayView : UIView
@property (nonatomic, copy) void (^onSuccess)(NSString *token);
@property (nonatomic, weak) UITextField *keyField;
@property (nonatomic, weak) UIButton *activateButton;
@property (nonatomic, weak) UIButton *pasteButton;
@property (nonatomic, weak) UILabel *statusLabel;
@property (nonatomic, weak) UIActivityIndicatorView *spinner;

- (void)setBusy:(BOOL)busy status:(NSString *)status;
- (void)dismissAnimated;
+ (NSString *)deviceModel;
+ (NSString *)iosVersion;
+ (NSString *)deviceFingerprint;
+ (NSString *)deviceHwid;
@end
