#import <UIKit/UIKit.h>

// Balances the paragraphs of a TextKit 1 stack that React Native has just built, in place.
//
// `storage` has one layout manager with one text container, as RN's stack builder returns it. Each
// paragraph with more than one line at the container's width gets minimum-raggedness balanced breaks
// at the same line count, imposed through a per-line text container that replaces RN's (at the same
// size), and checked against the lines TextKit then lays out. Break points follow UAX #14 (any
// script), widths come from Core Text glyph advances. A paragraph whose breaks don't fit, or still
// don't hold after one repair retry, keeps stock wrapping; if no paragraph balances, RN's own container stays in place.
// A paragraph containing a tab keeps stock wrapping. Text that would truncate at `maximumNumberOfLines`
// (0 = unlimited) is left exactly as stock; text that fits balances to its line count. While balanced
// breaks are applied to a paragraph, `pushOut` is cleared from its line-break strategy; a paragraph on stock
// wrapping keeps its original style.
void RNTBBalanceTextStorage(NSTextStorage *storage, NSUInteger maximumNumberOfLines);
