/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Nicolas Jinchereau. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#include <ui/TaskBarWindow.h>
#include <ui/AppleButton.h>
#include <ui/MenuHelpers.h>
#include <ui/QuickLaunch.h>
#include <ui/HoverButton.h>
#include <ui/Utils.h>
#include <Cocoa/Cocoa.h>
#include <AppKit/AppKit.h>
#include <algorithm>

#define TB_HEIGHT                   32
#define START_BTN_WIDTH             64
#define START_BTN_HEIGHT            32
#define START_BTN_RIGHT_SPACING     0
#define QL_RIGHT_SPACING            8   // gap between quick-launch and window-buttons when quick-launch is non-empty
#define BUTTON_SIZE                 200
#define BUTTON_SPACING              0
#define UPDATE_RATE                 0.1f
#define BUTTON_EXPAND_SPEED         3.0f
#define TRASH_BTN_WIDTH             32
#define SHOW_DESK_BTN_WIDTH         8
#define WINDOWS_RIGHT_SPACING       4   // gap between window-buttons and trash

@interface TaskBarWindow ()
-(void)showDesktop;
-(void)emptyTrash;
-(void)handleModifierEvent:(NSEvent*)event;
-(void)rearmKeyEventTap;
@end

// Thin, near-transparent peek-style button anchored at the far right.
@interface ShowDesktopButton : NSView
{
    BOOL _hot;
    void (^_action)(void);
}
-(id)initWithFrame:(NSRect)frame action:(void(^)(void))action;
@end

@implementation ShowDesktopButton
-(id)initWithFrame:(NSRect)frame action:(void(^)(void))action
{
    self = [super initWithFrame:frame];
    if(self)
    {
        _hot = NO;
        _action = [action copy];
        NSTrackingArea *area = [[NSTrackingArea alloc]
            initWithRect:NSZeroRect
                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                   owner:self userInfo:nil];
        [self addTrackingArea:area];
        [area release];
    }
    return self;
}
-(void)dealloc { [_action release]; [super dealloc]; }
-(void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds];
    if(_hot)
    {
        [[NSColor colorWithWhite:1.0 alpha:0.18] setFill];
        NSRectFillUsingOperation(b, NSCompositingOperationSourceOver);
    }
    // subtle vertical separator on the left edge
    [[NSColor colorWithWhite:0.5 alpha:0.35] setFill];
    NSRectFill(NSMakeRect(0, 4, 1, b.size.height - 8));
}
-(void)mouseEntered:(NSEvent*)e { _hot = YES; [self setNeedsDisplay:YES]; }
-(void)mouseExited:(NSEvent*)e  { _hot = NO;  [self setNeedsDisplay:YES]; }
-(void)mouseDown:(NSEvent*)e    { if(_action) _action(); }
@end

static CGEventRef TaskBarKeyEventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo)
{
    TaskBarWindow *tb = (__bridge TaskBarWindow*)userInfo;
    if(type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput)
    {
        // System disabled our tap (often after a slow callback). Re-enable.
        // Without this the close-on-second-tap stops working after a hiccup.
        [tb rearmKeyEventTap];
        return event;
    }
    NSEvent *nsEvent = [NSEvent eventWithCGEvent:event];
    if(nsEvent)
        [tb handleModifierEvent:nsEvent];
    return event;
}

CVReturn RenderTaskBarButtons(CVDisplayLinkRef displayLink,
                              const CVTimeStamp *inNow,
                              const CVTimeStamp *inOutputTime,
                              CVOptionFlags flagsIn,
                              CVOptionFlags *flagsOut,
                              void *displayLinkContext)
{
    TaskBarWindow *taskbarWindow = (__bridge TaskBarWindow*)displayLinkContext;
    [taskbarWindow performSelectorOnMainThread:@selector(updateAnimation) withObject:nil waitUntilDone:NO];
    return 0;
}

class WindowInfo
{
public:
    WindowInfo(){}
    
    ~WindowInfo() {
        [icon release];
        [app release];
    }
    
    NSRunningApplication *app;
    ax::Window* window;
    uint64_t processId;
    string title;
    NSImage *icon;
    HoverButton *button;
    float currentWidth;
    bool keep;
    bool updateTitle;
    bool unsupported;
};

@implementation TaskBarWindow

