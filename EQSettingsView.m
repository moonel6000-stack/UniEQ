#import "EQSettingsView.h"
#include "EQShared.h"

@interface NSObject (SEQLaunchServices)
+ (id)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end

static id kvv(id o, NSString *k) {
    @try { return [o valueForKey:k]; } @catch (__unused NSException *e) { return nil; }
}

NSArray<NSDictionary *> *SEQInstalledApps(void) {
    NSMutableArray *users = [NSMutableArray array], *sys = [NSMutableArray array];
    id ws = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
    for (id proxy in [ws allInstalledApplications]) {
        NSString *bid = kvv(proxy, @"applicationIdentifier");
        NSString *name = kvv(proxy, @"localizedName");
        NSString *type = kvv(proxy, @"applicationType");
        NSArray *tags = kvv(proxy, @"appTags");
        if (!bid.length || !name.length) continue;
        if ([tags isKindOfClass:NSArray.class] && [tags containsObject:@"hidden"]) continue;
        NSDictionary *item = @{ @"bid": bid, @"name": name };
        if ([type isEqualToString:@"User"]) [users addObject:item]; else [sys addObject:item];
    }
    NSComparator cmp = ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    };
    [users sortUsingComparator:cmp];
    [sys sortUsingComparator:cmp];
    return [users arrayByAddingObjectsFromArray:sys];
}

static NSArray<NSString *> *outKeys(void) { return @[@"out.speaker", @"out.wired", @"out.bt", @"out.airplay", @"out.other"]; }
static NSArray<NSString *> *outNames(void) { return @[@"Haut-parleur / récepteur", @"Écouteurs filaires", @"Bluetooth", @"AirPlay", @"Autres (USB, HDMI, voiture)"]; }

@interface SEQSettingsView () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic) UITableView *table;
@property (nonatomic) NSArray<NSDictionary *> *apps;
@property (nonatomic) NSArray<NSDictionary *> *active;
@property (nonatomic) NSString *activeSig;
@property (nonatomic) BOOL resetArmed;
@end

@implementation SEQSettingsView

- (instancetype)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.98];
    self.layer.cornerRadius = 16;
    self.clipsToBounds = YES;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    back.frame = CGRectMake(8, 0, 90, 44);
    [back setTitle:@"‹ Retour" forState:UIControlStateNormal];
    [back addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:back];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, f.size.width, 44)];
    t.text = @"Réglages";
    t.textAlignment = NSTextAlignmentCenter;
    t.textColor = UIColor.whiteColor;
    t.font = [UIFont boldSystemFontOfSize:16];
    t.userInteractionEnabled = NO;
    t.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self addSubview:t];

    self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 44, f.size.width, f.size.height - 44) style:UITableViewStyleGrouped];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.table];

    self.apps = SEQInstalledApps();
    self.active = @[];

    __weak SEQSettingsView *ws = self;
    [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *tm) { [ws tick]; }];
    return self;
}

- (void)setHidden:(BOOL)h {
    [super setHidden:h];
    if (!h) { self.activeSig = nil; [self tick]; }
}

- (void)backTapped { if (self.onBack) self.onBack(); }

- (void)tick {
    if (self.hidden || !self.window) return;
    NSArray *a = [SEQHub activeApps];
    NSMutableString *sig = [NSMutableString string];
    for (NSDictionary *d in a) [sig appendFormat:@"%@;", d[@"bid"]];
    if ([sig isEqualToString:self.activeSig]) return;
    self.activeSig = sig;
    self.active = a;
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Table (0 = sons en cours, 1 = sorties, 2 = mode, 3 = applications)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return MAX((NSInteger)self.active.count, 1);
    if (s == 1) return 5;
    if (s == 2) return 1;
    return (NSInteger)self.apps.count + 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"Sons en cours (choisis ceux traités par l’EQ)";
    if (s == 1) return @"Sorties audio (l’EQ s’applique à…)";
    if (s == 2) return @"Mode des applications";
    return @"Applications";
}

- (BOOL)appEffectiveOn:(NSString *)bid {
    BOOL includeOnly = SEQGetPrefInt("mode", 0) == 1;
    BOOL listed = SEQGetPrefBool([@"app." stringByAppendingString:bid].UTF8String, false);
    return includeOnly ? listed : !listed;
}

