/*
 * main.m — the System UI: the menu that drops from the System menu's square, and the About panel it opens.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 *   SystemUI [--dump-about]
 *
 * **THE SPLIT THIS PROCESS EXISTS FOR IS THE MAC'S.** The window server owns the menu bar's global portion — the strip,
 * the System menu's square and the OS mark inside it — because that is furniture no application owns.
 * `window-server/DESIGN.md` says why: "the System menu is about the SYSTEM rather than about any program — so the
 * server draws it, the server decides how wide it is". BUT A MENU IS NOT A MARK: it is text, a highlight chip, a
 * tracking loop and a dismissal, and all four are the AppKit's. So the menu itself is a client's window, at the
 * pop-up level, composited like every application's — and the server's half of the bargain is one forwarded click
 * (`agora_shell.system_menu_invoked`, version 19; see `AGWindowServerClaimSystemMenu`).
 *
 * **IT IS DELIBERATELY NOT ACTIVATABLE.** It has no menu bar of its own to put in the strip and no business taking the
 * keyboard from the application a person is working in. Every window it shows says so (`-cg_setActivatable:NO`), which
 * is the same rule the Dock's tiles follow — a click on furniture does not move the keyboard.
 *
 * **THE ABOUT PANEL IS THE COMPUTER'S, NOT AN APPLICATION'S.** macOS shows the machine's own summary — OS, CPU, memory,
 * graphics, and what this desktop is — which is why it is here rather than in `WSAboutPanel` (that one is Workspace's
 * own name and version, and it is where a person looking for "About Workspace" goes).
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSWindow.h>
#import <AppKit/platform/AGWindowServer.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimer.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

#if defined(__linux__)
#include <sys/sysinfo.h>
#endif

/* WHICH CHECKOUT THIS BINARY CAME FROM — baked in by the configure, which asks git (see CMakeLists.txt). */
#ifndef AWS_AGORA_VERSION
#define AWS_AGORA_VERSION "unknown"
#endif

/* ============================================================================================ *
 * THE MACHINE'S OWN FACTS                                                                       *
 *                                                                                                *
 * Each of these answers nil when the platform keeps the fact somewhere this build cannot read, and a nil line is
 * simply not shown: a panel that says "0 GB" is worse than one that says nothing. `--dump-about` prints exactly the
 * lines the panel draws, which is what makes them checkable without a session.
 * ============================================================================================ */

/* A LINE FROM A FILE, TRIMMED, ANSWERED AS A STRING. The one reader the four below share. */
static NSString *SYUStringFromFile(const char *path, const char *find)
{
	FILE *file = fopen(path, "r");
	char line[512];
	NSString *answer = nil;

	if (file == NULL) {
		return nil;
	}
	while (fgets(line, sizeof line, file) != NULL) {
		size_t length;

		if (find != NULL && strncmp(line, find, strlen(find)) != 0) {
			continue;
		}
		if (find != NULL) {
			char *value = line + strlen(find);

			while (*value == ' ' || *value == '\t' || *value == ':' || *value == '=') {
				value++;
			}
			memmove(line, value, strlen(value) + 1);
		}
		length = strlen(line);
		while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r' || line[length - 1] == ' ')) {
			line[--length] = '\0';
		}
		answer = [NSString stringWithUTF8String:line];
		break;
	}
	fclose(file);
	return answer;
}

/* THE DISTRO, BY ITS OWN PRETTY NAME — the same file, and the same key, the window server's identity probe reads. */
static NSString *SYUOSLine(void)
{
	NSString *pretty = SYUStringFromFile("/etc/os-release", "PRETTY_NAME=");
	NSString *kernel = SYUStringFromFile("/proc/sys/kernel/osrelease", NULL);

	if (pretty != nil && [pretty hasPrefix:@"\""] && [pretty hasSuffix:@"\""]) {
		pretty = [pretty substringWithRange:NSMakeRange(1, [pretty length] - 2)];
	}
	if (pretty == nil) {
		pretty = SYUStringFromFile("/etc/os-release", "NAME=");
	}
	if (pretty == nil) {
		return [kernel length] > 0 ? [NSString stringWithFormat:@"Linux kernel %@", kernel] : nil;
	}
	return ([kernel length] > 0) ? [NSString stringWithFormat:@"%@ (kernel %@)", pretty, kernel] : pretty;
}

