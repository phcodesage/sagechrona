#import <AppKit/AppKit.h>

#include "TimeLog.hpp"

#include <chrono>

namespace {

constexpr CGFloat kWindowWidth = 900.0;
constexpr CGFloat kWindowHeight = 340.0;
constexpr CGFloat kFontSize = 24.0;

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

NSTextField* makeDisplayField(NSString* value) {
    NSTextField* field = [NSTextField labelWithString:value];
    field.font = [NSFont systemFontOfSize:kFontSize];
    field.alignment = NSTextAlignmentCenter;
    field.selectable = YES;
    field.bezeled = YES;
    field.drawsBackground = YES;
    field.backgroundColor = NSColor.textBackgroundColor;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:54.0].active = YES;
    return field;
}

NSButton* makeButton(NSString* title, id target, SEL action) {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    button.font = [NSFont systemFontOfSize:kFontSize weight:NSFontWeightSemibold];
    button.bezelStyle = NSBezelStyleRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:48.0].active = YES;
    return button;
}

} // namespace

@interface TimeLoggerAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation TimeLoggerAppDelegate {
    NSWindow* _window;
    NSTextField* _timeInField;
    NSTextField* _timeOutField;
    timelogger::TimeLog _timeLog;
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
                                    NSWindowStyleMaskResizable;

    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"Time Logger v1.6";
    _window.delegate = self;
    _window.minSize = NSMakeSize(560.0, 320.0);
    [_window center];

    _timeInField = makeDisplayField(@"Time In: Not logged yet");
    _timeOutField = makeDisplayField(@"Time Out: Not logged yet");

    NSButton* startButton = makeButton(@"START WORK", self, @selector(startWork:));
    startButton.keyEquivalent = @"\r";
    NSButton* endButton = makeButton(@"END WORK", self, @selector(endWork:));

    NSStackView* stack = [NSStackView stackViewWithViews:@[
        _timeInField, _timeOutField, startButton, endButton
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 14.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView* contentView = _window.contentView;
    [contentView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24.0],
        [stack.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [_timeInField.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_timeOutField.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [startButton.widthAnchor constraintGreaterThanOrEqualToConstant:230.0],
        [endButton.widthAnchor constraintGreaterThanOrEqualToConstant:230.0],
    ]];

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)startWork:(id)sender {
    (void)sender;
    const auto now = std::chrono::system_clock::now();
    _timeLog.startWork(now);
    NSString* value = formatPuertoRicoTime(now);
    _timeInField.stringValue = [@"Time In: " stringByAppendingString:value];
    copyToClipboard(value);
}

- (void)endWork:(id)sender {
    (void)sender;
    const auto now = std::chrono::system_clock::now();
    _timeLog.endWork(now);
    NSString* value = formatPuertoRicoTime(now);
    _timeOutField.stringValue = [@"Time Out: " stringByAppendingString:value];
    copyToClipboard(value);
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