- (UITableViewCell *)plainCell:(UITableView *)tv id:(NSString *)rid {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:rid];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
        c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        c.textLabel.textColor = UIColor.whiteColor;
        c.textLabel.font = [UIFont systemFontOfSize:14];
    }
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 2) {
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"seg"];
        if (!c) {
            c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"seg"];
            c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Toutes sauf", @"Seulement"]];
            seg.frame = CGRectMake(10, 6, tv.bounds.size.width - 20 - 40, 32);
            seg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            seg.tag = 77;
            [seg addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
            [c.contentView addSubview:seg];
        }
        UISegmentedControl *seg = [c.contentView viewWithTag:77];
        seg.selectedSegmentIndex = SEQGetPrefInt("mode", 0) ? 1 : 0;
        return c;
    }

    if (ip.section == 3 && ip.row == 0) {
        UITableViewCell *c = [self plainCell:tv id:@"btn"];
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        c.textLabel.textAlignment = NSTextAlignmentCenter;
        c.textLabel.textColor = UIColor.systemRedColor;
        c.textLabel.text = self.resetArmed ? @"Toucher à nouveau pour confirmer" : @"Réinitialiser la sélection d’apps";
        return c;
    }

    if (ip.section == 0 && self.active.count == 0) {
        UITableViewCell *c = [self plainCell:tv id:@"ph"];
        c.textLabel.textAlignment = NSTextAlignmentNatural;
        c.textLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
        c.textLabel.text = @"Aucun son détecté — lance de la musique";
        c.accessoryView = nil;
        return c;
    }

    UITableViewCell *c = [self plainCell:tv id:@"sw"];
    c.textLabel.textAlignment = NSTextAlignmentNatural;
    c.textLabel.textColor = UIColor.whiteColor;
    if (![c.accessoryView isKindOfClass:UISwitch.class]) {
        UISwitch *nsw = [[UISwitch alloc] init];
        [nsw addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = nsw;
    }
    UISwitch *sw = (UISwitch *)c.accessoryView;
    sw.tag = ip.section * 10000 + ip.row;
    if (ip.section == 0) {
        NSDictionary *d = self.active[ip.row];
        c.textLabel.text = [NSString stringWithFormat:@"♪ %@", d[@"name"]];
        sw.on = [self appEffectiveOn:d[@"bid"]];
    } else if (ip.section == 1) {
        c.textLabel.text = outNames()[ip.row];
        sw.on = SEQGetPrefBool(outKeys()[ip.row].UTF8String, true);
    } else {
        NSDictionary *d = self.apps[ip.row - 1];
        c.textLabel.text = d[@"name"];
        sw.on = SEQGetPrefBool([@"app." stringByAppendingString:d[@"bid"]].UTF8String, false);
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (!(ip.section == 3 && ip.row == 0)) return;
    if (!self.resetArmed) {
        self.resetArmed = YES;
        [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
        __weak SEQSettingsView *ws = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (ws.resetArmed) { ws.resetArmed = NO; [ws.table reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationNone]; }
        });
    } else {
        self.resetArmed = NO;
        SEQResetAppSelection();
        [tv reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
        [tv reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)modeChanged:(UISegmentedControl *)seg {
    SEQSetPrefInt("mode", (int)seg.selectedSegmentIndex);
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)swChanged:(UISwitch *)sw {
    NSInteger sec = sw.tag / 10000, row = sw.tag % 10000;
    if (sec == 0) {
        if (row >= (NSInteger)self.active.count) return;
        NSString *bid = self.active[row][@"bid"];
        BOOL includeOnly = SEQGetPrefInt("mode", 0) == 1;
        BOOL listed = includeOnly ? sw.on : !sw.on;   /* l'interrupteur = "EQ appliqué à ce son" */
        SEQSetPrefBool([@"app." stringByAppendingString:bid].UTF8String, listed);
        [self.table reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationNone];
    } else if (sec == 1) {
        SEQSetPrefBool(outKeys()[row].UTF8String, sw.on);
    } else if (sec == 3 && row >= 1 && row - 1 < (NSInteger)self.apps.count) {
        NSString *bid = self.apps[row - 1][@"bid"];
        SEQSetPrefBool([@"app." stringByAppendingString:bid].UTF8String, sw.on);
        [self.table reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    }
}

@end