static NSString *SYUCPULine(void)
{
#if defined(__linux__)
	return SYUStringFromFile("/proc/cpuinfo", "model name");
#else
	return nil;
#endif
}

static NSString *SYUMemoryLine(void)
{
#if defined(__linux__)
	struct sysinfo info;

	if (sysinfo(&info) != 0 || info.totalram == 0) {
		return nil;
	}
	{
		/* IN THE UNIT A PERSON BUYS MEMORY IN, and the unit changes at a gibibyte for the reason it does on a Mac. */
		double bytes = (double)info.totalram * (double)info.mem_unit;
		double gib = bytes / (1024.0 * 1024.0 * 1024.0);

		return (gib >= 1.0) ? [NSString stringWithFormat:@"Memory %.1f GB", gib]
				    : [NSString stringWithFormat:@"Memory %.0f MB", bytes / (1024.0 * 1024.0)];
	}
#else
	return nil;
#endif
}

/* **THE CARD IS NAMED BY WHAT THE KERNEL KNOWS ABOUT IT: its driver and its PCI identifier.** A marketing name needs a
 * PCI vendor/device table, which this tree does not carry yet — so the line says what a person can look up rather than
 * guessing at a family. The identifier is what `lspci -nn` prints in brackets. */
static NSString *SYUGraphicsLine(void)
{
	NSString *driver = SYUStringFromFile("/sys/class/drm/card0/device/uevent", "DRIVER=");
	NSString *pci = SYUStringFromFile("/sys/class/drm/card0/device/uevent", "PCI_ID=");

	if (driver == nil && pci == nil) {
		return nil;
	}
	if (driver != nil && pci != nil) {
		return [NSString stringWithFormat:@"Graphics %@, PCI %@", driver, [pci lowercaseString]];
	}
	return [NSString stringWithFormat:@"Graphics %@", (driver != nil) ? driver : [pci lowercaseString]];
}

/* THE DISPLAY THIS SESSION IS ON: its size in points and the panel's honesty about itself, which is the same number the
 * compositor measured and the window server hands every client as `userSpaceScaleFactor`. */
static NSString *SYUDisplayLine(void)
{
	NSScreen *screen = [NSScreen mainScreen];
	NSRect frame;
	CGFloat factor;

	if (screen == nil) {
		return nil;
	}
	frame = [screen frame];
	if (frame.size.width <= 0.0 || frame.size.height <= 0.0) {
		return nil;
	}
	factor = [screen userSpaceScaleFactor];
	return [NSString stringWithFormat:@"Display %.0fx%.0f, %.0f dpi", frame.size.width, frame.size.height,
					 factor * 72.0];
}

/* **THE LINES, IN THE ORDER THE PANEL DRAWS THEM.** The first is `Agora <version>` and is set larger; the rest are the
 * machine. */
static NSArray *SYUAboutLines(void)
{
	NSMutableArray *lines = [NSMutableArray array];
	NSString *values[6];
	int i;

	[lines addObject:[NSString stringWithFormat:@"Agora %s", AWS_AGORA_VERSION]];
	values[0] = SYUOSLine();
	values[1] = SYUCPULine();
	values[2] = SYUMemoryLine();
	values[3] = SYUGraphicsLine();
	values[4] = SYUDisplayLine();
	values[5] = nil;
	for (i = 0; values[i] != nil; i++) {
		[lines addObject:values[i]];
	}
	return lines;
}

/* ============================================================================================ *
 * THE ABOUT PANEL                                                                               *
 *                                                                                                *
 * A titled window at the floating level, drawn by a view rather than assembled from controls: the panel is a fixed
 * list of lines, and one drawing pass is smaller than eight text fields and their layout. A press anywhere on it closes
 * it — it is a statement, not a dialog with a decision to make — and the title bar's close button does the same.
 * ============================================================================================ */

@interface SYUAboutView : NSView
{
	NSArray *_lines;
}
- (id)initWithFrame:(NSRect)frame lines:(NSArray *)lines;
@end

