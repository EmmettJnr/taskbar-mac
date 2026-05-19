/*---------------------------------------------------------------------------------------------
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#include <ui/QuickLaunch.h>
#include <ui/HoverButton.h>
#include <ui/MenuHelpers.h>

#define QL_BTN_SIZE     32
#define QL_BTN_SPACING  0

static NSString * const kPinnedAppsKey = @"PinnedApps";

@implementation QuickLaunch

-(id)initWithParentView:(NSView*)parent startX:(int)x height:(int)h onChanged:(QuickLaunchChangedBlock)cb
{
    self = [super init];
    if(self)
    {
        _parentView = [parent retain];
        _bundleIDs = [[NSMutableArray alloc] init];
        _buttons = [[NSMutableArray alloc] init];
        _startX = x;
        _height = h;
        _dragIndex = -1;
        _dragOffsetX = 0;
        _onChanged = [cb copy];

        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kPinnedAppsKey];
        for(NSString *bid in saved)
        {
            if([bid isKindOfClass:[NSString class]])
                [self addBundleID:bid persist:NO];
        }
        [self layout];
    }
    return self;
}

-(void)dealloc
{
    for(HoverButton *b in _buttons)
        [b removeFromSuperview];
    [_buttons release];
    [_bundleIDs release];
    [_parentView release];
    [_onChanged release];
    [super dealloc];
}

-(NSURL*)urlForBundleID:(NSString*)bundleID
{
    return [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleID];
}

-(NSImage*)iconForBundleID:(NSString*)bundleID
{
    NSURL *url = [self urlForBundleID:bundleID];
    if(!url) return nil;
    return [[NSWorkspace sharedWorkspace] iconForFile:[url path]];
}

-(NSString*)displayNameForBundleID:(NSString*)bundleID
{
    NSURL *url = [self urlForBundleID:bundleID];
    if(!url) return bundleID;
    return [[NSFileManager defaultManager] displayNameAtPath:[url path]];
}

-(BOOL)isPinned:(NSString*)bundleID
{
    return bundleID && [_bundleIDs containsObject:bundleID];
}

// Internal: append a bundle ID, build its button, optionally persist.
-(void)addBundleID:(NSString*)bundleID persist:(BOOL)persist
{
    if([self isPinned:bundleID]) return;

    NSImage *icon = [self iconForBundleID:bundleID];
    if(!icon)
        return; // app not installed; skip silently

    [_bundleIDs addObject:bundleID];

    HoverButton *btn = [[HoverButton alloc] initWithFrame:NSMakeRect(0, 0, QL_BTN_SIZE, _height) title:@""];
    [btn setImage:icon];
    [btn setImagePosition:NSImageOnly];
    [btn setReorderDragEnabled:YES];

    NSString *capturedID = [bundleID retain];
    QuickLaunch *weakSelf = self; // QuickLaunch outlives all its buttons

    btn.leftClickAction = ^(NSEvent *event) {
        [weakSelf launchBundleID:capturedID];
    };

    btn.reorderDragAction = ^(NSEvent *event) {
        [weakSelf handleDragForID:capturedID event:event ended:NO];
    };
    btn.reorderDragEnded = ^(NSEvent *event) {
        [weakSelf handleDragForID:capturedID event:event ended:YES];
    };

    btn.rightClickAction = ^(NSEvent *event) {
        NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"QuickLaunchMenu"] autorelease];

        auto openAction = [=]() {
            [weakSelf launchBundleID:capturedID];
        };
        auto unpinAction = [=]() {
            [weakSelf unpinBundleID:capturedID];
        };

        [menu addItem:[ActionItem itemWithTitle:@"Open" action:openAction]];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[ActionItem itemWithTitle:@"Unpin from Quick Launch" action:unpinAction]];
        [menu addItem:[ForceMenuPos forcePosItem:[NSEvent mouseLocation] level:NSDockWindowLevel + 1]];

        [NSMenu popUpContextMenu:menu withEvent:event forView:btn];
    };

    // The capturedID retain above is intentionally leaked into the blocks for their lifetime.
    // It will be released when the button (and its blocks) are dealloc'd in unpin/dealloc.

    [_parentView addSubview:btn];
    [_buttons addObject:btn];
    [btn release];

    if(persist) [self save];
}

-(BOOL)pinBundleID:(NSString*)bundleID
{
    if(!bundleID || [self isPinned:bundleID]) return NO;
    NSUInteger before = [_bundleIDs count];
    [self addBundleID:bundleID persist:YES];
    if([_bundleIDs count] == before) return NO; // skipped (e.g. icon failed to resolve)
    [self layout];
    if(_onChanged) _onChanged();
    return YES;
}

-(BOOL)unpinBundleID:(NSString*)bundleID
{
    NSUInteger idx = [_bundleIDs indexOfObject:bundleID];
    if(idx == NSNotFound) return NO;

    HoverButton *btn = [_buttons objectAtIndex:idx];
    [btn removeFromSuperview];
    [_buttons removeObjectAtIndex:idx];
    [_bundleIDs removeObjectAtIndex:idx];

    [self save];
    [self layout];
    if(_onChanged) _onChanged();
    return YES;
}

-(int)totalWidth
{
    NSUInteger n = [_buttons count];
    if(n == 0) return 0;
    return (int)(n * QL_BTN_SIZE + (n - 1) * QL_BTN_SPACING);
}

-(void)setStartX:(int)x
{
    if(_startX == x) return;
    _startX = x;
    [self layout];
}

-(void)layout
{
    int x = _startX;
    for(HoverButton *b in _buttons)
    {
        [b setFrame:NSMakeRect(x, 0, QL_BTN_SIZE, _height)];
        x += QL_BTN_SIZE + QL_BTN_SPACING;
    }
}

-(void)handleDragForID:(NSString*)bundleID event:(NSEvent*)event ended:(BOOL)ended
{
    NSUInteger idx = [_bundleIDs indexOfObject:bundleID];
    if(idx == NSNotFound) return;

    HoverButton *btn = [_buttons objectAtIndex:idx];

    if(_dragIndex == -1)
    {
        _dragIndex = (int)idx;
        NSPoint pInWindow = [event locationInWindow];
        NSPoint pInParent = [_parentView convertPoint:pInWindow fromView:nil];
        _dragOffsetX = pInParent.x - btn.frame.origin.x;
        // raise dragged button above its siblings
        [_parentView addSubview:btn positioned:NSWindowAbove relativeTo:nil];
    }

    NSPoint pInWindow = [event locationInWindow];
    NSPoint pInParent = [_parentView convertPoint:pInWindow fromView:nil];
    CGFloat newX = pInParent.x - _dragOffsetX;

    int n = (int)[_buttons count];
    int firstX = _startX;
    int lastX  = _startX + (n - 1) * (QL_BTN_SIZE + QL_BTN_SPACING);
    if(newX < firstX) newX = firstX;
    if(newX > lastX)  newX = lastX;

    NSRect f = btn.frame;
    f.origin.x = newX;
    [btn setFrame:f];

    // Pick target index from cursor center vs button-grid midpoints
    int cursorOffset = (int)(pInParent.x - _startX);
    int targetIdx = cursorOffset / (QL_BTN_SIZE + QL_BTN_SPACING);
    if(targetIdx < 0) targetIdx = 0;
    if(targetIdx >= n) targetIdx = n - 1;

    if(targetIdx != _dragIndex)
    {
        [_bundleIDs exchangeObjectAtIndex:_dragIndex withObjectAtIndex:targetIdx];
        [_buttons   exchangeObjectAtIndex:_dragIndex withObjectAtIndex:targetIdx];
        _dragIndex = targetIdx;

        // re-layout all non-dragged buttons to grid
        int x = _startX;
        for(int i = 0; i < n; i++)
        {
            HoverButton *b = [_buttons objectAtIndex:i];
            if(i != _dragIndex)
                [b setFrame:NSMakeRect(x, 0, QL_BTN_SIZE, _height)];
            x += QL_BTN_SIZE + QL_BTN_SPACING;
        }
    }

    if(ended)
    {
        int gridX = _startX + _dragIndex * (QL_BTN_SIZE + QL_BTN_SPACING);
        [btn setFrame:NSMakeRect(gridX, 0, QL_BTN_SIZE, _height)];
        _dragIndex = -1;
        [self save];
    }
}

-(void)save
{
    [[NSUserDefaults standardUserDefaults] setObject:[NSArray arrayWithArray:_bundleIDs] forKey:kPinnedAppsKey];
}

-(void)launchBundleID:(NSString*)bundleID
{
    NSURL *url = [self urlForBundleID:bundleID];
    if(!url) return;

    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:url
                                          configuration:cfg
                                      completionHandler:^(NSRunningApplication * _Nullable app, NSError * _Nullable error) {
        // best-effort; ignore errors
    }];
}

@end
