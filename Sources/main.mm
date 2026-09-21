#import <AppKit/AppKit.h>

#include "GitTracker.hpp"
#include "ReportFormatter.hpp"
#include "TimeLog.hpp"

#include <chrono>
#include <string>

namespace {

constexpr CGFloat kWindowWidth = 820.0;
constexpr CGFloat kWindowHeight = 590.0;
NSString* const kTargetDirectoryDefaultsKey = @"TargetGitDirectory";

NSColor* color(const CGFloat red, const CGFloat green, const CGFloat blue,
               const CGFloat alpha = 1.0) {
    return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0
                                blue:blue / 255.0 alpha:alpha];
}

std::string utf8String(NSString* value) {
    return value == nil ? std::string{} : std::string(value.fileSystemRepresentation);
}

NSString* nativeString(const std::string& value) {
    NSString* string = [NSString stringWithUTF8String:value.c_str()];
    return string == nil ? @"" : string;
}

NSString* formatPuertoRicoTime(const timelogger::Timestamp timestamp) {
    const auto seconds = std::chrono::duration<double>(timestamp.time_since_epoch()).count();
    NSDate* date = [NSDate dateWithTimeIntervalSince1970:seconds];

    static NSDateFormatter* formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithName:@"America/Puerto_Rico"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return [formatter stringFromDate:date];
}

void copyToClipboard(NSString* value) {
    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:value forType:NSPasteboardTypeString];
}

NSTextField* makeLabel(NSString* value, const CGFloat size, const NSFontWeight weight,
                       NSColor* textColor) {
    NSTextField* label = [NSTextField labelWithString:value];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = textColor;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

NSView* makeCard() {
    NSView* card = [[NSView alloc] initWithFrame:NSZeroRect];
    card.wantsLayer = YES;
    card.layer.backgroundColor = color(24.0, 28.0, 37.0).CGColor;
    card.layer.borderColor = color(255.0, 255.0, 255.0, 0.08).CGColor;
    card.layer.borderWidth = 1.0;
    card.layer.cornerRadius = 14.0;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    return card;
}

NSButton* makeActionButton(NSString* title, id target, SEL action, NSColor* fillColor) {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    button.font = [NSFont systemFontOfSize:16.0 weight:NSFontWeightBold];
    button.bordered = NO;
    button.contentTintColor = NSColor.whiteColor;
    button.wantsLayer = YES;
    button.layer.backgroundColor = fillColor.CGColor;
    button.layer.cornerRadius = 11.0;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return button;
}

NSButton* makeSecondaryButton(NSString* title, id target, SEL action) {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    button.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    button.bordered = NO;
    button.contentTintColor = color(218.0, 224.0, 238.0);
    button.wantsLayer = YES;
    button.layer.backgroundColor = color(43.0, 49.0, 62.0).CGColor;
    button.layer.borderColor = color(255.0, 255.0, 255.0, 0.10).CGColor;
    button.layer.borderWidth = 1.0;
    button.layer.cornerRadius = 9.0;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant:38.0].active = YES;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:162.0].active = YES;
    return button;
}

void setButtonEnabled(NSButton* button, const BOOL enabled) {
    button.enabled = enabled;
    button.layer.opacity = enabled ? 1.0F : 0.34F;
}

NSView* makeTimeCard(NSString* title, NSTextField** valueField) {
    NSView* card = makeCard();
    NSTextField* titleLabel = makeLabel(title, 11.0, NSFontWeightBold,
                                        color(139.0, 148.0, 169.0));
    NSTextField* value = makeLabel(@"Not logged yet", 21.0, NSFontWeightMedium,
                                   color(240.0, 243.0, 249.0));
    value.font = [NSFont monospacedDigitSystemFontOfSize:21.0 weight:NSFontWeightMedium];
    value.selectable = YES;
    *valueField = value;

    [card addSubview:titleLabel];
    [card addSubview:value];
    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:112.0],
        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:18.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [value.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [value.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-20.0],
        [value.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20.0],
    ]];
    return card;
}

} // namespace

