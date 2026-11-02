/*
 * AGDesign.m — the model: the tree, the graph, and the two questions that connect them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * See AGDesign.h. Three implementation notes:
 *
 * **THE TREE IS A MUTABLE COPY OF WHAT THE PARSER ANSWERED.** `propertyListFromSourceData:` answers an immutable
 * dictionary; the model keeps a mutable copy so that an edit is a change in place rather than a rebuild of the file. Only
 * the ROOT has to be mutable for that to work — the emitter is defined over whatever it is handed — but the root is also
 * the only dictionary the model itself writes (a top-level object added, a connection appended).
 *
 * **THE REVERSE MAP IS KEYED BY POINTER AND NOT BY `-hash`**, because two objects that are `isEqual:` are not two
 * different rows: a design that holds two identical buttons is two objects in the file and must be two rows in the outline.
 * `NSValue -valueWithPointer:` is the key for exactly that reason, and it is what `AGNibWriter` uses for the same purpose.
 *
 * **NOTHING HERE HOLDS A WINDOW OR A SCREEN.** The live objects may be views — the canvas puts them on screen — but the
 * model only ever asks them for their class, their frame and their coded properties, so the whole file runs with no
 * compositor and its suite asserts meaning rather than pixels.
 */
#import "AGDesign.h"

#import <AppKit/NSNibSource.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSValue.h>

/* THE NEW DOCUMENT'S TEXT, and the only place it is spelled. A view is the root because a design that opens with no
 * window still has something to arrange, and a window is one menu item away in a later slice. */
static NSString *const AGEmptyDesignSource =
	@"{\n"
	@"  version = 1;\n"
	@"  objects = (\n"
	@"    {\n"
	@"      id = root;\n"
	@"      class = NSView;\n"
	@"      properties = { frame = \"0 0 480 320\"; };\n"
	@"    }\n"
	@"  );\n"
	@"}\n";

@implementation AGDesign

/* ============================ THE TWO WAYS IN ============================ */

+ (instancetype)designWithSourceData:(NSData *)data error:(NSString **)error
{
	id plist;
	NSDictionary *objectsByID = nil;
	NSArray *topLevelObjects;
	AGDesign *design;

	if (data == nil) {
		if (error != NULL) {
			*error = @"the design has no bytes";
		}
		return nil;
	}
	plist = [NSNibSource propertyListFromSourceData:data error:error];
	if (![plist isKindOfClass:[NSDictionary class]]) {
		if (plist == nil) {
			return nil;
		}
		if (error != NULL) {
			*error = @"a design's root must be a dictionary";
		}
		return nil;
	}
	/* **THE OBJECTS ARE BUILT ONCE, HERE, AND THE MODEL OWNS THEM.** A canvas may put them on screen, but a design that
	 * has never been shown has the same graph: the model is not lazy because the outline, the inspector and the emitter
	 * all want a name for an object they were handed. */
	topLevelObjects = [NSNibSource objectsFromPropertyList:plist objectsByID:&objectsByID error:error];
	if (topLevelObjects == nil) {
		return nil;
	}

	design = [[self alloc] init];
	design->_propertyList = [[NSMutableDictionary alloc] initWithDictionary:(NSDictionary *)plist];
	design->_topLevelObjects = [topLevelObjects retain];
	design->_objectsByID = [objectsByID retain];
	design->_idsByObject = [[NSMutableDictionary alloc] init];
	/* **THE REVERSE MAP IS BUILT FROM THE SAME TABLE THE COMPILER FILLED**, so a nested object — the common destination
	 * of an outlet — is as findable as a top-level one, and the two directions cannot disagree because there is only one
	 * table to disagree with. */
	{
		NSEnumerator *enumerator = [objectsByID keyEnumerator];
		NSString *identifier;
		id object;

		while ((identifier = [enumerator nextObject]) != nil) {
			object = [objectsByID objectForKey:identifier];
			[design->_idsByObject setObject:identifier
						 forKey:[NSValue valueWithPointer:object]];
		}
	}
	return [design autorelease];
}