-(id)init
{
    rect = [[NSScreen mainScreen] frame];
    rect.origin.x = 0;
    rect.origin.y = 0;
    rect.size.height = TB_HEIGHT;
    
    self = [super initWithContentRect:rect styleMask:NSNonactivatingPanelMask backing:NSBackingStoreBuffered defer:NO];
    [self setDelegate:self];

    _dragWindowIndex = -1;
    _dragOffsetX = 0;

    if(self)
    {
        NSString *title = @"MyTaskbar_865d3ddb-d43b-40f1-bc2d-74fcf3d725e7";
        [self setTitle:title];
        [self setLevel:NSDockWindowLevel + 1];
        [self orderFrontRegardless];
        [self setBackgroundColor:Utils.backgroundColor];
        
        NSRect rc = NSMakeRect(BUTTON_SPACING, 0, START_BTN_WIDTH, START_BTN_HEIGHT);
        _appleButton = [[[AppleButton alloc] initWithFrame:rc] autorelease];
        [[self contentView] addSubview:_appleButton];

        TaskBarWindow *tb = self;

        int qlStartX = BUTTON_SPACING + START_BTN_WIDTH + START_BTN_RIGHT_SPACING;
        _quickLaunch = [[QuickLaunch alloc] initWithParentView:[self contentView]
                                                        startX:qlStartX
                                                        height:TB_HEIGHT
                                                     onChanged:^{ [tb startAnimation]; }];

        // Right-anchored buttons: trash + thin show-desktop strip
        CGFloat barWidth = rect.size.width;
        NSRect showDeskFrame = NSMakeRect(barWidth - SHOW_DESK_BTN_WIDTH, 0, SHOW_DESK_BTN_WIDTH, TB_HEIGHT);
        _showDesktopButton = [[ShowDesktopButton alloc] initWithFrame:showDeskFrame
                                                               action:^{ [tb showDesktop]; }];
        [_showDesktopButton setAutoresizingMask:NSViewMinXMargin];
        [[self contentView] addSubview:_showDesktopButton];

        NSRect trashFrame = NSMakeRect(barWidth - SHOW_DESK_BTN_WIDTH - TRASH_BTN_WIDTH, 0,
                                       TRASH_BTN_WIDTH, TB_HEIGHT);
        _trashButton = [[HoverButton alloc] initWithFrame:trashFrame title:@""];
        NSString *trashPath = [[@"~/.Trash" stringByExpandingTildeInPath] copy];
        NSImage *trashIcon = [[NSWorkspace sharedWorkspace] iconForFile:trashPath];
        [_trashButton setImage:trashIcon];
        [_trashButton setImagePosition:NSImageOnly];
        [_trashButton setAutoresizingMask:NSViewMinXMargin];
        _trashButton.leftClickAction = ^(NSEvent *event) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:trashPath]];
        };
        HoverButton *trashBtn = _trashButton;
        _trashButton.rightClickAction = ^(NSEvent *event) {
            NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"TrashMenu"] autorelease];

            auto openAction = [=]() {
                [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:trashPath]];
            };
            auto emptyAction = [=]() {
                [tb emptyTrash];
            };

            [menu addItem:[ActionItem itemWithTitle:@"Open" action:openAction]];
            [menu addItem:[NSMenuItem separatorItem]];
            [menu addItem:[ActionItem itemWithTitle:@"Empty Trash…" action:emptyAction]];
            [menu addItem:[ForceMenuPos forcePosItem:[NSEvent mouseLocation] level:NSDockWindowLevel + 1]];

            [NSMenu popUpContextMenu:menu withEvent:event forView:trashBtn];
        };
        [[self contentView] addSubview:_trashButton];
        
        NSEventMask eventMask = NSLeftMouseDownMask | NSLeftMouseUpMask;
        
        _mouseEventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:eventMask handler:^(NSEvent *event)
        {
            if(event.type == NSLeftMouseDown)
            {
                if(tb->_cmdHeld) tb->_cmdTapClean = NO;
                [tb globalLeftMouseDown];
            }
            else if(event.type == NSLeftMouseUp)
            {
                [tb globalLeftMouseUp];
            }
        }];

        _cmdHeld = NO;
        _cmdTapClean = NO;
        _cmdDownTime = 0;

        CGEventMask tapMask = CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventKeyDown);
        _keyEventTap = CGEventTapCreate(kCGSessionEventTap,
                                        kCGHeadInsertEventTap,
                                        kCGEventTapOptionListenOnly,
                                        tapMask,
                                        TaskBarKeyEventTapCallback,
                                        (__bridge void*)self);
        if(_keyEventTap)
        {
            _keyEventTapSource = CFMachPortCreateRunLoopSource(NULL, _keyEventTap, 0);
            CFRunLoopAddSource(CFRunLoopGetMain(), _keyEventTapSource, kCFRunLoopCommonModes);
            CGEventTapEnable(_keyEventTap, true);
        }

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
        CVDisplayLinkSetCurrentCGDisplay(displayLink, CGMainDisplayID());
        CVDisplayLinkSetOutputCallback(displayLink, &RenderTaskBarButtons, (void*)self);
    }
    
    return self;
}