static NSDictionary *SYUTextAttributes(CGFloat size, BOOL bold, NSColor *colour)
{
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
	NSFont *font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];

	if (font != nil) {
		[attributes setObject:font forKey:NSFontAttributeName];
	}
	if (colour != nil) {
		[attributes setObject:colour forKey:NSForegroundColorAttributeName];
	}
	return attributes;
}

@implementation SYUAboutView

- (id)initWithFrame:(NSRect)frame lines:(NSArray *)lines
{
	self = [super initWithFrame:frame];
	if (self != nil) {
		_lines = [lines retain];
	}
	return self;
}

- (void)dealloc
{
	[_lines release];
	[super dealloc];
}

- (BOOL)isOpaque
{
	return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
	const CGFloat padding = 18.0;
	const CGFloat titleSize = 15.0;
	const CGFloat lineSize = 12.0;
	const CGFloat pitch = 17.0;
	NSColor *ink = [NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:1.0];
	NSColor *quiet = [NSColor colorWithCalibratedRed:0.35 green:0.35 blue:0.35 alpha:1.0];
	NSRect bounds = [self bounds];
	CGFloat top = padding + titleSize + 9.0;
	NSUInteger i;

	(void)dirtyRect;
	/* THE FACE IS THE WINDOW'S, DRAWN HERE SO THAT THE PANEL IS ONE COLOUR FROM EDGE TO EDGE — the content view of a
	 * titled window is inset from the frame, and a fill that stopped at the content view would leave a seam. */
	[[NSColor colorWithCalibratedRed:0.929 green:0.929 blue:0.929 alpha:1.0] setFill];
	NSRectFill(bounds);
	/* THE FIRST LINE IS THE TITLE. `drawInRect:` does not honour a paragraph style's alignment in this tier, so every
	 * line is placed at a measured x — the panel is as wide as its longest line, which is what keeps them all left. */
	if ([_lines count] > 0) {
		NSString *title = [_lines objectAtIndex:0];

		[title drawInRect:NSMakeRect(padding, bounds.size.height - padding - ceil(titleSize + 4.0),
					     bounds.size.width - 2.0 * padding, ceil(titleSize + 4.0))
		   withAttributes:SYUTextAttributes(titleSize, YES, ink)];
	}
	for (i = 1; i < [_lines count]; i++) {
		NSString *line = [_lines objectAtIndex:i];
		CGFloat y = bounds.size.height - top - (CGFloat)(i - 1) * pitch - ceil(lineSize + 3.0);

		[line drawInRect:NSMakeRect(padding, y, bounds.size.width - 2.0 * padding, ceil(lineSize + 3.0))
		  withAttributes:SYUTextAttributes(lineSize, NO, quiet)];
	}
}

- (void)mouseDown:(NSEvent *)event
{
	(void)event;
	[[self window] close];
}

@end

/* ============================================================================================ *
 * THE SYSTEM MENU                                                                               *
 * ============================================================================================ */

@interface SYUController : NSObject
{
	NSRect _square;
	int _pendingOpen;
}
- (void)showAbout:(id)sender;
- (void)systemMenuInvokedAt:(NSRect)square;
- (void)openSystemMenu:(NSTimer *)timer;
@end

@implementation SYUController

/* **THE FIVE ROWS, AND THE FOUR THAT ARE GREY.** "A row with no target is a disabled row" is this tree's own convention
 * (`WSMainMenu.m`): the AppKit's `-[NSMenu update]` enables a row only when its action has a target that answers it, so
 * a command the desktop cannot offer yet is DRAWN GREY rather than absent. Restart, Shut Down and Log Out need a session
 * manager this tree has not got, and System Preferences needs an application it has not got. */
static NSMenu *SYUSystemMenu(SYUController *controller)
{
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"System"] autorelease];
	NSMenuItem *item;

	item = [menu addItemWithTitle:@"About this Computer…" action:@selector(showAbout:) keyEquivalent:@""];
	[item setTarget:controller];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:@"System Preferences" action:NULL keyEquivalent:@""];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:@"Restart" action:NULL keyEquivalent:@""];
	[menu addItemWithTitle:@"Shut Down" action:NULL keyEquivalent:@""];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:@"Log Out" action:NULL keyEquivalent:@""];
	return menu;
}