@interface TimeLoggerAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation TimeLoggerAppDelegate {
    NSWindow* _window;
    NSTextField* _timeInField;
    NSTextField* _timeOutField;
    NSTextField* _repositoryField;
    NSTextField* _statusField;
    NSTextField* _statusDot;
    NSButton* _chooseDirectoryButton;
    NSButton* _copyReportButton;
    NSString* _selectedDirectory;
    timelogger::TimeLog _timeLog;
}

- (void)showError:(NSString*)message {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Time Logger";
    alert.informativeText = message;
    [alert beginSheetModalForWindow:_window completionHandler:nil];
}

- (void)setStatus:(NSString*)text color:(NSColor*)statusColor {
    _statusField.stringValue = text;
    _statusDot.textColor = statusColor;
}

- (void)setSelectedDirectory:(NSString*)directory {
    _selectedDirectory = [directory copy];
    if (_selectedDirectory.length == 0) {
        _repositoryField.stringValue = @"No repository selected";
        return;
    }
    _repositoryField.stringValue = _selectedDirectory;
    [NSUserDefaults.standardUserDefaults setObject:_selectedDirectory
                                            forKey:kTargetDirectoryDefaultsKey];
}

- (void)installMainMenu {
    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem* applicationMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                                 action:nil
                                                          keyEquivalent:@""];
    [mainMenu addItem:applicationMenuItem];
    NSMenu* applicationMenu = [[NSMenu alloc] initWithTitle:@"Time Logger"];
    NSMenuItem* quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Time Logger"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [applicationMenu addItem:quitItem];
    applicationMenuItem.submenu = applicationMenu;
    NSApp.mainMenu = mainMenu;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;
    [self installMainMenu];

    const NSRect frame = NSMakeRect(0.0, 0.0, kWindowWidth, kWindowHeight);
    const NSWindowStyleMask style = NSWindowStyleMaskTitled |
                                    NSWindowStyleMaskClosable |
                                    NSWindowStyleMaskMiniaturizable |
                                    NSWindowStyleMaskResizable |
                                    NSWindowStyleMaskFullSizeContentView;
    _window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
                                            backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"Time Logger";
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    _window.backgroundColor = color(12.0, 15.0, 21.0);
    _window.delegate = self;
    _window.minSize = NSMakeSize(720.0, 560.0);
    _window.movableByWindowBackground = YES;
    [_window center];

    NSView* root = [[NSView alloc] initWithFrame:frame];
    root.wantsLayer = YES;
    root.layer.backgroundColor = color(12.0, 15.0, 21.0).CGColor;
    _window.contentView = root;

    NSTextField* appTitle = makeLabel(@"Time Logger", 28.0, NSFontWeightBold,
                                      color(245.0, 247.0, 252.0));
    NSTextField* subtitle = makeLabel(@"Turn focused work into a Git activity report",
                                      14.0, NSFontWeightRegular,
                                      color(136.0, 146.0, 166.0));
    NSStackView* titleStack = [NSStackView stackViewWithViews:@[appTitle, subtitle]];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 3.0;

    NSTextField* versionBadge = makeLabel(@"v1.7.1  •  GIT REPORTS", 11.0,
                                          NSFontWeightBold, color(151.0, 165.0, 255.0));
    versionBadge.alignment = NSTextAlignmentCenter;
    versionBadge.wantsLayer = YES;
    versionBadge.layer.backgroundColor = color(105.0, 118.0, 255.0, 0.13).CGColor;
    versionBadge.layer.borderColor = color(124.0, 137.0, 255.0, 0.28).CGColor;
    versionBadge.layer.borderWidth = 1.0;
    versionBadge.layer.cornerRadius = 11.0;
    [versionBadge.widthAnchor constraintEqualToConstant:142.0].active = YES;
    [versionBadge.heightAnchor constraintEqualToConstant:28.0].active = YES;

    NSView* headerSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
    NSStackView* header = [NSStackView stackViewWithViews:@[titleStack, headerSpacer, versionBadge]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;

    NSView* repositoryCard = makeCard();
    NSTextField* repositoryTitle = makeLabel(@"TRACKED GIT DIRECTORY", 11.0,
                                              NSFontWeightBold, color(139.0, 148.0, 169.0));
    _repositoryField = makeLabel(@"No repository selected", 14.0,
                                 NSFontWeightMedium, color(230.0, 233.0, 241.0));
    _repositoryField.font = [NSFont monospacedSystemFontOfSize:14.0
                                                        weight:NSFontWeightMedium];
    _repositoryField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _repositoryField.selectable = YES;
    _chooseDirectoryButton = makeSecondaryButton(@"CHOOSE DIRECTORY", self,
                                                  @selector(selectGitDirectory:));
    [repositoryCard addSubview:repositoryTitle];
    [repositoryCard addSubview:_repositoryField];
    [repositoryCard addSubview:_chooseDirectoryButton];
    [NSLayoutConstraint activateConstraints:@[
        [repositoryCard.heightAnchor constraintEqualToConstant:82.0],
        [repositoryTitle.topAnchor constraintEqualToAnchor:repositoryCard.topAnchor constant:16.0],
        [repositoryTitle.leadingAnchor constraintEqualToAnchor:repositoryCard.leadingAnchor constant:20.0],
        [_repositoryField.leadingAnchor constraintEqualToAnchor:repositoryCard.leadingAnchor constant:20.0],
        [_repositoryField.trailingAnchor constraintLessThanOrEqualToAnchor:_chooseDirectoryButton.leadingAnchor constant:-18.0],
        [_repositoryField.bottomAnchor constraintEqualToAnchor:repositoryCard.bottomAnchor constant:-16.0],
        [_chooseDirectoryButton.trailingAnchor constraintEqualToAnchor:repositoryCard.trailingAnchor constant:-16.0],
        [_chooseDirectoryButton.centerYAnchor constraintEqualToAnchor:repositoryCard.centerYAnchor],
    ]];

    NSView* timeInCard = makeTimeCard(@"START TIME  •  PUERTO RICO", &_timeInField);
    NSView* timeOutCard = makeTimeCard(@"END TIME  •  PUERTO RICO", &_timeOutField);
    NSStackView* timeRow = [NSStackView stackViewWithViews:@[timeInCard, timeOutCard]];
    timeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    timeRow.distribution = NSStackViewDistributionFillEqually;
    timeRow.spacing = 14.0;

    NSButton* startButton = makeActionButton(@"▶  START WORK", self, @selector(startWork:),
                                             color(92.0, 80.0, 210.0));
    startButton.keyEquivalent = @"\r";
    NSButton* endButton = makeActionButton(@"■  END WORK", self, @selector(endWork:),
                                           color(49.0, 57.0, 72.0));
    NSStackView* actionRow = [NSStackView stackViewWithViews:@[startButton, endButton]];
    actionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actionRow.distribution = NSStackViewDistributionFillEqually;
    actionRow.spacing = 14.0;

    _copyReportButton = makeActionButton(@"COPY GIT REPORT", self, @selector(copyReport:),
                                         color(36.0, 166.0, 131.0));
    setButtonEnabled(_copyReportButton, NO);

    _statusDot = makeLabel(@"●", 12.0, NSFontWeightBold, color(111.0, 222.0, 177.0));
    _statusField = makeLabel(@"Select a Git directory to begin.", 13.0,
                             NSFontWeightMedium, color(156.0, 165.0, 184.0));
    NSStackView* statusRow = [NSStackView stackViewWithViews:@[_statusDot, _statusField]];
    statusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusRow.alignment = NSLayoutAttributeCenterY;
    statusRow.spacing = 8.0;

    NSStackView* content = [NSStackView stackViewWithViews:@[
        header, repositoryCard, timeRow, actionRow, _copyReportButton, statusRow
    ]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeCenterX;
    content.spacing = 16.0;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:root.topAnchor constant:56.0],
        [content.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:36.0],
        [content.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-36.0],
        [content.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-28.0],
        [header.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [repositoryCard.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [timeRow.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [actionRow.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [_copyReportButton.widthAnchor constraintEqualToAnchor:content.widthAnchor],
    ]];

    NSString* savedDirectory = [NSUserDefaults.standardUserDefaults stringForKey:kTargetDirectoryDefaultsKey];
    if (savedDirectory.length > 0) {
        const auto error = timelogger::GitTracker::validateDirectory(utf8String(savedDirectory));
        if (error.empty()) {
            [self setSelectedDirectory:savedDirectory];
            [self setStatus:@"Ready to track Git commits." color:color(111.0, 222.0, 177.0)];
        }
    }

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)selectGitDirectory:(id)sender {
    (void)sender;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Choose a Git directory to track";
    panel.prompt = @"Select";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = NO;
    if ([panel runModal] != NSModalResponseOK) {
        return;
    }

    NSString* directory = panel.URL.path;
    const auto error = timelogger::GitTracker::validateDirectory(utf8String(directory));
    if (!error.empty()) {
        [self showError:nativeString(error)];
        return;
    }
    [self setSelectedDirectory:directory];
    [self setStatus:@"Ready to track Git commits." color:color(111.0, 222.0, 177.0)];
}

- (void)startWork:(id)sender {
    (void)sender;
    const auto directory = utf8String(_selectedDirectory);
    if (const auto error = timelogger::GitTracker::validateDirectory(directory); !error.empty()) {
        [self showError:nativeString(error)];
        return;
    }

    const auto now = std::chrono::system_clock::now();
    _timeLog.startWork(now, directory);
    NSString* value = formatPuertoRicoTime(now);
    _timeInField.stringValue = value;
    _timeOutField.stringValue = @"Not logged yet";
    setButtonEnabled(_copyReportButton, NO);
    setButtonEnabled(_chooseDirectoryButton, NO);
    [self setStatus:@"Tracking commits in the selected directory…" color:color(255.0, 191.0, 94.0)];
    copyToClipboard(value);
}

- (void)endWork:(id)sender {
    (void)sender;
    if (!_timeLog.timeIn().has_value()) {
        [self showError:@"Start work before ending the session."];
        return;
    }

    const auto now = std::chrono::system_clock::now();
    _timeLog.endWork(now);
    NSString* value = formatPuertoRicoTime(now);
    _timeOutField.stringValue = value;
    setButtonEnabled(_copyReportButton, YES);
    setButtonEnabled(_chooseDirectoryButton, YES);
    [self setStatus:@"Session complete — your Git report is ready."
              color:color(111.0, 222.0, 177.0)];
    copyToClipboard(value);
}

- (void)copyReport:(id)sender {
    (void)sender;
    if (!_timeLog.isComplete()) {
        [self showError:@"Complete a work session before copying its report."];
        return;
    }

    const auto result = timelogger::GitTracker::commitsBetween(
        _timeLog.targetDirectory(), *_timeLog.timeIn(), *_timeLog.timeOut());
    if (!result.succeeded()) {
        [self showError:nativeString(result.error)];
        return;
    }

    const auto report = timelogger::formatReport(
        result.commits, *_timeLog.timeIn(), *_timeLog.timeOut());
    copyToClipboard(nativeString(report));
    if (result.commits.empty()) {
        [self setStatus:@"Report copied — no commits in this session."
                  color:color(126.0, 141.0, 255.0)];
    } else {
        NSString* message = [NSString stringWithFormat:@"Copied %lu commit%@ to the clipboard.",
            static_cast<unsigned long>(result.commits.size()),
            result.commits.size() == 1 ? @"" : @"s"];
        [self setStatus:message color:color(126.0, 141.0, 255.0)];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

@end

int main(int argc, const char* argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication* application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyRegular;
        TimeLoggerAppDelegate* delegate = [[TimeLoggerAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