- (void)dealloc
{
    [NSEvent removeMonitor:_mouseEventMonitor];
    if(_keyEventTap)
    {
        CGEventTapEnable(_keyEventTap, false);
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _keyEventTapSource, kCFRunLoopCommonModes);
        CFRelease(_keyEventTapSource);
        CFRelease(_keyEventTap);
    }
    CVDisplayLinkRelease(displayLink);
    [_quickLaunch release];
    [_trashButton release];
    [_showDesktopButton release];
    [super dealloc];
}

-(BOOL)canBecomeKeyWindow
{
    return NO;
}

-(BOOL)canBecomeMainWindow
{
    return NO;
}

-(void)globalLeftMouseDown
{
    for(auto& info : _windows)
        [info->button globalLeftMouseDown];
}

-(void)globalLeftMouseUp
{
    for(auto& info : _windows)
        [info->button globalLeftMouseUp];
}

-(void)rearmKeyEventTap
{
    if(_keyEventTap) CGEventTapEnable(_keyEventTap, true);
}

-(void)handleModifierEvent:(NSEvent*)event
{
    if(event.type == NSEventTypeKeyDown)
    {
        if(_cmdHeld) _cmdTapClean = NO;
        return;
    }

    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL cmdNow = (flags & NSEventModifierFlagCommand) != 0;
    BOOL otherModsNow = (flags & ~NSEventModifierFlagCommand) != 0;

    if(cmdNow && !_cmdHeld)
    {
        _cmdHeld = YES;
        _cmdDownTime = [NSDate timeIntervalSinceReferenceDate];
        _cmdTapClean = !otherModsNow;
    }
    else if(!cmdNow && _cmdHeld)
    {
        _cmdHeld = NO;
        NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _cmdDownTime;
        BOOL fire = _cmdTapClean && !otherModsNow && elapsed < 0.3 && Utils.isCmdTapToggleEnabled;
        _cmdTapClean = NO;
        if(fire)
            [_appleButton toggleStartMenu];
    }
    else if(cmdNow && otherModsNow)
    {
        _cmdTapClean = NO;
    }
}

-(void)showDesktop
{
    // Simulate the system "Show Desktop" shortcut (F11 by default in
    // System Settings → Keyboard → Shortcuts → Mission Control).
    // macOS handles the toggle itself: first press slides windows to the
    // screen edges, second press restores them.
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 0x67 /* kVK_F11 */, true);
    CGEventRef keyUp   = CGEventCreateKeyboardEvent(source, 0x67 /* kVK_F11 */, false);
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);
    CFRelease(keyDown);
    CFRelease(keyUp);
    CFRelease(source);
}

