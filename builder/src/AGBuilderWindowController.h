/*
 * AGBuilderWindowController.h — the window: the object graph on the left, the live objects on the right.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THIS IS THE WINDOW THE WHOLE APPLICATION IS ABOUT, AND ITS TWO HALVES WILL BE THE SAME FACT SEEN TWICE.** The left half
 * is to be the SOURCE TREE — objects, their classes, their names, and the nesting the file states — because a design is
 * data and a person reviewing a design wants to see the data. The right half is the LIVE GRAPH, the designed views
 * themselves on a canvas, because the only honest preview of an AppKit interface is the AppKit drawing it. The tree is not
 * in the window yet: see the note in the implementation about the two measured defects that keep a list from drawing its
 * rows in this tier, and the canvas holding the whole width until they are fixed.
 *
 * **DESIGN MODE IS A MODE, AND THE SHIELD IS WHAT MAKES IT ONE.** A canvas that hosts real controls would send their real
 * actions when a person clicked to select them, which is why an invisible view sits above the designed hierarchy and
 * swallows the mouse. Dropping the shield is what "Test Interface" will mean, and having it there from the first slice is
 * what keeps the canvas from being rewritten when that slice arrives.
 *
 * **THE WINDOW PLACES ITS OWN PANES, AND THAT IS DELIBERATE.** `NSSplitView` re-places its subviews on its own schedule in
 * this tier and drags its children behind it (Forge records the same finding and answers it the same way), so the geometry
 * lives in one `-fn_placePanes` that runs from `-setFrame:` and `-setFrameSize:`: arithmetic a person can read, and drag
 * dividers named as the next slice rather than pretended away.
 */
#ifndef AGBUILDERWINDOWCONTROLLER_H
#define AGBUILDERWINDOWCONTROLLER_H

#import <AppKit/NSView.h>
#import <AppKit/NSWindowController.h>

@class AGDesign, AGCanvasView, NSTextField;

@interface AGBuilderWindowController : NSWindowController
{
	AGDesign *_design;	/* RETAINED: the document's model, held for the window's lifetime */
	AGCanvasView *_canvas;	/* NOT RETAINED: the pane owns it */
	NSTextField *_status;	/* NOT RETAINED: the window owns it */
}

/* THE DESIGN IS SET THROUGH THE DOCUMENT, not through this initialiser: `NSDocument -addWindowController:` calls
 * `-setDocument:`, which is where the standard lifecycle hands a window its model, its title and its edited state. */
- (instancetype)init;

@end

#endif /* AGBUILDERWINDOWCONTROLLER_H */
