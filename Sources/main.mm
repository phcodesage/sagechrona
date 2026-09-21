#import <AppKit/AppKit.h>

#include "GitTracker.hpp"
#include "ReportFormatter.hpp"
#include "TimeLog.hpp"

#include <chrono>
#include <string>

namespace {

constexpr CGFloat kWindowWidth = 900.0;
constexpr CGFloat kWindowHeight = 560.0;
constexpr CGFloat kFontSize = 24.0;
NSString* const kTargetDirectoryDefaultsKey = @"TargetGitDirectory";

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

NSButton* makeSecondaryButton(NSString* title, id target, SEL action) {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    button.font = [NSFont systemFontOfSize:17.0 weight:NSFontWeightSemibold];
    button.bezelStyle = NSBezelStyleRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:38.0].active = YES;
    return button;
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

- (void)setSelectedDirectory:(NSString*)directory {
    _selectedDirectory = [directory copy];
    if (_selectedDirectory.length == 0) {
        _repositoryField.stringValue = @"Git directory: Not selected";
        return;
    }

    _repositoryField.stringValue = [@"Git directory: " stringByAppendingString:_selectedDirectory];
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
                                    NSWindowStyleMaskResizable;

    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"Time Logger v1.7";
    _window.delegate = self;
    _window.minSize = NSMakeSize(680.0, 500.0);
    [_window center];

    _timeInField = makeDisplayField(@"Time In: Not logged yet");
    _timeOutField = makeDisplayField(@"Time Out: Not logged yet");

    _repositoryField = [NSTextField labelWithString:@"Git directory: Not selected"];
    _repositoryField.font = [NSFont systemFontOfSize:15.0];
    _repositoryField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _repositoryField.selectable = YES;
    _repositoryField.translatesAutoresizingMaskIntoConstraints = NO;

    _statusField = [NSTextField labelWithString:@"Select the Git directory to track."];
    _statusField.font = [NSFont systemFontOfSize:14.0];
    _statusField.textColor = NSColor.secondaryLabelColor;
    _statusField.alignment = NSTextAlignmentCenter;
    _statusField.translatesAutoresizingMaskIntoConstraints = NO;

    _chooseDirectoryButton = makeSecondaryButton(@"SELECT GIT DIRECTORY", self,
                                                  @selector(selectGitDirectory:));

    NSButton* startButton = makeButton(@"START WORK", self, @selector(startWork:));
    startButton.keyEquivalent = @"\r";
    NSButton* endButton = makeButton(@"END WORK", self, @selector(endWork:));
    _copyReportButton = makeButton(@"COPY REPORT", self, @selector(copyReport:));
    _copyReportButton.enabled = NO;

    NSStackView* repositoryRow = [NSStackView stackViewWithViews:@[
        _repositoryField, _chooseDirectoryButton
    ]];
    repositoryRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    repositoryRow.alignment = NSLayoutAttributeCenterY;
    repositoryRow.spacing = 12.0;
    repositoryRow.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView* stack = [NSStackView stackViewWithViews:@[
        repositoryRow, _timeInField, _timeOutField, startButton, endButton,
        _copyReportButton, _statusField
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
        [repositoryRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_timeInField.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_timeOutField.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [startButton.widthAnchor constraintGreaterThanOrEqualToConstant:230.0],
        [endButton.widthAnchor constraintGreaterThanOrEqualToConstant:230.0],
        [_copyReportButton.widthAnchor constraintGreaterThanOrEqualToConstant:230.0],
        [_statusField.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];

    NSString* savedDirectory = [NSUserDefaults.standardUserDefaults
        stringForKey:kTargetDirectoryDefaultsKey];
    if (savedDirectory.length > 0) {
        const auto error = timelogger::GitTracker::validateDirectory(utf8String(savedDirectory));
        if (error.empty()) {
            [self setSelectedDirectory:savedDirectory];
            _statusField.stringValue = @"Ready to track Git commits.";
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
    _statusField.stringValue = @"Ready to track Git commits.";
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
    _timeInField.stringValue = [@"Time In: " stringByAppendingString:value];
    _timeOutField.stringValue = @"Time Out: Not logged yet";
    _copyReportButton.enabled = NO;
    _chooseDirectoryButton.enabled = NO;
    _statusField.stringValue = @"Tracking commits in the selected directory…";
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
    _timeOutField.stringValue = [@"Time Out: " stringByAppendingString:value];
    _copyReportButton.enabled = YES;
    _chooseDirectoryButton.enabled = YES;
    _statusField.stringValue = @"Session complete. Copy the Git report when ready.";
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
        _statusField.stringValue = @"Copied report: no commits in this session.";
    } else {
        _statusField.stringValue = [NSString stringWithFormat:
            @"Copied %lu commit%@ to the clipboard.",
            static_cast<unsigned long>(result.commits.size()),
            result.commits.size() == 1 ? @"" : @"s"];
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
