/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Nicolas Jinchereau. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#include <Foundation/Foundation.h>
#include <unistd.h>
#include <mach/task.h>
#include <ui/AppleButton.h>
#include <ui/StartMenu.h>
#include <ui/ShortcutsWindow.h>
#include <ui/MenuHelpers.h>
#include <ui/Utils.h>

@implementation AppleButton

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame title:nil];
    
    if(self)
    {
        [self setToolTip:@"Click Me"];
        [[self hoverButtonCell] setImage:[NSImage imageNamed:@"AppleLogo.png"]];
        [[self hoverButtonCell] setHotImage:[NSImage imageNamed:@"AppleLogoHighlighted.png"]];
        [[self hoverButtonCell] setImagePosition:NSImageOnly];
        
        self.leftClickAction = [=](NSEvent *theEvent){
            [self toggleStartMenu];
        };
        
        self.rightClickAction = [=](NSEvent *theEvent){
            NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Start Menu Right"] autorelease];
        
            struct task_basic_info info;
            mach_msg_type_number_t size = sizeof(info);
            kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
        
            if(kerr == KERN_SUCCESS)
            {
                float memoryUsage = (float)(info.resident_size / 1024) / 1024.0f;
                NSString *itemText = [NSString stringWithFormat:@"%f MB in use", memoryUsage];
                [menu insertItemWithTitle:itemText action:nil keyEquivalent:@"" atIndex:0];
            }
            else
            {
                [menu insertItemWithTitle:@"Could not determine memory usage." action:nil keyEquivalent:@"" atIndex:0];
            }

            [menu insertItemWithTitle:@"Toggle Fast Dock" action:@selector(onClickToggleFastDock:) keyEquivalent:@"" atIndex:1];
            NSMenuItem *cmdTapItem = [menu insertItemWithTitle:@"Toggle Start Menu with ⌘ Tap" action:@selector(onClickToggleCmdTap:) keyEquivalent:@"" atIndex:2];
            [cmdTapItem setState:Utils.isCmdTapToggleEnabled ? NSControlStateValueOn : NSControlStateValueOff];
            [menu insertItemWithTitle:@"Edit Shortcuts" action:@selector(onClickEditShortcuts:) keyEquivalent:@"" atIndex:3];
            [menu insertItemWithTitle:@"Quit Taskbar" action:@selector(onClickedQuit:) keyEquivalent:@"" atIndex:4];
            [menu addItem:[ForceMenuPos forcePosItem:[NSEvent mouseLocation] level:NSDockWindowLevel + 1]];
        
            [NSMenu popUpContextMenu:menu withEvent:theEvent forView:self];
        };
    }
    
    return self;
}

-(void)dealloc
{
    [_currentMenu release];
    [super dealloc];
}

- (void)toggleStartMenu
{
    if(_currentMenu)
    {
        [_currentMenu cancelTracking];
        return;
    }

    NSMenu *menu = [StartMenu rootMenu:self];
    _currentMenu = [menu retain];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 32) inView:self];
    [_currentMenu release];
    _currentMenu = nil;
}

- (void)onClickToggleFastDock:(NSEvent*)theEvent {
    [Utils enableFastDock: !Utils.isFastDockEnabled];
}

- (void)onClickToggleCmdTap:(NSEvent*)theEvent {
    [Utils enableCmdTapToggle: !Utils.isCmdTapToggleEnabled];
}

- (void)onClickEditShortcuts:(NSEvent*)theEvent
{
    ShortcutsWindow *win = [[ShortcutsWindow alloc] init];
    [NSApp runModalForWindow:win];
}

- (void)onClickedQuit:(NSEvent*)theEvent
{
    [[NSApplication sharedApplication] terminate:nil];
}

@end
