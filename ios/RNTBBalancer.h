#import <UIKit/UIKit.h>

// Balances the paragraphs of a TextKit 1 stack that React Native has just built, in place.
//
// `storage` has one layout manager with one text container, as RN's stack builder returns it. Each
// paragraph with more than one line at the container's width is given a minimum-raggedness plan at
// the same line count, imposed through a per-line text container that replaces RN's (at the same
// size), and checked against the lines TextKit then lays out. Break points follow UAX #14 (any
// script), widths come from Core Text glyph advances. A paragraph whose plan doesn't fit, or still
// doesn't hold after one repair retry, keeps stock wrapping; if no paragraph balances, RN's own container stays in place.
// Text that would truncate at `maximumNumberOfLines` (0 = unlimited) is left exactly as stock.
void RNTBBalanceTextStorage(NSTextStorage *storage, NSUInteger maximumNumberOfLines);
