/*
 * AGBuilderDocument.m — reading the text, writing it back, and one window over it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * See AGBuilderDocument.h. Two notes:
 *
 * **THE TYPE IS THE UTI, NOT THE EXTENSION.** `Info.plist` names the type `io.github.agoradesktop.agnib` and maps `.agnib`
 * to it; the document controller resolves an opened file's extension into that name and this class answers for it. A type
 * name is what a document carries through a save panel, an error and a recent-documents list, so it is the UTI rather than
 * the four letters of a filesystem accident.
 *
 * **A FAILED READ DOES NOT REPLACE THE DESIGN.** `-readFromData:` builds a NEW `AGDesign` and swaps it in only after the
 * parser and the object table have both accepted the file, so a document whose read is refused keeps whatever it had and
 * reports why — the same shape `NSNib` uses when it leaves the top-level out-parameter exactly as it was.
 */
#import "AGBuilderDocument.h"

#import "AGBuilderWindowController.h"
#import "AGDesign.h"

#import <AppKit/NSDocument.h>
#import <AppKit/NSWindowController.h>

#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSString.h>

NSString * const AGBuilderErrorDomain = @"AGBuilderErrorDomain";

@implementation AGBuilderDocument

/* ============================ THE TYPE TABLE ============================ */

+ (NSArray *)readableTypes
{
	return [NSArray arrayWithObject:@"io.github.agoradesktop.agnib"];
}

+ (NSArray *)writableTypes
{
	return [NSArray arrayWithObject:@"io.github.agoradesktop.agnib"];
}

+ (BOOL)isNativeType:(NSString *)type
{
	return [type isEqualToString:@"io.github.agoradesktop.agnib"];
}

/* ============================ A DOCUMENT'S LIFE ============================ */

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_design = [[AGDesign emptyDesign] retain];
	}
	return self;
}

- (void)dealloc
{
	[_design release];
	[super dealloc];
}

- (AGDesign *)design
{
	return _design;
}

/* ============================ READING AND WRITING ============================ */

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	NSString *reason = nil;
	AGDesign *design;

	(void)typeName;
	design = [AGDesign designWithSourceData:data error:&reason];
	if (design == nil) {
		if (outError != NULL) {
			*outError = [NSError errorWithDomain:AGBuilderErrorDomain
							code:AGBuilderErrorRead
						    userInfo:[NSDictionary dictionaryWithObject:
								  (reason != nil) ? reason : @"the design could not be read"
											     forKey:NSLocalizedDescriptionKey]];
		}
		return NO;
	}
	[design retain];
	[_design release];
	_design = design;
	return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	NSString *reason = nil;
	NSData *data;

	(void)typeName;
	data = [_design sourceDataWithError:&reason];
	if (data == nil && outError != NULL) {
		*outError = [NSError errorWithDomain:AGBuilderErrorDomain
						code:AGBuilderErrorWrite
					    userInfo:[NSDictionary dictionaryWithObject:
							  (reason != nil) ? reason : @"the design could not be written"
								     forKey:NSLocalizedDescriptionKey]];
	}
	return data;
}

/* ============================ THE WINDOW ============================ */

- (void)makeWindowControllers
{
	AGBuilderWindowController *controller = [[AGBuilderWindowController alloc] init];

	[self addWindowController:controller];
	[controller release];
}

/* THE WINDOW IS HANDED NO MODEL HERE: `-addWindowController:` calls `-setDocument:`, and that is the standard lifecycle's
 * door for a controller learning whose file it is showing. `NSWindowController` also knows how to spell the pair — `Untitled`
 * for a design with no file, the last path component once it has one, with the edited dot the window draws for itself. */
@end