+ (instancetype)emptyDesign
{
	NSString *reason = nil;
	AGDesign *design = [self designWithSourceData:[AGEmptyDesignSource dataUsingEncoding:NSUTF8StringEncoding]
						error:&reason];

	if (design == nil) {
		/* **THIS CANNOT HAPPEN, AND IT IS NOT ASSERTED AWAY.** The literal above is compiled by the same parser the
		 * documents use; if it ever stops compiling the whole application is broken, and a nil design would then be a
		 * crash three frames away from the cause. Answering a design built by hand keeps the failure audible instead. */
		design = [[[self alloc] init] autorelease];
		design->_propertyList = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
			[NSNumber numberWithInt:1], @"version",
			[NSArray array], @"objects", nil];
		design->_topLevelObjects = [[NSArray alloc] init];
		design->_objectsByID = [[NSDictionary alloc] init];
		design->_idsByObject = [[NSMutableDictionary alloc] init];
	}
	return design;
}

- (void)dealloc
{
	[_propertyList release];
	[_topLevelObjects release];
	[_objectsByID release];
	[_idsByObject release];
	[super dealloc];
}

/* ============================ THE WAY BACK OUT ============================ */

- (NSData *)sourceDataWithError:(NSString **)error
{
	return [NSNibSource sourceDataFromPropertyList:_propertyList error:error];
}

/* ============================ WHAT A VIEW ASKS ============================ */

- (NSMutableDictionary *)propertyList
{
	return _propertyList;
}

- (NSArray *)topLevelObjects
{
	return _topLevelObjects;
}

- (NSDictionary *)objectsByID
{
	return _objectsByID;
}

- (id)objectForID:(NSString *)identifier
{
	if (identifier == nil) {
		return nil;
	}
	return [_objectsByID objectForKey:identifier];
}

- (NSString *)identifierForObject:(id)object
{
	if (object == nil) {
		return nil;
	}
	return [_idsByObject objectForKey:[NSValue valueWithPointer:object]];
}

- (NSArray *)objectRecords
{
	id objects = [_propertyList objectForKey:@"objects"];

	return [objects isKindOfClass:[NSArray class]] ? (NSArray *)objects : [NSArray array];
}

/* THE THREE STRUCTURAL KEYS, IN THE ORDER THE FORMAT STATES THEM. `subviews` is last because it is the one a person reads
 * as "inside this": a content view and a cell are one object each, and a subview list is the hierarchy. */
- (NSArray *)childRecordsOfRecord:(NSDictionary *)record
{
	NSMutableArray *children = [NSMutableArray array];
	NSArray *keys = [NSArray arrayWithObjects:@"contentView", @"cell", @"subviews", nil];
	NSUInteger i;

	for (i = 0; i < [keys count]; i++) {
		id value = [record objectForKey:[keys objectAtIndex:i]];

		if ([value isKindOfClass:[NSArray class]]) {
			[children addObjectsFromArray:(NSArray *)value];
		} else if ([value isKindOfClass:[NSDictionary class]]) {
			[children addObject:value];
		}
	}
	return children;
}

- (NSString *)classNameOfRecord:(NSDictionary *)record
{
	id name = [record objectForKey:@"class"];

	return [name isKindOfClass:[NSString class]] ? (NSString *)name : nil;
}

- (NSString *)identifierOfRecord:(NSDictionary *)record
{
	id name = [record objectForKey:@"id"];

	return [name isKindOfClass:[NSString class]] ? (NSString *)name : nil;
}

- (NSArray *)connectionRecords
{
	id connections = [_propertyList objectForKey:@"connections"];

	return [connections isKindOfClass:[NSArray class]] ? (NSArray *)connections : [NSArray array];
}

- (NSString *)summaryOfRecord:(NSDictionary *)record
{
	NSString *className = [self classNameOfRecord:record];
	NSString *identifier = [self identifierOfRecord:record];

	if (className == nil) {
		return @"(no class)";
	}
	if (identifier == nil) {
		return className;
	}
	/* **CONCATENATED RATHER THAN FORMATTED, BECAUSE THIS TIER'S `+stringWithFormat:` WALKS THE FORMAT'S BYTES.** A multi-byte
	 * character in a format string comes out as one Latin-1 character per byte — measured: `"%@ — %@"` answers a 15-unit
	 * string whose dash is `â` plus three stray bytes — while `-stringByAppendingString:` is UTF-8-correct. The separator is
	 * therefore appended, not formatted, and the same rule holds anywhere else in this application a format would need one. */
	return [[className stringByAppendingString:@" — "] stringByAppendingString:identifier];
}

@end
