/*
 * main.m — the entry point: the menu bar, the document to open, and the loop.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 *   Builder [--seconds N] [design.agnib]
 *
 * **THE FILE MENU IS WIRED RATHER THAN LEFT TO THE RESPONDER CHAIN, AND THAT IS THIS TIER'S OWN DETAIL.** `NSDocument`
 * implements the save and close verbs and `NSDocumentController` implements new and open, but neither is an `NSResponder`,
 * so neither is in the chain a nil-targeted menu item walks (key window's first responder → window → application). The
 * chain is still the right answer for a DESIGNED control — a menu row a view owns — so the File rows name a small
 * controller that forwards to the document controller, and Edit keeps nil targets because those verbs belong to whatever
 * is being edited.
 *
 * `--seconds` is a TEST'S door, the same one Workspace's and Dock's entry points have: an application is a thing that
 * stays, and a suite needs it to be able to leave.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSError.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ===================================================================================================
 * THE FILE VERBS
 * =================================================================================================== */
@interface AGBuilderAppController : NSObject
- (void)newDocument:(id)sender;
- (void)openDocument:(id)sender;
- (void)saveDocument:(id)sender;
- (void)saveDocumentAs:(id)sender;
- (void)closeDocument:(id)sender;
@end

@implementation AGBuilderAppController

- (NSDocumentController *)fn_documentController
{
	return [NSDocumentController sharedDocumentController];
}

- (void)newDocument:(id)sender
{
	[[self fn_documentController] newDocument:sender];
}

- (void)openDocument:(id)sender
{
	[[self fn_documentController] openDocument:sender];
}

/* **THE VERBS ARE ANSWERED BY THE CURRENT DOCUMENT, NOT STORED HERE.** A controller that remembered "the" document would be
 * wrong the moment a second one opened; `-currentDocument` asks the key window, which is the same rule the menu bar
 * follows. */
- (void)saveDocument:(id)sender
{
	[[[self fn_documentController] currentDocument] saveDocument:sender];
}

- (void)saveDocumentAs:(id)sender
{
	[[[self fn_documentController] currentDocument] saveDocumentAs:sender];
}

- (void)closeDocument:(id)sender
{
	[[[self fn_documentController] currentDocument] close];
}

@end

/* ===================================================================================================
 * THE MENU BAR
 * =================================================================================================== */

/* **EVERY TOP-LEVEL ITEM IS A TITLE WHOSE CONTENT IS A SUBMENU** — a bare title with an action is a flat row of commands
 * pretending to be a menu bar, which is what Terminal's entry point records having produced once. */
static NSMenuItem *fn_bar_title(NSString *title, NSMenu *submenu)
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];

	[item setSubmenu:submenu];
	return [item autorelease];
}

static NSMenuItem *fn_row(NSMenu *menu, NSString *title, SEL action, id target, NSString *key, NSUInteger mask)
{
	NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:(key != nil) ? key : @""];

	[item setTarget:target];
	if (key != nil) {
		[item setKeyEquivalentModifierMask:mask];
	}
	return item;
}