/* **THE MENU OPENS ON THE NEXT PASS OF THE RUN LOOP, NOT INSIDE THE EVENT THAT SAID SO.** The square's click arrives as
 * a protocol event, and the seam delivers it from inside a dispatch of the connection. A MENU TRACKS — its loop asks
 * the application for events, and that ask waits on the same connection — so opening it there is a pump INSIDE a
 * dispatch, which this tier refuses by design ("a second reader on the same display is a protocol error"). MEASURED
 * with the direct call: the panel was drawn, `NSMenuView` tracked, and every event the loop saw was nil — the menu could
 * not be hovered or chosen, and never closed. A zero-interval timer is one pass later, outside the dispatch, which is
 * where every other menu in this desktop opens from. */
- (void)systemMenuInvokedAt:(NSRect)square
{
	_square = square;
	if (_pendingOpen) {
		return;		/* one open per click, whatever else arrives before the pass runs */
	}
	_pendingOpen = 1;
	[NSTimer scheduledTimerWithTimeInterval:0.0 target:self selector:@selector(openSystemMenu:) userInfo:nil
					 repeats:NO];
}

- (void)openSystemMenu:(NSTimer *)timer
{
	NSScreen *screen = [NSScreen mainScreen];
	NSMenu *menu;

	(void)timer;
	_pendingOpen = 0;
	if (screen == nil) {
		return;
	}
	/* **THE PANEL HANGS FROM THE SQUARE'S BOTTOM-LEFT**, and the compositor counts DOWN from the screen's top while
	 * Cocoa counts UP from the bottom — so the point is the square's bottom edge converted, not the square's top. */
	menu = SYUSystemMenu(self);
	if (menu != nil) {
		/* **THE CLICK THAT OPENED THIS MENU WAS THE SERVER'S.** The square's press is consumed by the compositor, so
		 * this process never saw it — and the tracking loop's "swallow the release that opened me" rule would eat the
		 * person's FIRST real click on a row. This says so, and the menu still drives its own loop. */
		[menu cg_setOpenedWithoutPress:YES];
		[menu popUpMenuPositioningItem:nil
				    atLocation:NSMakePoint(_square.origin.x,
							   [screen frame].size.height - NSMaxY(_square))
				      inView:nil];
	}
}

- (void)showAbout:(id)sender
{
	static NSWindow *s_panel = nil;

	(void)sender;
	if (s_panel == nil) {
		NSArray *lines = SYUAboutLines();
		CGFloat padding = 18.0;
		CGFloat width = 320.0;
		CGFloat height;
		NSUInteger i;
		NSWindow *panel;

		/* THE PANEL IS AS WIDE AS ITS LONGEST LINE, measured in the fonts the view will draw them in. */
		for (i = 0; i < [lines count]; i++) {
			NSDictionary *attributes = SYUTextAttributes((i == 0) ? 15.0 : 12.0, (i == 0), nil);
			CGFloat needed = ceil([[lines objectAtIndex:i] sizeWithAttributes:attributes].width)
				+ 2.0 * padding;

			if (needed > width) {
				width = needed;
			}
		}
		height = padding + 15.0 + 9.0 + (CGFloat)([lines count] - 1) * 17.0 + padding;
		panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, width, height)
						    styleMask:NSTitledWindowMask | NSClosableWindowMask
						      backing:NSBackingStoreBuffered
							defer:NO];
		if (panel == nil) {
			return;
		}
		[panel setTitle:@"About this Computer"];
		[panel setLevel:NSFloatingWindowLevel];
		/* **NOT A PLACE TO PUT THE KEYBOARD, AND NOT A PLACE TO PUT THE MENU BAR.** See the file's header: this process
		 * has no menus of its own to show in the strip, so a click that activated it would empty the bar. */
		[panel cg_setActivatable:NO];
		[panel setContentView:[[[SYUAboutView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, height)
								    lines:lines] autorelease]];
		s_panel = panel;
	}
	[s_panel center];
	[s_panel orderFront:nil];
	fprintf(stderr, "systemui: the About panel is ordered front (%.0fx%.0f at %.0f,%.0f, %lu line(s))\n",
		(double)[s_panel frame].size.width, (double)[s_panel frame].size.height,
		(double)[s_panel frame].origin.x, (double)[s_panel frame].origin.y, (unsigned long)[SYUAboutLines() count]);
}

