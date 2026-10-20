#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

static NSString *const kDomain = @"com.example.syseq";
static NSString *const kNotify = @"com.example.syseq/prefschanged";

/* API privée déclarée via une catégorie (pas de dépendance de lien) */
@interface NSObject (SEQLaunchServices)
+ (id)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end

@interface SEQAppsController : PSListController
@end

@implementation SEQAppsController

static id kv(id obj, NSString *key) {
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

- (PSSpecifier *)specForName:(NSString *)name bundleID:(NSString *)bid {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:Nil
                                                       cell:PSSwitchCell
                                                       edit:Nil];
    [sp setProperty:kDomain forKey:@"defaults"];
    [sp setProperty:[@"app." stringByAppendingString:bid] forKey:@"key"];
    [sp setProperty:@NO forKey:@"default"];
    [sp setProperty:kNotify forKey:@"PostNotification"];
    return sp;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *users = [NSMutableArray array], *system = [NSMutableArray array];
    id ws = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
    for (id proxy in [ws allInstalledApplications]) {
        NSString *bid = kv(proxy, @"applicationIdentifier");
        NSString *name = kv(proxy, @"localizedName");
        NSString *type = kv(proxy, @"applicationType");
        NSArray *tags = kv(proxy, @"appTags");
        if (!bid.length || !name.length) continue;
        if ([tags isKindOfClass:NSArray.class] && [tags containsObject:@"hidden"]) continue;
        NSDictionary *item = @{ @"bid": bid, @"name": name };
        if ([type isEqualToString:@"User"]) [users addObject:item]; else [system addObject:item];
    }
    NSComparator cmp = ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    };
    [users sortUsingComparator:cmp];
    [system sortUsingComparator:cmp];

    NSMutableArray *specs = [NSMutableArray array];
    PSSpecifier *g1 = [PSSpecifier groupSpecifierWithName:@"Apps installées"];
    [g1 setProperty:@"Selon le mode choisi, l’égaliseur s’applique à toutes les apps sauf celles cochées, ou seulement à celles cochées." forKey:@"footerText"];
    [specs addObject:g1];
    for (NSDictionary *d in users) [specs addObject:[self specForName:d[@"name"] bundleID:d[@"bid"]]];

    [specs addObject:[PSSpecifier groupSpecifierWithName:@"Apps système"]];
    for (NSDictionary *d in system) [specs addObject:[self specForName:d[@"name"] bundleID:d[@"bid"]]];

    _specifiers = specs;
    self.title = @"Applications";
    return _specifiers;
}

@end
