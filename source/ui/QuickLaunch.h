/*---------------------------------------------------------------------------------------------
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#pragma once
#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

typedef void (^QuickLaunchChangedBlock)(void);

@interface QuickLaunch : NSObject
{
    NSView *_parentView;
    NSMutableArray *_bundleIDs;     // NSString bundle identifiers
    NSMutableArray *_buttons;       // HoverButton, parallel to _bundleIDs
    int _startX;
    int _height;
    int _dragIndex;                 // index of currently-dragged button, or -1
    CGFloat _dragOffsetX;           // cursor offset within button at drag start
    QuickLaunchChangedBlock _onChanged;
}

-(id)initWithParentView:(NSView*)parent startX:(int)x height:(int)h onChanged:(QuickLaunchChangedBlock)cb;
-(BOOL)pinBundleID:(NSString*)bundleID;
-(BOOL)unpinBundleID:(NSString*)bundleID;
-(BOOL)isPinned:(NSString*)bundleID;
-(int)totalWidth;
-(void)setStartX:(int)x;

@end
