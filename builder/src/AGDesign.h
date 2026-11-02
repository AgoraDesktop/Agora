/*
 * AGDesign.h — a design: the property list a person edits, and the live objects it names.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE MODEL IS TWO THINGS AT ONCE, AND THAT IS THE POINT.** A design file is TEXT — the format `NSNibSource`
 * documents — and a canvas is a graph of LIVE `NSView`s, because the only honest preview of an AppKit interface is the
 * AppKit. Keeping both in one object is what lets the window be a view of the file rather than a drawing of it: the tree
 * is what a save writes, so every spelling, every `id` and every key's order is the person's and not a reconstruction; the
 * live objects are what the canvas shows and what an inspector writes through, so editing a frame moves the real view.
 *
 * **AND THE OBJECTS ARE MADE BY THE COMPILER'S OWN CODE**, through
 * `+[NSNibSource objectsFromPropertyList:objectsByID:error:]`, so a design that shows in this window and a design that
 * instantiates from the compiled nib are the same graph built by the same rules — including the refusals. A builder that
 * built its own objects would be a second opinion about what a design file means, and the two opinions would disagree the
 * first time a class gained a property.
 *
 * **THE MODEL HAS NO VIEW IN IT, WHICH IS WHY IT HAS A SUITE THAT NEEDS NO COMPOSITOR.** Everything a design can get
 * wrong — a tree that does not round-trip, an `id` that names no object, a record the outline cannot show — is answerable
 * here. The canvas, the outline and the inspector are views over this object; they are allowed to be wrong about
 * appearance, not about meaning.
 */
#ifndef AGDESIGN_H
#define AGDESIGN_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AGDesign : NSObject
{
	NSMutableDictionary *_propertyList;	/* RETAINED: the root of the source tree — what a save writes */
	NSArray *_topLevelObjects;		/* RETAINED: live objects, in file order */
	NSDictionary *_objectsByID;		/* RETAINED: every name in the file, nested objects included */
	NSMutableDictionary *_idsByObject;	/* RETAINED: NSValue pointer -> the name, for the reverse question */
}

/* ============================ THE TWO WAYS IN ============================ */

/* **A DESIGN OUT OF THE BYTES A DOCUMENT READS.** The parser's refusals are the compiler's, and so are the object table's,
 * so a file this door answers is a file `ibtool compile` would also answer. Answers nil with the sentence in `error` when
 * the file is not a design — the sentence is the AppKit's, and a document puts it in front of a person unchanged rather
 * than rephrasing it into something less exact. */
+ (nullable instancetype)designWithSourceData:(NSData *)data error:(NSString * _Nullable * _Nullable)error;

/* **A NEW DESIGN: ONE VIEW, THE SIZE A WINDOW'S CONTENT VIEW USUALLY IS.** It is built by PARSING its own text rather than
 * by assembling a property list in code, so a new document and an opened one travel the same path and there is no second
 * definition of what an empty design is. */
+ (instancetype)emptyDesign;

/* ============================ THE WAY BACK OUT ============================ */

/* The tree as text, by the AppKit's emitter — the parser's inverse, which is what makes an unedited save byte-identical. */
- (nullable NSData *)sourceDataWithError:(NSString * _Nullable * _Nullable)error;

/* ============================ WHAT A VIEW ASKS ============================ */

/* THE ROOT OF THE SOURCE TREE. Mutable, because an edit changes it: a property set, a subview added, a connection drawn.
 * A view must not mutate it directly — the model's own edit verbs are the ones that keep the live objects and the tree in
 * step — but reading it is how the outline and the inspector find what to show. */
- (NSMutableDictionary *)propertyList;

/* THE LIVE GRAPH: the top-level objects in file order, and the name → object table the compiler built. */
- (NSArray *)topLevelObjects;
- (NSDictionary *)objectsByID;
- (nullable id)objectForID:(NSString *)identifier;
- (nullable NSString *)identifierForObject:(id)object;

/* THE RECORDS — the source dictionaries, which is what the outline navigates. A record is one object's `{ id; class;
 * properties; … }`; its children are its `contentView`, its `cell` and its `subviews`, in that order, because that is the
 * order the format states them in. */
- (NSArray *)objectRecords;
- (NSArray *)childRecordsOfRecord:(NSDictionary *)record;
- (nullable NSString *)classNameOfRecord:(NSDictionary *)record;
- (nullable NSString *)identifierOfRecord:(NSDictionary *)record;

/* AND THE CONNECTIONS, as the source states them: `source`, then `keyPath` or `action` (or `binding`), then `destination`.
 * They are records rather than live target/action pairs because a connection is a fact about the DESIGN — the destination
 * may be the file's owner, which does not exist until the nib is instantiated. */
- (NSArray *)connectionRecords;

/* THE LINE A PERSON READS IN THE OUTLINE: `NSButton — goButton`, or the class alone when the object has no name. */
- (NSString *)summaryOfRecord:(NSDictionary *)record;

@end

NS_ASSUME_NONNULL_END

#endif /* AGDESIGN_H */
