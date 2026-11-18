#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// What RNTBBalanceTextStorage applied to a storage: each balanced line's width and side, keyed by
// where the line starts. No balanced lines means default wrapping. Immutable, so the break cache
// can share it across threads.
@interface RNTBBalancedBreaks : NSObject
// The storage on default wrapping.
@property (class, nonatomic, readonly) RNTBBalancedBreaks *defaultWrapping;
// The height these lines need: in a shorter container TextKit cuts lines off, and balancing there
// gives a different outcome. 0 for default wrapping, which a shorter container doesn't change.
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
// don't hold after one repair retry, keeps default wrapping; if no paragraph balances, RN's own container stays in place.
// A paragraph containing a tab keeps default wrapping. Text that would truncate at `maximumNumberOfLines`
// (0 = unlimited) is left exactly as default wrapping leaves it; text that fits balances to its line count.
// The storage itself is never edited: the only change is the text container.
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