-(void)emptyTrash
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Are you sure you want to permanently erase the items in the Trash?"];
    [alert setInformativeText:@"You can't undo this action."];
    [alert addButtonWithTitle:@"Empty Trash"];
    [alert addButtonWithTitle:@"Cancel"];
    [[[alert buttons] objectAtIndex:0] setHasDestructiveAction:YES];

    NSModalResponse response = [alert runModal];
    [alert release];

    if(response == NSAlertFirstButtonReturn)
    {
        NSDictionary *errInfo = nil;
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:@"tell application \"Finder\" to empty trash"];
        NSAppleEventDescriptor *result = [script executeAndReturnError:&errInfo];
        [script release];

        if(!result)
        {
            NSString *msg = [errInfo objectForKey:NSAppleScriptErrorMessage] ?: @"Unknown error.";
            NSNumber *code = [errInfo objectForKey:NSAppleScriptErrorNumber];
            if(code && [code intValue] == -1743)
                msg = @"Taskbar isn't allowed to control Finder. Open System Settings → Privacy & Security → Automation, find Taskbar, and enable Finder.";

            NSAlert *err = [[NSAlert alloc] init];
            [err setMessageText:@"Couldn't empty the Trash"];
            [err setInformativeText:msg];
            [err addButtonWithTitle:@"OK"];
            [err runModal];
            [err release];
        }

        if(result)
            [_trashButton setImage:[NSImage imageNamed:NSImageNameTrashEmpty]];
    }
}

-(void)handleWindowDrag:(ax::Window*)window event:(NSEvent*)event ended:(BOOL)ended
{
    int idx = -1;
    for(int i = 0; i < (int)_windows.size(); i++)
    {
        if(_windows[i]->window == window) { idx = i; break; }
    }
    if(idx < 0) return;

    HoverButton *btn = _windows[idx]->button;
    int n = (int)_windows.size();

    int qlWidth = _quickLaunch ? [_quickLaunch totalWidth] : 0;
    int qlSpace = qlWidth > 0 ? qlWidth + QL_RIGHT_SPACING : 0;
    int windowsBaseX = BUTTON_SPACING + START_BTN_WIDTH + START_BTN_RIGHT_SPACING + qlSpace;

    float usedWidth = (float)windowsBaseX + (float)(max(n - 1, 0)) * BUTTON_SPACING;
    int rightReserve = TRASH_BTN_WIDTH + SHOW_DESK_BTN_WIDTH + WINDOWS_RIGHT_SPACING;
    float availableWidth = [self frame].size.width - usedWidth - rightReserve;
    int maxButtonSize = n > 0 ? (int)(availableWidth / (float)n) : BUTTON_SIZE;
    int perButton = std::min((int)BUTTON_SIZE, maxButtonSize);
    if(perButton < 1) perButton = 1;

    if(_dragWindowIndex == -1)
    {
        _dragWindowIndex = idx;
        NSPoint pInWindow = [event locationInWindow];
        NSPoint pInParent = [[self contentView] convertPoint:pInWindow fromView:nil];
        _dragOffsetX = pInParent.x - btn.frame.origin.x;
        [[self contentView] addSubview:btn positioned:NSWindowAbove relativeTo:nil];
    }

    NSPoint pInWindow = [event locationInWindow];
    NSPoint pInParent = [[self contentView] convertPoint:pInWindow fromView:nil];
    CGFloat newX = pInParent.x - _dragOffsetX;

    int firstX = windowsBaseX;
    int lastX  = windowsBaseX + (n - 1) * (perButton + BUTTON_SPACING);
    if(newX < firstX) newX = firstX;
    if(newX > lastX)  newX = lastX;

    NSRect f = btn.frame;
    f.origin.x = newX;
    [btn setFrame:f];

    int cursorOffset = (int)(pInParent.x - windowsBaseX);
    int targetIdx = cursorOffset / (perButton + BUTTON_SPACING);
    if(targetIdx < 0) targetIdx = 0;
    if(targetIdx >= n) targetIdx = n - 1;

    if(targetIdx != _dragWindowIndex)
    {
        std::swap(_windows[_dragWindowIndex], _windows[targetIdx]);
        _dragWindowIndex = targetIdx;
        [self startAnimation]; // trigger a layout pass for the non-dragged buttons
    }

    if(ended)
    {
        int gridX = windowsBaseX + _dragWindowIndex * (perButton + BUTTON_SPACING);
        [btn setFrame:NSMakeRect(gridX, 0, perButton, TB_HEIGHT)];
        _dragWindowIndex = -1;
        [self startAnimation];
    }
}

-(void)startAnimation
{
    if(!CVDisplayLinkIsRunning(displayLink))
    {
        lastRender = CACurrentMediaTime();
        CVDisplayLinkStart(displayLink);
    }
}

-(void)stopAnimation
{
    if(CVDisplayLinkIsRunning(displayLink))
    {
        CVDisplayLinkStop(displayLink);
    }
}