@end

/* ============================================================================================ *
 * THE ONE EVENT: THE SQUARE WAS CLICKED.                                                        *
 * ============================================================================================ */

static void SYUSystemMenuInvoked(void *context, int x, int y, int width, int height)
{
	SYUController *controller = (SYUController *)context;

	/* THE RECT IS KEPT IN THE COMPOSITOR'S OWN SPACE — top-down, from the square's top — and converted where the menu is
	 * placed. Nothing is opened here: see `-systemMenuInvokedAt:`. */
	[controller systemMenuInvokedAt:NSMakeRect((CGFloat)x, (CGFloat)y, (CGFloat)width, (CGFloat)height)];
}

/* ============================================================================================ *
 * THE PROGRAM                                                                                   *
 * ============================================================================================ */

/* **ONE SYSTEM UI PER SESSION, AND THIS IS WHAT SAYS SO.** The square is one click and the menu that answers it is one
 * menu, so a second copy of this process is a second thing that could open the same menu — and, before the server's
 * single claimant, a second copy that the server would have to arbitrate. The Mac's answer to a second launch is that
 * the first one is brought forward; here there is nothing to bring forward, so the second launch says so and leaves.
 *
 * **A LOCK RATHER THAN A PROTOCOL ANSWER**, because the claim is a statement and has no reply: the file is the session's
 * own (`$XDG_RUNTIME_DIR`, where the Wayland socket lives), the kernel drops the lock when the holder dies, and a live
 * holder is therefore exactly "another System UI is running". The server still refuses a second claim — the lock is the
 * process's half, and the compositor does not trust a client to be the only one. */
static int SYUTakeSingleInstanceLock(void)
{
	const char *runtime = getenv("XDG_RUNTIME_DIR");
	char path[PATH_MAX];
	int fd;

	snprintf(path, sizeof path, "%s/agora-systemui.lock", (runtime != NULL) ? runtime : "/tmp");
	fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
	if (fd < 0) {
		fprintf(stderr, "systemui: cannot open %s: %s\n", path, strerror(errno));
		return -1;
	}
	if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
		fprintf(stderr, "systemui: another System UI is running (the lock is %s)\n", path);
		close(fd);
		return -1;
	}
	/* THE DESCRIPTOR IS DELIBERATELY KEPT: closing it would release the lock. It is one fd for the life of the
	 * process, which is what holding a lock looks like. */
	return fd;
}

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	SYUController *controller;
	AGWindowServer *server;
	AGSystemMenuHandlers handlers;
	int lock;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--dump-about") == 0) {
			/* A TEST'S DOOR, AND NAMED AS ONE: the panel's lines are the machine facts, and a suite has to be able to
			 * read them without a session and without a screen. */
			NSArray *lines = SYUAboutLines();
			NSUInteger line;

			for (line = 0; line < [lines count]; line++) {
				printf("%s\n", [[lines objectAtIndex:line] UTF8String]);
			}
			[pool drain];
			return 0;
		}
	}
	/* BEFORE THE CONNECTION, so a second copy fails for the reason it should and not for a missing display. */
	lock = SYUTakeSingleInstanceLock();
	if (lock < 0) {
		[pool drain];
		return 0;	/* a second launch is not an error — the System UI is already running */
	}
	[NSApplication sharedApplication];
	controller = [[SYUController alloc] init];
	server = AGWindowServerShared();
	if (server == NULL) {
		fprintf(stderr, "systemui: no window server to talk to (is WAYLAND_DISPLAY set?)\n");
		[pool drain];
		return 1;
	}
	handlers.context = controller;
	handlers.invoked = SYUSystemMenuInvoked;
	if (!AGWindowServerClaimSystemMenu(server, &handlers)) {
		fprintf(stderr, "systemui: this window server does not forward the System menu's clicks "
				"(agora_shell version 19 is needed)\n");
		[pool drain];
		return 1;
	}
	fprintf(stderr, "systemui: the System menu's square is this process's\n");
	[NSApp run];
	[pool drain];
	return 0;
}
