#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// What RNTBBalanceTextStorage applied to a storage: each balanced line's width and side, keyed by
// where the line starts, and the paragraph style runs whose `pushOut` it cleared. No balanced lines
// means stock wrapping. Immutable, so the break cache can share it across threads.
@interface RNTBBalancedBreaks : NSObject
// The storage on stock wrapping.
@property (class, nonatomic, readonly) RNTBBalancedBreaks *stock;
// The height these lines need: in a shorter container TextKit cuts lines off, and balancing there
// gives a different outcome. 0 for stock wrapping, which a shorter container doesn't change.
@property (nonatomic, readonly) CGFloat minimumHeight;
- (instancetype)init NS_UNAVAILABLE;
@end

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
//
// Returns what it applied, for RNTBApplyBalancedBreaks to reapply to a stack built from the same
// input. Returns nil when the container's height cut lines off, because then the outcome depends
// on that height.
RNTBBalancedBreaks *_Nullable RNTBBalanceTextStorage(NSTextStorage *storage, NSUInteger maximumNumberOfLines);

// Applies balanced breaks that RNTBBalanceTextStorage returned for a stack built from the same input
// (attributed string, paragraph attributes and width) to this one, without choosing or checking
// them again. The lines come out identical, as long as the container is at least `minimumHeight` tall.
void RNTBApplyBalancedBreaks(NSTextStorage *storage, RNTBBalancedBreaks *breaks);

NS_ASSUME_NONNULL_END