-(BOOL)isAnimating
{
    return CVDisplayLinkIsRunning(displayLink);
}

- (void)updateWindows:(NSTimer*)timer
{
    rect = [[NSScreen mainScreen] frame];
    rect.origin.x = 0;
    rect.origin.y = 0;
    rect.size.height = TB_HEIGHT;
    
    NSRect currentFrame = [[self contentView] frame];
    NSRect newFrame = [self frameRectForContentRect:rect];
    
    if(!NSEqualRects(currentFrame, newFrame))
    {
        [self setFrame:newFrame display:YES];
    }
}

- (void)updateAnimation
{
    float deltaTime = (float)(CACurrentMediaTime() - lastRender);

    int qlWidth = _quickLaunch ? [_quickLaunch totalWidth] : 0;
    int qlSpace = qlWidth > 0 ? qlWidth + QL_RIGHT_SPACING : 0;
    int windowsBaseX = BUTTON_SPACING + START_BTN_WIDTH + START_BTN_RIGHT_SPACING + qlSpace;

    if(_windows.empty())
    {
        [self stopAnimation];
        return;
    }

    float usedWidth = windowsBaseX;
    usedWidth += (float)(max((int)_windows.size() - 1, 0)) * BUTTON_SPACING;

    int rightReserve = TRASH_BTN_WIDTH + SHOW_DESK_BTN_WIDTH + WINDOWS_RIGHT_SPACING;
    float availableWidth = [self frame].size.width - usedWidth - rightReserve;
    int maxButtonSize = (int)(availableWidth / (float)_windows.size());

    int windowButtonX = windowsBaseX;
    
    bool didUpdateButton = false;

    int i = 0;
    for(auto it = _windows.begin();
             it != _windows.end(); )
    {
        auto &info = (*it);

        if(info->keep)
        {
            if(info->currentWidth < BUTTON_SIZE - 0.1f)
            {
                info->currentWidth = std::min(info->currentWidth
                                   + BUTTON_SIZE * BUTTON_EXPAND_SPEED
                                   * deltaTime, (float)BUTTON_SIZE);
                didUpdateButton = true;
            }
        }
        else
        {
            if(info->currentWidth > 0.1f)
            {
                info->currentWidth = max(info->currentWidth
                                   - (float)BUTTON_SIZE * BUTTON_EXPAND_SPEED
                                   * deltaTime, 0.0f);
                didUpdateButton = true;
            }
        }

        if(info->currentWidth > 0.1f)
        {
            int visibleWidth = min((int)info->currentWidth, maxButtonSize);
            // The dragged button's frame is owned by the drag handler.
            // Still reserve its slot so other buttons flow around it.
            if(i != _dragWindowIndex)
                [info->button setFrame:NSMakeRect(windowButtonX, 0, visibleWidth, TB_HEIGHT)];
            windowButtonX += visibleWidth + BUTTON_SPACING;
            ++it;
            ++i;
        }
        else
        {
            if(i == _dragWindowIndex) _dragWindowIndex = -1;
            else if(_dragWindowIndex > i) _dragWindowIndex--;
            [info->button removeFromSuperview];
            it = _windows.erase(it);
        }
    }
    
    if(!didUpdateButton)
    {
        [self stopAnimation];
    }
}

-(void)mouseDown:(NSEvent *)theEvent
{
    NSPoint mouseLoc = [NSEvent mouseLocation];
    
    CGFloat x = mouseLoc.x;
    CGFloat y = mouseLoc.y;
    
    if(x < START_BTN_WIDTH && y < START_BTN_HEIGHT)
    {
        [_appleButton performClick:nil];
    }
}

-(void)windowDidChangeScreen:(NSNotification*)notification
{
    rect = [[NSScreen mainScreen] frame];
    rect.origin.x = 0;
    rect.origin.y = 0;
    rect.size.height = TB_HEIGHT;
    [self setFrame:rect display:YES];
    [self startAnimation];
    
    for(auto &info : _windows)
        info->window->clipToTaskbar();
}

-(void)clearWindows
{
    for(auto &info : _windows)
        [info->button removeFromSuperview];
    
    _windows.clear();
}

