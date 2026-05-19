/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Nicolas Jinchereau. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#include <ui/StartMenu.h>
#include <ui/AppleButton.h>
#include <ui/Utils.h>
#include <ui/MenuHelpers.h>
#include <vector>
#include <set>
#include <string>
#include <cstring>

@implementation StartMenu

-(id)initAsRootMenu:(AppleButton*)button
{
    self = [super initWithTitle:@"Start Menu"];
    
    _button = button;
    _rootMenu = self;
    _path = nil;
    
    [self setAutoenablesItems:TRUE];
    
    NSArray* downloadsPath = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES);
    NSArray* documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSMutableArray *shortcuts = [NSMutableArray arrayWithArray:[prefs objectForKey:@"Shortcuts"]];
    NSUInteger shortcutCount = [shortcuts count];
    
    for(size_t i = 0, ct = shortcutCount; i < ct; ++i)
    {
        NSString *shortcut = [shortcuts objectAtIndex:i];
        
        BOOL isDir = NO;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:shortcut isDirectory:&isDir];
        BOOL isPackage = [[NSWorkspace sharedWorkspace] isFilePackageAtPath:shortcut];
        
        if(isDir && !isPackage)
            [self addItem:[StartMenu menuItemForPath:shortcut rootMenu:self largeIcon:YES]];
        else
            [self addItem:[StartMenu menuItemForShortcut:shortcut rootMenu:self]];
    }
    
    if(shortcutCount > 0)
        [self addItem:[NSMenuItem separatorItem]];
    
    [self addItem:[StartMenu menuItemForFile:@"/System/Library/CoreServices/Finder.app" rootMenu:self largeIcon:YES]];
    [self addItem:[StartMenu menuItemForPath:@"/Applications/" rootMenu:self largeIcon:YES]];
    [self addItem:[StartMenu menuItemForPath:[downloadsPath objectAtIndex:0] rootMenu:self largeIcon:YES]];
    [self addItem:[StartMenu menuItemForPath:[documentsPath objectAtIndex:0] rootMenu:self largeIcon:YES]];
    
    [self addItem:[ForceMenuPos forcePosItem:NSMakePoint(0, 32) level:NSDockWindowLevel - 1]];
    
    return self;
}

- (id)initAsSubmenu:(StartMenu*)rootMenu path:(NSString*)path
{
    self = [super initWithTitle:@"Sub Menu"];
    
    _button = rootMenu->_button;
    _rootMenu = rootMenu;
    _path = path;
    
    [self setDelegate:self];
    [self setAutoenablesItems:TRUE];
    
    return self;
}

- (void)dealloc
{
    [_path release];
    [super dealloc];
}

+ (StartMenu*)rootMenu:(AppleButton*)button
{
    return [[[StartMenu alloc] autorelease] initAsRootMenu:button];
}

+ (StartMenu*)menuAsSubmenu:(StartMenu*)rootMenu path:(NSString*)path
{
    return [[[StartMenu alloc] autorelease] initAsSubmenu:rootMenu path:path];
}

+ (NSMenuItem*)menuItemForPath:(NSString*)path rootMenu:(StartMenu*)rootMenu largeIcon:(BOOL)largeIcon
{
    NSString *name = [[path lastPathComponent] stringByDeletingPathExtension];
    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
    
    if(!largeIcon)
        [icon setSize:NSMakeSize(16, 16)];
    
    NSMenuItem *subMenuItem = [[NSMenuItem alloc] autorelease];
    [subMenuItem initWithTitle:name action:@selector(launchItem:) keyEquivalent:@""];
    [subMenuItem setTarget:rootMenu];
    [subMenuItem setRepresentedObject:[NSArray arrayWithObjects:subMenuItem, path, nil]];
    [subMenuItem setImage:icon];
    
    StartMenu *subMenu = [StartMenu menuAsSubmenu:rootMenu path:[path retain]];
    [subMenuItem setSubmenu:subMenu];
    
    return subMenuItem;
}

