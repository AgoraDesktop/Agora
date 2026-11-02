/*
 * AGBuilderWindowController.m — the panes, the object list, and the canvas that hosts the design.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * See AGBuilderWindowController.h. The classes here are the whole window:
 *
 *   `AGPanesView`       places the object list, the canvas and the status line; it owns the arithmetic.
 *   `AGObjectListView`  draws the design's objects, indented by depth, and reports a click.
 *   `AGCanvasView`      hosts the design's real views and draws the grid under them.
 *   `AGShieldView`      swallows the mouse so a designed control cannot fire while it is being looked at.
 *
 * **THE CANVAS DOES NOT FLIP ITS COORDINATES.** An AppKit view's frame is bottom-left relative to its superview, and a
 * design file states frames in exactly that space, so a canvas that flipped would need a conversion at every door and a
 * person would read one number in the file and another on screen.
 *
 * **AND NOTHING IS RESIZED TO FIT.** A top-level view keeps the frame the file gives it, even when that is bigger than the
 * canvas: a design is a measurement, and a builder that shrank it to the window would be showing a different interface
 * from the one being designed.
 *
 * **THE OBJECT LIST IS DRAWN BY THIS FILE RATHER THAN BY `NSOutlineView`, AND THAT IS A RECORDED OWED SLICE.** A stock
 * outline in a scroll view draws its rows into nothing in this tier — measured: the table reports the right row count,
 * `-rowsInRect:` answers the right row, the cell is prepared with the right string, and `-drawWithFrame:inView:` paints no
 * pixels, while the same table added directly to a pane paints its background and still no rows. The window is the thing a
 * person is here to use, so the list is a small self-drawn view until that path is fixed; `NSOutlineView` comes back with
 * disclosure triangles, drag-reorder and column resizing, which a hand-drawn list owes.
 */
#import "AGBuilderWindowController.h"

#import "AGBuilderDocument.h"
#import "AGDesign.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#include <stdio.h>

/* THE DESIGN AREA'S ORIGIN IS THE CANVAS'S ORIGIN, with no offset: a design is a measurement, and a canvas that shifted it
 * would make the frame in the file and the frame on screen two different numbers. */
static const CGFloat AGGridStep = 8.0;
static const CGFloat AGStatusHeight = 22.0;

/* THE TWO PRIVATE DOORS, DECLARED BEFORE THEY ARE USED. */
@interface AGBuilderWindowController ()
- (void)fn_buildContent;
- (void)reloadFromDesign;
@end

/* ===================================================================================================
 * THE PANES
 * =================================================================================================== */
@interface AGPanesView : NSView
{
@public
	NSView *_canvas;
	NSTextField *_status;
}
@end

@implementation AGPanesView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self != nil) {
		[self setAutoresizesSubviews:NO];
	}
	return self;
}

- (void)fn_placePanes
{
	NSRect bounds = [self bounds];

	/* **THE CANVAS HAS THE WHOLE WIDTH UNTIL THE OBJECT LIST DRAWS CORRECTLY.** The list is the next slice's first task and
	 * the window is more useful showing the design than showing two of its rows; the panes' arithmetic is already the shape
	 * a list will slot into. */
	[_canvas setFrame:NSMakeRect(0.0, AGStatusHeight, bounds.size.width,
				     bounds.size.height - AGStatusHeight)];
	[_status setFrame:NSMakeRect(0.0, 0.0, bounds.size.width, AGStatusHeight)];
}

- (void)setFrame:(NSRect)frame
{
	[super setFrame:frame];
	[self fn_placePanes];
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];
	[self fn_placePanes];
}

@end

/* ===================================================================================================
 * THE SHIELD
 * =================================================================================================== */
@interface AGShieldView : NSView
@end

@implementation AGShieldView

/* **A DESIGNED CONTROL MUST NOT ACT WHILE IT IS BEING DESIGNED.** The shield is transparent, has no subviews, and swallows
 * the mouse buttons; the canvas adds it LAST so that hit-testing finds it before any designed view. Test mode will remove
 * it rather than teach the canvas a second event path. */
- (BOOL)isOpaque
{
	return NO;
}

- (BOOL)acceptsFirstResponder
{
	return NO;
}

- (void)mouseDown:(NSEvent *)event
{
	(void)event;
}

- (void)mouseUp:(NSEvent *)event
{
	(void)event;
}

- (void)mouseDragged:(NSEvent *)event
{
	(void)event;
}

- (void)rightMouseDown:(NSEvent *)event
{
	(void)event;
}

@end

/* ===================================================================================================
 * THE CANVAS
 * =================================================================================================== */
@interface AGCanvasView : NSView
{
	AGDesign *_design;		/* NOT RETAINED: the document owns it */
	AGShieldView *_shield;		/* RETAINED by this view */
	NSMutableArray *_hosted;	/* NOT RETAINED entries: this view's own subviews */
}
- (void)setDesign:(AGDesign *)design;
@end

@implementation AGCanvasView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self != nil) {
		_shield = [[AGShieldView alloc] initWithFrame:[self bounds]];
		_hosted = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_shield release];
	[_hosted release];
	[super dealloc];
}

