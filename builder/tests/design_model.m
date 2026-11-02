/*
 * design_model — the model, the document and the graph, with no window anywhere.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A BUILDER'S QUIET FAILURES ARE ALL MODEL FAILURES**, which is why this is the first test written and the one that runs
 * on every build: an outline row that names nothing, an `id` whose live object is not the view on the canvas, a save that
 * renames an object or reorders a file nobody edited, a document that reports success and writes bytes the compiler then
 * refuses. Each of those looks like a working builder until somebody opens the result.
 *
 * WHAT IS ASSERTED:
 *
 *   1. A NEW DESIGN HAS SOMETHING IN IT. `+emptyDesign` is one view, one record, no connections, and its text is its own
 *      fixed point — a save of a document nobody edited is byte-identical to the document.
 *   2. THE TWO DIRECTIONS OF THE TABLE AGREE. `identifierForObject:` answers the `id` the file states for a top-level object
 *      and for a SUBVIEW — the object a connection or a constraint usually names — and the record→child walk reaches both.
 *   3. A SAVE IS A COMPILABLE FILE. The emitted text goes back through `archiveFromSourceData:` and the reader accepts the
 *      archive, which is the promise that saving is never the step at which a design becomes unreadable.
 *   4. A REFUSED FILE IS REFUSED BY NAME, and the document turns the AppKit's sentence into an error rather than a
 *      document that looks empty.
 *   5. THE DOCUMENT'S DOORS ARE THE MODEL'S. `-readFromData:ofType:error:` and `-dataOfType:error:` carry a design in and
 *      out unchanged, because a document is a file rather than a second model.
 */
#import "AGBuilderDocument.h"
#import "AGDesign.h"

#import <AppKit/NSNib.h>
#import <AppKit/NSNibSource.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("%s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSData *source(const char *text)
{
	return [NSData dataWithBytes:text length:strlen(text)];
}

static NSString *textOf(NSData *data)
{
	if (data == nil) {
		return nil;
	}
	return [[[NSString alloc] initWithBytes:[data bytes]
					 length:[data length]
				       encoding:NSUTF8StringEncoding] autorelease];
}

/* THE FIXTURE: a view with a renamed child, and one connection to the file's owner — enough to reach the table's two
 * directions, the child walk and the connection records. */
