#import <UIKit/UIKit.h>
#include <math.h>
#include "EQShared.h"

@interface SEQWindow : UIWindow @end
@implementation SEQWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return (v == self || v == self.rootViewController.view) ? nil : v;
}
@end

@interface SEQVC : UIViewController
@property (nonatomic) UIButton *bubble;
@property (nonatomic) UIView *panel;
@property (nonatomic) UISwitch *sw;
@property (nonatomic) NSMutableArray<UISlider *> *sliders; // 0 = pre, 1..5 = bandes
@property (nonatomic) SEQSettings set;
@end

@implementation SEQVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    SEQSettings s; SEQLoadSettings(&s); self.set = s;

    // Bulle
    self.bubble = [UIButton buttonWithType:UIButtonTypeCustom];
    self.bubble.frame = CGRectMake(20, 200, 46, 46);
    self.bubble.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    self.bubble.layer.cornerRadius = 23;
    self.bubble.layer.borderWidth = 1.5;
    [self.bubble setTitle:@"EQ" forState:UIControlStateNormal];
    self.bubble.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.bubble addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragBubble:)]];
    [self.view addSubview:self.bubble];
    [self refreshBubble];

    // Panneau
    CGFloat W = 270, H = 330;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(80, 200, W, H)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    self.panel.layer.cornerRadius = 16;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 44)];
    head.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    [head addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];
    [self.panel addSubview:head];
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, 120, 44)];
    t.text = @"Égaliseur"; t.textColor = UIColor.whiteColor; t.font = [UIFont boldSystemFontOfSize:16];
    [head addSubview:t];
    self.sw = [[UISwitch alloc] initWithFrame:CGRectMake(W - 64, 6, 0, 0)];
    self.sw.on = self.set.enabled;
    [self.sw addTarget:self action:@selector(swChanged) forControlEvents:UIControlEventValueChanged];
    [head addSubview:self.sw];

    NSArray *names = @[@"Pré", @"60 Hz", @"230", @"910", @"3.6k", @"14k"];
    self.sliders = [NSMutableArray array];
    for (int i = 0; i < 6; i++) {
        CGFloat y = 56 + i * 40;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, y, 52, 30)];
        l.text = names[i]; l.textColor = [UIColor colorWithWhite:0.85 alpha:1]; l.font = [UIFont systemFontOfSize:13];
        [self.panel addSubview:l];
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(68, y, W - 68 - 14, 30)];
        sl.minimumValue = -12; sl.maximumValue = 12;
        sl.value = (i == 0) ? self.set.pre : self.set.gains[i - 1];
        sl.tag = i;
        [sl addTarget:self action:@selector(slChanged:) forControlEvents:UIControlEventValueChanged];
        [self.panel addSubview:sl];
        [self.sliders addObject:sl];
    }
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    reset.frame = CGRectMake(14, H - 42, 90, 32);
    [reset setTitle:@"Reset" forState:UIControlStateNormal];
    [reset addTarget:self action:@selector(reset) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:reset];
    UIButton *bass = [UIButton buttonWithType:UIButtonTypeSystem];
    bass.frame = CGRectMake(W - 14 - 110, H - 42, 110, 32);
    [bass setTitle:@"Bass boost" forState:UIControlStateNormal];
    [bass addTarget:self action:@selector(bassPreset) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:bass];
}

- (void)refreshBubble {
    self.bubble.layer.borderColor = (self.set.enabled ? UIColor.systemGreenColor : UIColor.grayColor).CGColor;
    [self.bubble setTitleColor:(self.set.enabled ? UIColor.systemGreenColor : UIColor.lightGrayColor) forState:UIControlStateNormal];
}

- (void)commit { SEQSaveSettings(&_set); [self refreshBubble]; }

- (void)swChanged { _set.enabled = self.sw.on; [self commit]; }

- (void)slChanged:(UISlider *)s {
    float v = roundf(s.value * 2) / 2; // pas de 0.5 dB
    if (s.tag == 0) _set.pre = v; else _set.gains[s.tag - 1] = v;
    [self commit];
}

- (void)setAllFromSettings {
    self.sliders[0].value = _set.pre;
    for (int i = 0; i < SEQ_BANDS; i++) self.sliders[i + 1].value = _set.gains[i];
    self.sw.on = _set.enabled;
}
- (void)reset {
    _set.pre = 0; for (int i = 0; i < SEQ_BANDS; i++) _set.gains[i] = 0;
    [self setAllFromSettings]; [self commit];
}
- (void)bassPreset {
    float g[SEQ_BANDS] = { 6, 4, 0, 0, 1 };
    _set.pre = -4; for (int i = 0; i < SEQ_BANDS; i++) _set.gains[i] = g[i];
    _set.enabled = true;
    [self setAllFromSettings]; [self commit];
}

- (CGPoint)clamp:(CGPoint)c size:(CGSize)sz {
    CGRect b = self.view.bounds; UIEdgeInsets ins = self.view.safeAreaInsets;
    c.x = MAX(sz.width / 2, MIN(b.size.width - sz.width / 2, c.x));
    c.y = MAX(ins.top + sz.height / 2, MIN(b.size.height - ins.bottom - sz.height / 2, c.y));
    return c;
}
- (void)dragBubble:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.view]; [g setTranslation:CGPointZero inView:self.view];
    CGPoint c = CGPointMake(g.view.center.x + d.x, g.view.center.y + d.y);
    g.view.center = [self clamp:c size:g.view.bounds.size];
}
- (void)dragPanel:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.view]; [g setTranslation:CGPointZero inView:self.view];
    CGPoint c = CGPointMake(self.panel.center.x + d.x, self.panel.center.y + d.y);
    self.panel.center = [self clamp:c size:self.panel.bounds.size];
}
- (void)toggle {
    if (self.panel.hidden) {
        CGPoint c = CGPointMake(self.bubble.center.x + 23 + self.panel.bounds.size.width / 2 + 8, self.bubble.center.y + self.panel.bounds.size.height / 2 - 23);
        if (c.x + self.panel.bounds.size.width / 2 > self.view.bounds.size.width)
            c.x = self.bubble.center.x - 23 - self.panel.bounds.size.width / 2 - 8;
        self.panel.center = [self clamp:c size:self.panel.bounds.size];
    }
    self.panel.hidden = !self.panel.hidden;
}
@end

@interface SEQOverlay : NSObject @end
static SEQWindow *gWin;

@implementation SEQOverlay
+ (void)show {
    if (gWin) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; }
    gWin = scene ? [[SEQWindow alloc] initWithWindowScene:scene]
                 : [[SEQWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    gWin.frame = UIScreen.mainScreen.bounds;
    gWin.windowLevel = UIWindowLevelAlert + 1000;
    gWin.backgroundColor = UIColor.clearColor;
    gWin.rootViewController = [SEQVC new];
    gWin.hidden = NO;
}
@end
