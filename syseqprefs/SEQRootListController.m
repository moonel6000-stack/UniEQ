#import <Preferences/PSListController.h>

@interface SEQRootListController : PSListController
@end

@implementation SEQRootListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}
@end
