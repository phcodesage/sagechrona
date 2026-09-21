#import <AppKit/AppKit.h>

#include "GitTracker.hpp"
#include "ReportFormatter.hpp"
#include "TimeLog.hpp"

#include <chrono>
#include <string>

namespace {

constexpr CGFloat kWindowWidth = 820.0;
constexpr CGFloat kWindowHeight = 640.0;
NSString* const kTargetDirectoryDefaultsKey = @"TargetGitDirectory";
NSString* const kTimeZoneDefaultsKey = @"ReportTimeZone";

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

NSString* formatTime(const timelogger::Timestamp timestamp, NSString* timeZoneName) {
    const auto seconds = std::chrono::duration<double>(timestamp.time_since_epoch()).count();
    NSDate* date = [NSDate dateWithTimeIntervalSince1970:seconds];

    static NSDateFormatter* formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    formatter.timeZone = [NSTimeZone timeZoneWithName:timeZoneName];
    return [formatter stringFromDate:date];
}

timelogger::Timestamp timestampFromDate(NSDate* date) {
    const auto duration = std::chrono::duration<double>(date.timeIntervalSince1970);
    return timelogger::Timestamp{
        std::chrono::duration_cast<timelogger::Timestamp::duration>(duration)
    };
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
    NSButton* _startButton;
    NSButton* _earlierButton;
    NSButton* _endButton;
    NSComboBox* _timeZonePicker;
    NSString* _selectedDirectory;
    NSString* _sessionTimeZone;
    timelogger::TimeLog _timeLog;
}

- (void)showError:(NSString*)message {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"SageChrona";
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

- (NSString*)selectedTimeZoneName {
    NSString* value = [_timeZonePicker.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [NSTimeZone timeZoneWithName:value] == nil ? nil : value;
}

- (void)timeZoneChanged:(id)sender {
    (void)sender;
    NSString* timeZoneName = [self selectedTimeZoneName];
    if (timeZoneName == nil) {
        [self setStatus:@"Choose a valid IANA timezone from the list."
                  color:color(255.0, 122.0, 122.0)];
        return;
    }
    [NSUserDefaults.standardUserDefaults setObject:timeZoneName forKey:kTimeZoneDefaultsKey];
    [self setStatus:@"Timezone saved. Ready to track Git commits."
              color:color(111.0, 222.0, 177.0)];
}

- (void)installMainMenu {
    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem* applicationMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                                 action:nil
                                                          keyEquivalent:@""];
    [mainMenu addItem:applicationMenuItem];
    NSMenu* applicationMenu = [[NSMenu alloc] initWithTitle:@"SageChrona"];
    NSMenuItem* quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit SageChrona"
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
    _window.title = @"SageChrona";
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    _window.backgroundColor = color(12.0, 15.0, 21.0);
    _window.delegate = self;
    _window.minSize = NSMakeSize(720.0, 610.0);
    _window.movableByWindowBackground = YES;
    [_window center];

    NSView* root = [[NSView alloc] initWithFrame:frame];
    root.wantsLayer = YES;
    root.layer.backgroundColor = color(12.0, 15.0, 21.0).CGColor;
    _window.contentView = root;

    NSTextField* appTitle = makeLabel(@"SageChrona", 28.0, NSFontWeightBold,
                                      color(245.0, 247.0, 252.0));
    NSTextField* subtitle = makeLabel(@"Developer timekeeping, powered by Git",
                                      14.0, NSFontWeightRegular,
                                      color(136.0, 146.0, 166.0));
    NSStackView* titleStack = [NSStackView stackViewWithViews:@[appTitle, subtitle]];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 3.0;

    NSTextField* versionBadge = makeLabel(@"BY PHCODESAGE", 11.0,
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
    NSBox* settingsDivider = [[NSBox alloc] initWithFrame:NSZeroRect];
    settingsDivider.boxType = NSBoxSeparator;
    settingsDivider.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField* timeZoneTitle = makeLabel(@"REPORT TIMEZONE", 11.0,
                                           NSFontWeightBold, color(139.0, 148.0, 169.0));
    _timeZonePicker = [[NSComboBox alloc] initWithFrame:NSZeroRect];
    _timeZonePicker.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    _timeZonePicker.completes = YES;
    _timeZonePicker.numberOfVisibleItems = 12;
    _timeZonePicker.hasVerticalScroller = YES;
    _timeZonePicker.target = self;
    _timeZonePicker.action = @selector(timeZoneChanged:);
    _timeZonePicker.translatesAutoresizingMaskIntoConstraints = NO;
    [_timeZonePicker addItemsWithObjectValues:NSTimeZone.knownTimeZoneNames];
    [repositoryCard addSubview:repositoryTitle];
    [repositoryCard addSubview:_repositoryField];
    [repositoryCard addSubview:_chooseDirectoryButton];
    [repositoryCard addSubview:settingsDivider];
    [repositoryCard addSubview:timeZoneTitle];
    [repositoryCard addSubview:_timeZonePicker];
    [NSLayoutConstraint activateConstraints:@[
        [repositoryCard.heightAnchor constraintEqualToConstant:130.0],
        [repositoryTitle.topAnchor constraintEqualToAnchor:repositoryCard.topAnchor constant:14.0],
        [repositoryTitle.leadingAnchor constraintEqualToAnchor:repositoryCard.leadingAnchor constant:20.0],
        [_repositoryField.leadingAnchor constraintEqualToAnchor:repositoryCard.leadingAnchor constant:20.0],
        [_repositoryField.trailingAnchor constraintLessThanOrEqualToAnchor:_chooseDirectoryButton.leadingAnchor constant:-18.0],
        [_repositoryField.topAnchor constraintEqualToAnchor:repositoryTitle.bottomAnchor constant:5.0],
        [_chooseDirectoryButton.trailingAnchor constraintEqualToAnchor:repositoryCard.trailingAnchor constant:-16.0],
        [_chooseDirectoryButton.topAnchor constraintEqualToAnchor:repositoryCard.topAnchor constant:15.0],
        [settingsDivider.leadingAnchor constraintEqualToAnchor:repositoryCard.leadingAnchor constant:20.0],
        [settingsDivider.trailingAnchor constraintEqualToAnchor:repositoryCard.trailingAnchor constant:-20.0],
        [settingsDivider.topAnchor constraintEqualToAnchor:repositoryCard.topAnchor constant:73.0],
        [timeZoneTitle.leadingAnchor constraintEqualToAnchor:repositoryCard.leadingAnchor constant:20.0],
        [timeZoneTitle.centerYAnchor constraintEqualToAnchor:_timeZonePicker.centerYAnchor],
        [_timeZonePicker.trailingAnchor constraintEqualToAnchor:repositoryCard.trailingAnchor constant:-16.0],
        [_timeZonePicker.bottomAnchor constraintEqualToAnchor:repositoryCard.bottomAnchor constant:-12.0],
        [_timeZonePicker.widthAnchor constraintEqualToConstant:280.0],
        [_timeZonePicker.heightAnchor constraintEqualToConstant:34.0],
    ]];

    NSView* timeInCard = makeTimeCard(@"START TIME", &_timeInField);
    NSView* timeOutCard = makeTimeCard(@"END TIME", &_timeOutField);
    NSStackView* timeRow = [NSStackView stackViewWithViews:@[timeInCard, timeOutCard]];
    timeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    timeRow.distribution = NSStackViewDistributionFillEqually;
    timeRow.spacing = 14.0;

    _startButton = makeActionButton(@"▶  START NOW", self, @selector(startWork:),
                                    color(92.0, 80.0, 210.0));
    _startButton.keyEquivalent = @"\r";
    _earlierButton = makeActionButton(@"◷  STARTED EARLIER…", self,
                                      @selector(startedEarlier:),
                                      color(48.0, 57.0, 76.0));
    _endButton = makeActionButton(@"■  END WORK", self, @selector(endWork:),
                                  color(49.0, 57.0, 72.0));
    setButtonEnabled(_endButton, NO);
    NSStackView* actionRow = [NSStackView stackViewWithViews:@[
        _startButton, _earlierButton, _endButton
    ]];
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

    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSString* savedDirectory = [defaults stringForKey:kTargetDirectoryDefaultsKey];
    BOOL migratedLegacySettings = NO;
    if (savedDirectory.length == 0) {
        NSUserDefaults* legacyDefaults = [[NSUserDefaults alloc]
            initWithSuiteName:@"com.local.timelogger"];
        savedDirectory = [legacyDefaults stringForKey:kTargetDirectoryDefaultsKey];
        migratedLegacySettings = savedDirectory.length > 0;
    }
    if (savedDirectory.length > 0) {
        const auto error = timelogger::GitTracker::validateDirectory(utf8String(savedDirectory));
        if (error.empty()) {
            [self setSelectedDirectory:savedDirectory];
            [self setStatus:@"Ready to track Git commits." color:color(111.0, 222.0, 177.0)];
        }
    }

    NSString* savedTimeZone = [defaults stringForKey:kTimeZoneDefaultsKey];
    if ([NSTimeZone timeZoneWithName:savedTimeZone] == nil) {
        savedTimeZone = migratedLegacySettings
            ? @"America/Puerto_Rico"
            : NSTimeZone.localTimeZone.name;
    }
    _timeZonePicker.stringValue = savedTimeZone;
    [defaults setObject:savedTimeZone forKey:kTimeZoneDefaultsKey];

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
    NSString* timeZoneName = [self selectedTimeZoneName];
    if (timeZoneName == nil) {
        [self showError:@"Choose a valid timezone before starting work."];
        return;
    }

    const auto now = std::chrono::system_clock::now();
    _timeLog.startWork(now, directory);
    _sessionTimeZone = [timeZoneName copy];
    [NSUserDefaults.standardUserDefaults setObject:_sessionTimeZone forKey:kTimeZoneDefaultsKey];
    NSString* value = formatTime(now, _sessionTimeZone);
    _timeInField.stringValue = value;
    _timeOutField.stringValue = @"Not logged yet";
    setButtonEnabled(_copyReportButton, NO);
    setButtonEnabled(_chooseDirectoryButton, NO);
    _timeZonePicker.enabled = NO;
    setButtonEnabled(_startButton, NO);
    setButtonEnabled(_earlierButton, NO);
    setButtonEnabled(_endButton, YES);
    [self setStatus:@"Tracking commits in the selected directory…" color:color(255.0, 191.0, 94.0)];
    copyToClipboard(value);
}

- (void)startedEarlier:(id)sender {
    (void)sender;
    const auto directory = utf8String(_selectedDirectory);
    if (const auto error = timelogger::GitTracker::validateDirectory(directory); !error.empty()) {
        [self showError:nativeString(error)];
        return;
    }
    NSString* timeZoneName = [self selectedTimeZoneName];
    if (timeZoneName == nil) {
        [self showError:@"Choose a valid timezone before selecting a start time."];
        return;
    }

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"When did you start working?";
    alert.informativeText = [NSString stringWithFormat:
        @"Choose the actual start date and time in %@.", timeZoneName];
    [alert addButtonWithTitle:@"Start Tracking"];
    [alert addButtonWithTitle:@"Cancel"];

    NSDatePicker* picker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0.0, 0.0, 330.0, 34.0)];
    picker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    picker.datePickerElements = NSDatePickerElementFlagYearMonthDay |
                                NSDatePickerElementFlagHourMinuteSecond;
    picker.timeZone = [NSTimeZone timeZoneWithName:timeZoneName];
    picker.dateValue = [NSDate dateWithTimeIntervalSinceNow:-3600.0];
    picker.maxDate = NSDate.date;
    alert.accessoryView = picker;

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    if ([picker.dateValue compare:NSDate.date] == NSOrderedDescending) {
        [self showError:@"The start time cannot be in the future."];
        return;
    }

    const auto selectedTime = timestampFromDate(picker.dateValue);
    _timeLog.startWork(selectedTime, directory);
    _sessionTimeZone = [timeZoneName copy];
    [NSUserDefaults.standardUserDefaults setObject:_sessionTimeZone forKey:kTimeZoneDefaultsKey];
    NSString* value = formatTime(selectedTime, _sessionTimeZone);
    _timeInField.stringValue = value;
    _timeOutField.stringValue = @"Not logged yet";
    setButtonEnabled(_copyReportButton, NO);
    setButtonEnabled(_chooseDirectoryButton, NO);
    _timeZonePicker.enabled = NO;
    setButtonEnabled(_startButton, NO);
    setButtonEnabled(_earlierButton, NO);
    setButtonEnabled(_endButton, YES);
    [self setStatus:@"Tracking from the selected earlier start time…"
              color:color(255.0, 191.0, 94.0)];
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
    NSString* value = formatTime(now, _sessionTimeZone);
    _timeOutField.stringValue = value;
    setButtonEnabled(_copyReportButton, YES);
    setButtonEnabled(_chooseDirectoryButton, YES);
    _timeZonePicker.enabled = YES;
    setButtonEnabled(_startButton, YES);
    setButtonEnabled(_earlierButton, YES);
    setButtonEnabled(_endButton, NO);
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
