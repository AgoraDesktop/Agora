/*
 * AGBuilderDocument.h — one design file, and the window that shows it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE DOCUMENT IS THE FILE, AND THE FILE IS TEXT.** `NSDocument`'s reading and writing doors are what the
 * `CFBundleDocumentTypes` entry in `Info.plist` promises: `-readFromData:ofType:error:` parses the source and
 * `-dataOfType:error:` emits it, both through the AppKit's own format code, so opening and saving this application's files
 * is exactly what `ibtool validate` and `ibtool roundtrip` do to them. Nothing in this class knows a property list.
 *
 * **THE COMPILED ARCHIVE IS NOT THIS DOCUMENT'S BUSINESS.** A design is saved as the text a person reviews; turning that
 * text into the `.nib` a running application loads is the build's job (`ibtool compile`), and this document writes the
 * artifact only when it is asked to test the interface — which is a later slice. Committing a binary beside the source
 * would be committing the one file the federation cannot merge.
 *
 * **AN UNTITLED DOCUMENT IS A DESIGN, NOT AN EMPTY BUFFER.** `-init` makes an empty design through `AGDesign`, so a new
 * window can draw something and a save has a root to write. That is also why this class never asks whether its design is
 * nil: it has one from the first moment, and the only way it changes is a successful read.
 */
#ifndef AGBUILDERDOCUMENT_H
#define AGBUILDERDOCUMENT_H

#import <AppKit/NSDocument.h>

@class AGDesign;

/* THE DOCUMENT'S ERROR DOMAIN, for the two doors that can fail. The SENTENCE is the AppKit's — a parser or emitter refusal,
 * passed through unchanged — because a rephrased refusal is a refusal a person cannot act on. */
extern NSString * const AGBuilderErrorDomain;

typedef enum {
	AGBuilderErrorRead = 1,
	AGBuilderErrorWrite = 2
} AGBuilderErrorCode;

@interface AGBuilderDocument : NSDocument
{
	AGDesign *_design;	/* RETAINED: never nil; a new document starts with an empty design */
}

/* THE MODEL, for the window controller and for a future palette and inspector. */
- (AGDesign *)design;

@end

#endif /* AGBUILDERDOCUMENT_H */
