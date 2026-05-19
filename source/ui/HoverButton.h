/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Nicolas Jinchereau. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#pragma once
#include <iostream>
#include <functional>
#include <Foundation/Foundation.h>
#include <Cocoa/Cocoa.h>
#include <QuartzCore/QuartzCore.h>
#include <QuartzCore/CVDisplayLink.h>
#include <CoreVideo/CoreVideo.h>
#include <ui/Utils.h>
using namespace std;

struct WindowInfo;

@interface HoverButtonCell : NSButtonCell
{
@public bool _hot;
@public bool _focused;
@public bool _down;
    
    NSDictionary *textAttributes;
    NSImage *_hotImage;
    NSGradient* _hotGradient;
    NSGradient* _selectedGradient;
    NSGradient* _pressedGradient;
}
-(void)setHotImage:(NSImage*)image;
@end

@interface HoverButton : NSButton
{
    HoverButtonCell *buttonCell;
    NSTrackingArea *focusTrackingArea;
    function<void(NSEvent*)> _leftClickAction;
    function<void(NSEvent*)> _rightClickAction;
    function<void()> _dragAction;
    function<void(NSEvent*)> _reorderDragAction;
    function<void(NSEvent*)> _reorderDragEnded;
    BOOL _enabled;
    BOOL _reorderDragEnabled;

    NSTimer *_hoverTimer;
    bool _mouseDown;
    bool _leftDown;
    bool _rightDown;
    bool _wasDragged;
    NSPoint _mouseDownPoint;
}
@property function<void(NSEvent*)> leftClickAction;
@property function<void(NSEvent*)> rightClickAction;
@property function<void()> dragAction;
// Reorder-drag callbacks: invoked when the user drags this button beyond a threshold.
// reorderDragAction fires on each mouseDragged; reorderDragEnded fires on mouseUp after a drag.
// When a drag occurs, leftClickAction is suppressed.
@property function<void(NSEvent*)> reorderDragAction;
@property function<void(NSEvent*)> reorderDragEnded;
@property BOOL reorderDragEnabled;
@property BOOL isEnabled;
-(id)initWithFrame:(NSRect)frame title:(NSString*)title;
-(void)setHotImage:(NSImage*)image;
-(void)setTitle:(NSString*)title;
-(void)setFocused:(BOOL)focused;
-(HoverButtonCell*)hoverButtonCell;
// called by TaskBarWindow
-(void)globalLeftMouseDown;
-(void)globalLeftMouseUp;
@end