-(void)addWindow:(ax::Window*)window
{
    NSRunningApplication *runningApp = window->app()->runningApplication();
    
    if(!runningApp)
        return;

    int qlWidth = _quickLaunch ? [_quickLaunch totalWidth] : 0;
    int qlSpace = qlWidth > 0 ? qlWidth + QL_RIGHT_SPACING : 0;
    int windowButtonX = BUTTON_SPACING + START_BTN_WIDTH + START_BTN_RIGHT_SPACING + qlSpace;

    for(auto &info : _windows)
        windowButtonX += info->currentWidth + BUTTON_SPACING;
    
    auto info = make_shared<WindowInfo>();
    
    info->app = [runningApp retain];
    info->window = window;
    info->processId = window->app()->processID();
    info->title = window->title();
    info->icon = [[runningApp icon] retain];
    info->keep = true;
    info->updateTitle = false;
    info->unsupported = false;
    info->currentWidth = 0.5f;
    
    NSString *btnText = [NSString stringWithUTF8String:window->title().c_str()];
    
    info->button = [[HoverButton alloc] autorelease];
    [info->button initWithFrame:NSMakeRect(0, 0, 0, 0) title:btnText];
    [info->button setImage:info->icon];
    
    info->button.leftClickAction = [=](NSEvent *event)
    {
        if((event.modifierFlags & NSEventModifierFlagOption) != 0)
            window->maximize();
        else
            window->toggleFocusMinimize();
    };

    [info->button setReorderDragEnabled:YES];
    TaskBarWindow *taskbarSelf = self;
    ax::Window *capturedWindow = window;
    info->button.reorderDragAction = ^(NSEvent *event) {
        [taskbarSelf handleWindowDrag:capturedWindow event:event ended:NO];
    };
    info->button.reorderDragEnded = ^(NSEvent *event) {
        [taskbarSelf handleWindowDrag:capturedWindow event:event ended:YES];
    };
    
    QuickLaunch *quickLaunch = _quickLaunch;
    NSString *bundleID = [[runningApp bundleIdentifier] copy];

    info->button.rightClickAction = [=](NSEvent *event)
    {
        NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"AppMenu"] autorelease];

        auto maximizeAction = [=](){
            window->maximize();
        };

        auto minimizeAction = [=](){
            window->minimize();
        };

        auto closeAction = [=](){
            window->close();
        };

        [menu addItem:[ActionItem itemWithTitle:@"Maximize" action:maximizeAction]];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[ActionItem itemWithTitle:@"Minimize" action:minimizeAction]];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[ActionItem itemWithTitle:@"Close" action:closeAction]];

        if(bundleID && ![quickLaunch isPinned:bundleID])
        {
            [menu addItem:[NSMenuItem separatorItem]];
            auto pinAction = [=](){
                [quickLaunch pinBundleID:bundleID];
            };
            [menu addItem:[ActionItem itemWithTitle:@"Pin to Quick Launch" action:pinAction]];
        }

        [menu addItem:[ForceMenuPos forcePosItem:[NSEvent mouseLocation] level:NSDockWindowLevel + 1]];

        [NSMenu popUpContextMenu:menu withEvent:event forView:info->button];
    };
    
    info->button.dragAction = [=]()
    {
        window->focus();
    };
    
    [[self contentView] addSubview: info->button];
    
    _windows.push_back(info);
    
    [self startAnimation];
}

-(void)removeWindow:(ax::Window*)window
{
    auto it = std::find_if(_windows.begin(), _windows.end(), [window](const shared_ptr<WindowInfo>& info){
        return info->window == window;
    });
    
    if(it != _windows.end())
    {
        (*it)->keep = false;
        (*it)->button.isEnabled = NO;
        [self startAnimation];
    }
}

-(void)renameWindow:(ax::Window*)window
{
    auto it = std::find_if(_windows.begin(), _windows.end(), [window](const shared_ptr<WindowInfo>& info){
        return info->window == window;
    });
    
    if(it != _windows.end())
    {
        (*it)->title = window->title();
        NSString* nsTitle = [NSString stringWithUTF8String:window->title().c_str()];
        [(*it)->button setTitle:nsTitle];
    }
}

-(void)setWindowFocus:(ax::Window*)window focused:(bool)focused
{
    for(auto& win : _windows)
    {
        if(win->window == window) {
            [win->button setFocused:focused];
            break;
        }
    }
}
@end