+ (NSMenuItem*)menuItemForFile:(NSString*)file rootMenu:(StartMenu*)rootMenu largeIcon:(BOOL)largeIcon
{
    NSString *name;
    NSImage *icon;
    
    if([[NSWorkspace sharedWorkspace] isFilePackageAtPath:file])
    {
        name = [[file lastPathComponent] stringByDeletingPathExtension];
        icon = [[NSWorkspace sharedWorkspace] iconForFile:file];
    }
    else
    {
        name = [file lastPathComponent];
        icon = [[NSWorkspace sharedWorkspace] iconForFileType:[file pathExtension]];
    }
    
    if(!largeIcon)
        [icon setSize:NSMakeSize(16, 16)];
    
    NSMenuItem *fileItem = [[NSMenuItem alloc] autorelease];
    [fileItem initWithTitle:name action:@selector(launchItem:) keyEquivalent:@""];
    [fileItem setTarget:rootMenu];
    [fileItem setRepresentedObject:[NSArray arrayWithObjects:fileItem, file, nil]];
    [fileItem setImage:icon];
    
    return fileItem;
}

+ (NSMenuItem*)menuItemForShortcut:(NSString*)shortcut rootMenu:(StartMenu*)rootMenu
{
    NSMenuItem *shortcutItem = [[[NSMenuItem alloc] autorelease] initWithTitle:[Utils titleForPath:shortcut] action:@selector(launchItem:) keyEquivalent:@""];
    
    [shortcutItem setImage:[Utils iconForPath:shortcut]];
    [shortcutItem setTarget:rootMenu];
    [shortcutItem setRepresentedObject:[NSArray arrayWithObjects:shortcut, shortcut, nil]];
    
    return shortcutItem;
}

- (void)launchItem:(id)sender
{
    NSArray *arg = [sender representedObject];
    [[NSWorkspace sharedWorkspace] openFile:[arg objectAtIndex:1]];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem
{
    return YES;
}

- (BOOL)isDirectory:(NSString*)path
{
    BOOL isDir;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    BOOL isPackage = [[NSWorkspace sharedWorkspace] isFilePackageAtPath:path];
    return isDir && !isPackage;
}

- (void)menuNeedsUpdate:(NSMenu*)menu
{
    NSString* rootPath = ((StartMenu*)menu)->_path;
    std::vector<NSString*> dirs;
    std::vector<NSString*> files;
    
    [menu removeAllItems];
    
    NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootPath error:nil];
    
    for(size_t i = 0, ct = [entries count]; i < ct; ++i)
    {
        NSString *entry = [entries objectAtIndex:i];
        
        if([entry isEqualToString:@".DS_Store"] || [entry isEqualToString:@".localized"])
           continue;
        
        NSString *path = [rootPath stringByAppendingPathComponent:entry];
        
        if([self isDirectory:path])
            dirs.push_back(path);
        else
            files.push_back(path);
    }
    
    std::sort(dirs.begin(), dirs.end(), [](NSString* x, NSString* y) {
        return [x compare:y options:(NSCaseInsensitiveSearch | NSForcedOrderingSearch)] == NSOrderedAscending;
    });
    
    std::sort(files.begin(), files.end(), [](NSString* x, NSString* y) {
        return [x compare:y options:(NSCaseInsensitiveSearch | NSForcedOrderingSearch)] == NSOrderedAscending;
    });
    
    for(auto dir : dirs)
    {
        NSMenuItem *subItem = [StartMenu menuItemForPath:dir  rootMenu:self largeIcon:NO];
        [subItem setEnabled:YES];
        [menu addItem:subItem];
    }
    
    for(auto file : files)
    {
        NSMenuItem *subItem = [StartMenu menuItemForFile:file rootMenu:self largeIcon:NO];
        [subItem setEnabled:YES];
        [menu addItem:subItem];
    }
}
@end