static const char *kFixture =
	"{\n"
	"  version = 1;\n"
	"  objects = (\n"
	"    {\n"
	"      id = root;\n"
	"      class = NSView;\n"
	"      properties = { frame = \"0 0 320 240\"; };\n"
	"      subviews = (\n"
	"        { id = title; class = NSTextField; properties = { toolTip = \"press me\"; }; }\n"
	"      );\n"
	"    }\n"
	"  );\n"
	"  connections = (\n"
	"    { source = title; action = \"go:\"; destination = owner; }\n"
	"  );\n"
	"}\n";

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* 1. A NEW DESIGN. */
	{
		AGDesign *design = [AGDesign emptyDesign];
		NSString *reason = nil;
		NSData *emitted;

		check(design != nil, "a new design exists");
		check([[design topLevelObjects] count] == 1, "…with one top-level object");
		check([[design objectRecords] count] == 1, "…and one record");
		check([[design objectsByID] count] == 1, "…whose name the table holds");
		check([[design connectionRecords] count] == 0, "…and no connections");

		emitted = [design sourceDataWithError:&reason];
		check(emitted != nil && reason == nil, "a new design emits");
		check([[NSString stringWithFormat:@"%@", textOf(emitted)] length] > 0, "…as text");
		check([[[AGDesign designWithSourceData:emitted error:&reason] sourceDataWithError:&reason]
			  isEqualToData:emitted],
		      "…which is its own fixed point, so an unedited save cannot churn a diff");
	}

	/* 2. THE TABLE, BOTH WAYS, AND THE CHILD WALK. */
	{
		NSString *reason = nil;
		AGDesign *design = [AGDesign designWithSourceData:source(kFixture) error:&reason];
		NSDictionary *rootRecord;
		NSArray *children;

		check(design != nil, "the fixture opens");
		check(reason == nil, "…without a reason");

		if (design != nil) {
			id root = [design objectForID:@"root"];
			id title = [design objectForID:@"title"];

			check(root != nil && [root isKindOfClass:[NSView class]], "an id resolves to its live object");
			check([[design topLevelObjects] objectAtIndex:0] == root, "…and it is the object the graph holds");
			check(title != nil && [design identifierForObject:title] != nil &&
			      [[design identifierForObject:title] isEqualToString:@"title"],
			      "the reverse direction answers for a SUBVIEW, which is what a connection names");
			check([design identifierForObject:[[NSView alloc] init]] == nil,
			      "…and answers nothing for an object the file never named");

			rootRecord = [[design objectRecords] objectAtIndex:0];
			children = [design childRecordsOfRecord:rootRecord];
			check([children count] == 1, "the record walk reaches the child");
			check(children != nil && [[design identifierOfRecord:[children objectAtIndex:0]] isEqualToString:@"title"],
			      "…under the name the file gives it");
			check([design childRecordsOfRecord:[children objectAtIndex:0]] == nil ||
			      [[design childRecordsOfRecord:[children objectAtIndex:0]] count] == 0,
			      "…and a leaf has no children");

			check([[design connectionRecords] count] == 1, "the connection is a record");
			check([[design summaryOfRecord:rootRecord] isEqualToString:@"NSView — root"],
			      "a row reads as class and name");
			check([[design classNameOfRecord:rootRecord] isEqualToString:@"NSView"],
			      "…and the class is the file's word for it");
		}
	}

	/* 3. A SAVED DESIGN IS A COMPILABLE FILE. */
	{
		NSString *reason = nil;
		AGDesign *design = [AGDesign designWithSourceData:source(kFixture) error:&reason];
		NSData *emitted = [design sourceDataWithError:&reason];
		NSData *archive = [NSNibSource archiveFromSourceData:emitted error:&reason];

		check(emitted != nil, "the fixture emits");
		check(archive != nil, "the emitted text COMPILES");
		check(archive != nil && [NSNib refusalReasonForArchiveData:archive] == nil,
		      "…into an archive the reader accepts");
	}

	/* 4. A REFUSED FILE IS REFUSED BY NAME. */
	{
		NSString *reason = nil;
		AGDesign *design = [AGDesign designWithSourceData:source("{ version = 1; objects = ( { class = NSView3; } ); }")
							    error:&reason];

		check(design == nil, "a design naming a class this tree has not got is refused");
		check(reason != nil && [reason rangeOfString:@"NSView3"].location != NSNotFound,
		      "…naming it, rather than saying the file is bad");
	}

	/* 5. THE DOCUMENT'S DOORS ARE THE MODEL'S. */
	{
		NSError *error = nil;
		AGBuilderDocument *document = [[AGBuilderDocument alloc] init];
		AGDesign *expected = [AGDesign designWithSourceData:source(kFixture) error:NULL];
		NSData *wanted = [expected sourceDataWithError:NULL];
		NSData *written = nil;

		check([document readFromData:source(kFixture) ofType:@"io.github.agoradesktop.agnib" error:&error],
		      "a document reads a design");
		check(error == nil, "…without an error");
		check([[[document design] objectForID:@"title"] isKindOfClass:[NSTextField class]],
		      "…and its model holds the live graph");

		written = [document dataOfType:@"io.github.agoradesktop.agnib" error:&error];
		check(written != nil && [written isEqualToData:wanted],
		      "writing it back is the model's own bytes, not a second spelling");

		error = nil;
		check(![document readFromData:source("{ objects = ( ); }") ofType:@"io.github.agoradesktop.agnib" error:&error],
		      "a bad file is refused");
		check(error != nil && [[error localizedDescription] length] > 0,
		      "…with a sentence for the person who opened it");
		check([[[document design] objectForID:@"title"] isKindOfClass:[NSTextField class]],
		      "…and the design it already had is untouched");
		[document release];
	}

	[pool release];
	if (s_failed != 0) {
		fprintf(stderr, "%d failure(s)\n", s_failed);
		return 1;
	}
	printf("all design-model assertions passed\n");
	return 0;
}