static void fn_install_menu(NSApplication *application, AGBuilderAppController *controller)
{
	NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
	NSMenu *app = [[NSMenu alloc] initWithTitle:@"Builder"];
	NSMenu *file = [[NSMenu alloc] initWithTitle:@"File"];
	NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
	NSMenu *window = [[NSMenu alloc] initWithTitle:@"Window"];
	NSUInteger command = NSCommandKeyMask;
	NSUInteger commandShift = NSCommandKeyMask | NSShiftKeyMask;

	fn_row(app, @"About Builder", @selector(orderFrontStandardAboutPanel:), application, nil, 0);
	[app addItem:[NSMenuItem separatorItem]];
	fn_row(app, @"Hide Builder", @selector(hide:), application, @"h", command);
	[app addItem:[NSMenuItem separatorItem]];
	fn_row(app, @"Quit Builder", @selector(terminate:), application, @"q", command);

	fn_row(file, @"New", @selector(newDocument:), controller, @"n", command);
	fn_row(file, @"Open…", @selector(openDocument:), controller, @"o", command);
	[file addItem:[NSMenuItem separatorItem]];
	fn_row(file, @"Close", @selector(closeDocument:), controller, @"w", command);
	fn_row(file, @"Save", @selector(saveDocument:), controller, @"s", command);
	fn_row(file, @"Save As…", @selector(saveDocumentAs:), controller, @"S", commandShift);

	/* EDIT KEEPS NIL TARGETS: undo, cut and paste belong to whatever is being edited, which is the rule the whole menu bar
	 * exists to serve. */
	fn_row(edit, @"Undo", @selector(undo:), nil, @"z", command);
	fn_row(edit, @"Redo", @selector(redo:), nil, @"Z", commandShift);
	[edit addItem:[NSMenuItem separatorItem]];
	fn_row(edit, @"Cut", @selector(cut:), nil, @"x", command);
	fn_row(edit, @"Copy", @selector(copy:), nil, @"c", command);
	fn_row(edit, @"Paste", @selector(paste:), nil, @"v", command);
	fn_row(edit, @"Select All", @selector(selectAll:), nil, @"a", command);

	fn_row(window, @"Minimize", @selector(performMiniaturize:), nil, @"m", command);

	[main addItem:fn_bar_title(@"Builder", app)];
	[main addItem:fn_bar_title(@"File", file)];
	[main addItem:fn_bar_title(@"Edit", edit)];
	[main addItem:fn_bar_title(@"Window", window)];
	[application setMainMenu:main];
	[main release];
}

/* ===================================================================================================
 * main
 * =================================================================================================== */
int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *application;
	AGBuilderAppController *controller;
	NSDocumentController *documents;
	NSString *path = nil;
	double seconds = 0.0;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
			seconds = atof(argv[++i]);
		} else if (argv[i][0] == '-') {
			fprintf(stderr, "usage: %s [--seconds N] [design.agnib]\n", argv[0]);
			[pool release];
			return 2;
		} else if (path == nil) {
			path = [NSString stringWithUTF8String:argv[i]];
		} else {
			fprintf(stderr, "usage: %s [--seconds N] [design.agnib]\n", argv[0]);
			[pool release];
			return 2;
		}
	}

	/* **A RELATIVE PATH IS MADE ABSOLUTE BEFORE IT BECOMES A URL.** `-typeForContentsOfURL:` answers from the URL's
	 * extension, and a relative path spelled into a file URL is one this tier's NSURL does not resolve — so
	 * `Builder examples/Panel.agnib` would answer "no document type is registered for (null)" while the same file by
	 * absolute path opens. A command line is a person's shorthand, not a promise that they typed `$PWD`. */
	if (path != nil && ![path isAbsolutePath]) {
		path = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:path];
	}

	application = [NSApplication sharedApplication];
	controller = [[AGBuilderAppController alloc] init];
	/* REGULAR, because this is a document application: it owns the menu bar while it is active, which is the opposite of
	 * the Dock's answer and the reason the policy is set rather than defaulted. */
	[application setActivationPolicy:NSApplicationActivationPolicyRegular];
	fn_install_menu(application, controller);
	[application finishLaunching];

	documents = [NSDocumentController sharedDocumentController];
	if (path != nil) {
		NSError *error = nil;
		NSURL *url = [NSURL fileURLWithPath:path];
		id document = [documents openDocumentWithContentsOfURL:url display:YES error:&error];

		if (document == nil) {
			fprintf(stderr, "builder: %s\n", [[error localizedDescription] UTF8String]);
			[controller release];
			[pool release];
			return 1;
		}
	} else {
		[documents newDocument:controller];
	}

	if (seconds > 0.0) {
		/* A TEST'S LOOP: pump until the deadline, then leave, sending every event through NSApplication so that a
		 * document's own edits and the canvas's redraws travel the path they will in a session. */
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];

		while ([deadline timeIntervalSinceNow] > 0.0) {
			NSEvent *event = [application nextEventMatchingMask:NSAnyEventMask
								  untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
								     inMode:nil
								    dequeue:YES];

			if (event != nil) {
				[application sendEvent:event];
			}
		}
	} else {
		[application run];
	}

	[controller release];
	[pool release];
	return 0;
}
