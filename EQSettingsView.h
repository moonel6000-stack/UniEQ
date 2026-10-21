#import <UIKit/UIKit.h>

/* Apps installées visibles : [{bid, name}], apps utilisateur puis système, triées */
NSArray<NSDictionary *> *SEQInstalledApps(void);

@interface SEQSettingsView : UIView
@property (nonatomic, copy) void (^onBack)(void);
@end