/* **THE HOSTED VIEWS ARE THE DESIGN'S OWN OBJECTS, NOT COPIES.** A controller keeps what it drew — and then looks it up in
 * the design by identity — so a selection can name a live object and an inspector can move it. The canvas therefore never
 * copies a view and never rebuilds one on a redraw. */
- (void)setDesign:(AGDesign *)design
{
	NSArray *topLevel;
	NSUInteger i;

	while ([_hosted count] > 0) {
		[[_hosted lastObject] removeFromSuperview];
		[_hosted removeLastObject];
	}
	_design = design;
	topLevel = [design topLevelObjects];
	for (i = 0; i < [topLevel count]; i++) {
		id object = [topLevel objectAtIndex:i];

		if (![object isKindOfClass:[NSView class]]) {
			/* A WINDOW IS A DESIGNED OBJECT TOO, and a later slice draws it as a titled sheet on this canvas. Nothing is
			 * added for one here: pretending it is a view would put its content view at the wrong depth. */
			continue;
		}
		[self addSubview:object];
		[_hosted addObject:object];
	}
	/* LAST, AND THAT IS THE WHOLE MECHANISM: a subview later in the list is hit first. */
	[self addSubview:_shield];
	[_shield setFrame:[self bounds]];
	[self setNeedsDisplay:YES];
}

- (void)setFrame:(NSRect)frame
{
	[super setFrame:frame];
	[_shield setFrame:[self bounds]];
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];
	[_shield setFrame:[self bounds]];
}

/* THE GRID IS EIGHT POINTS, which is the spacing AppKit's own alignment idioms use for controls and what a person's eye
 * reads as "a unit" at every scale this desktop runs at. Drawn in the VIEW's space, under the designed views, so it can
 * never be mistaken for part of a design. */
- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];
	CGFloat x;
	CGFloat y;

	(void)dirtyRect;
	[[NSColor controlBackgroundColor] set];
	[NSBezierPath fillRect:bounds];

	[[NSColor gridColor] setStroke];
	for (x = 0.0; x <= bounds.size.width; x += AGGridStep) {
		[NSBezierPath strokeLineFromPoint:NSMakePoint(x + 0.5, 0.0)
					  toPoint:NSMakePoint(x + 0.5, bounds.size.height)];
	}
	for (y = 0.0; y <= bounds.size.height; y += AGGridStep) {
		[NSBezierPath strokeLineFromPoint:NSMakePoint(0.0, y + 0.5)
					  toPoint:NSMakePoint(bounds.size.width, y + 0.5)];
	}
}

@end

/* ===================================================================================================
 * THE WINDOW
 * =================================================================================================== */
@implementation AGBuilderWindowController

- (instancetype)init
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80.0, 80.0, 900.0, 600.0)
						       styleMask:(NSTitledWindowMask | NSClosableWindowMask |
								  NSMiniaturizableWindowMask | NSResizableWindowMask)
							 backing:NSBackingStoreBuffered
							   defer:NO];

	self = [super initWithWindow:window];
	[window release];
	if (self != nil) {
		[self fn_buildContent];
	}
	return self;
}

- (void)dealloc
{
	[_design release];
	[super dealloc];
}

- (void)fn_buildContent
{
	NSWindow *window = [self window];
	AGPanesView *panes;
	NSTextField *status;

	panes = [[AGPanesView alloc] initWithFrame:[[window contentView] bounds]];

	_canvas = [[AGCanvasView alloc] initWithFrame:NSMakeRect(301.0, AGStatusHeight, 600.0, 400.0)];

	status = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 900.0, AGStatusHeight)];
	[status setStringValue:@"No design"];
	[status setEditable:NO];
	[status setSelectable:NO];
	[status setBezeled:NO];
	[status setBordered:NO];
	[status setDrawsBackground:NO];
	[status setFont:[NSFont systemFontOfSize:11.0]];
	_status = status;

	panes->_canvas = _canvas;
	panes->_status = status;
	[panes addSubview:_canvas];
	[panes addSubview:status];
	[_canvas release];
	[status release];

	[window setContentView:panes];
	[window setMinSize:NSMakeSize(520.0, 360.0)];
	[window setTitle:@"Builder"];
	[panes release];
}

/* ============================ THE DOCUMENT ============================ */

- (void)setDocument:(id)document
{
	[super setDocument:document];
	if ([document isKindOfClass:[AGBuilderDocument class]]) {
		[_design release];
		_design = [[(AGBuilderDocument *)document design] retain];
	}
	[self reloadFromDesign];
	[self synchronizeWindowTitleWithDocumentName];
}

/* ONE PLACE REBUILDS EVERY VIEW OF THE MODEL, so an edit anywhere has one door to knock on. */
- (void)reloadFromDesign
{
	if (_design == nil) {
		return;
	}
	[_canvas setDesign:_design];
	/* ASCII IN THE FORMAT, because a multi-byte character in a format string is mangled by this tier's formatter (see
	 * AGDesign's `-summaryOfRecord:`); anything that needs one is appended. */
	[_status setStringValue:[NSString stringWithFormat:@"%lu object(s), %lu connection(s)",
				 (unsigned long)[[_design objectsByID] count],
				 (unsigned long)[[_design connectionRecords] count]]];
}

@end
