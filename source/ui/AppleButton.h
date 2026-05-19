/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Nicolas Jinchereau. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

#pragma once
#include <iostream>
#include <Foundation/Foundation.h>
#include <Cocoa/Cocoa.h>
#include <AppKit/AppKit.h>
#include <ui/HoverButton.h>
using namespace std;

@interface AppleButton : HoverButton
{
    NSMenu *_currentMenu;
}
- (id)initWithFrame:(NSRect)frame;
- (void)toggleStartMenu;
- (void)onClickToggleFastDock:(NSEvent*)theEvent;
- (void)onClickToggleCmdTap:(NSEvent*)theEvent;
- (void)onClickedQuit:(NSEvent*)theEvent;
- (void)onClickEditShortcuts:(NSEvent*)theEvent;
@end
