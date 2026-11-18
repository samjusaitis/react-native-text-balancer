// react-native-text-balancer: makes React Native's textBreakStrategy="balanced" balance on iOS.
//
// The hook (ADR 0001). Every RN text path (measure, onTextLayout lines, draw, hit-test) builds its
// TextKit 1 stack through the private
//   -[RCTTextLayoutManager _textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:]
// so replacing that one method keeps them all consistent. The replacement calls RN's original first
// (so adjustsFontSizeToFit has already scaled the storage) and only touches the stack when the
// Outermost Text asked for textBreakStrategy="balanced". Every other Text gets exactly what RN built.
//
// RN's measure and lines caches key on ParagraphAttributes, which include textBreakStrategy, so a
// balanced and a default layout of the same string never share an entry.
//
// The break cache: RN caches measure and lines, but draw (on the main thread) and hit-test build
// the stack again for the same string and width. So the hook keeps what balancing applied and
// reapplies it to later stacks built from the same input. The key is everything the outcome
// depends on, so nothing needs invalidating (Dynamic Type changes the fonts, so the key).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <functional>

#import <React/RCTDefines.h>
#import <React/RCTLog.h>
#import <cxxreact/ReactNativeVersion.h>
#import <react/renderer/attributedstring/ParagraphAttributes.h>

#import "RNTBBalancer.h"

// RN's main branch reports 1000.0, which passes.
#if REACT_NATIVE_VERSION_MAJOR == 0 && REACT_NATIVE_VERSION_MINOR < 85
#error "react-native-text-balancer needs React Native 0.85 or newer (New Architecture)."
#endif

using facebook::react::ParagraphAttributes;
using facebook::react::TextBreakStrategy;

static NSString *const kHookClass = @"RCTTextLayoutManager";
static NSString *const kHookSelector = @"_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:";

// A break cache key: RN's input attributed string (before any adjustsFontSizeToFit scaling),
// compared attribute by attribute, plus the paragraph attributes and size that change the outcome.
// Height only matters when adjustsFontSizeToFit scales to it; otherwise RNTBBalancedBreaks'
// minimumHeight covers it.
@interface RNTBBreakCacheKey : NSObject <NSCopying>
- (instancetype)initWithString:(NSAttributedString *)string
           paragraphAttributes:(const ParagraphAttributes &)paragraphAttributes
                          size:(CGSize)size;
@end

@implementation RNTBBreakCacheKey {
  NSAttributedString *_string;
  CGFloat _width;
  CGFloat _height;
  NSUInteger _maximumNumberOfLines;
  BOOL _adjustsFontSizeToFit;
  NSUInteger _hash;
}

- (instancetype)initWithString:(NSAttributedString *)string
           paragraphAttributes:(const ParagraphAttributes &)paragraphAttributes
                          size:(CGSize)size
{
  if (self = [super init]) {
    _string = [string copy];
    _width = size.width;
    _adjustsFontSizeToFit = paragraphAttributes.adjustsFontSizeToFit;
    _height = _adjustsFontSizeToFit ? size.height : 0;
    _maximumNumberOfLines = paragraphAttributes.maximumNumberOfLines;
    _hash = _string.string.hash ^ std::hash<CGFloat>{}(_width) ^ (_maximumNumberOfLines << 20);
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  return self; // immutable
}

- (NSUInteger)hash
{
  return _hash;
}

- (BOOL)isEqual:(id)object
{
  if (![object isKindOfClass:[RNTBBreakCacheKey class]]) {
    return NO;
  }
  RNTBBreakCacheKey *other = object;
  return _hash == other->_hash && _width == other->_width && _height == other->_height &&
      _maximumNumberOfLines == other->_maximumNumberOfLines && _adjustsFontSizeToFit == other->_adjustsFontSizeToFit &&
      [_string isEqualToAttributedString:other->_string];
}

@end

static NSCache<RNTBBreakCacheKey *, RNTBBalancedBreaks *> *breakCache()
{
  static NSCache *cache = [] {
    NSCache *c = [NSCache new];
    c.countLimit = 256;
    return c;
  }();
  return cache;
}

typedef NSTextStorage *(*RNTBBuildIMP)(id, SEL, NSAttributedString *, ParagraphAttributes, CGSize);
static RNTBBuildIMP gOriginalBuild = nullptr;

static NSTextStorage *RNTBBuild(
    id self,
    SEL _cmd,
    NSAttributedString *attributedString,
    ParagraphAttributes paragraphAttributes,
    CGSize size)
{
  NSTextStorage *storage = gOriginalBuild(self, _cmd, attributedString, paragraphAttributes, size);
  if (paragraphAttributes.textBreakStrategy != TextBreakStrategy::Balanced) {
    return storage;
  }
  RNTBBreakCacheKey *key = [[RNTBBreakCacheKey alloc] initWithString:attributedString
                                                 paragraphAttributes:paragraphAttributes
                                                                size:size];
  RNTBBalancedBreaks *breaks = [breakCache() objectForKey:key];
  if (breaks != nil && size.height >= breaks.minimumHeight) {
    RNTBApplyBalancedBreaks(storage, breaks);
    return storage;
  }
  breaks = RNTBBalanceTextStorage(storage, paragraphAttributes.maximumNumberOfLines);
  if (breaks != nil) {
    [breakCache() setObject:breaks forKey:key];
  }
  return storage;
}

@interface RNTextBalancer : NSObject
@end

@implementation RNTextBalancer

// Never called. It exists so the compiler encodes the signature we expect RN's builder to have,
// from the same RN headers the replacement above is compiled against.
- (NSTextStorage *)rntb_expectedSignature:(NSAttributedString *)attributedString
                      paragraphAttributes:(ParagraphAttributes)paragraphAttributes
                                     size:(CGSize)size
{
  return nil;
}

+ (void)load
{
  NSString *problem = [self install];
  if (problem != nil) {
#if RCT_DEV
    // Deferred so RN's logging is set up; +load runs once, so this warns once per process.
    dispatch_async(dispatch_get_main_queue(), ^{
      RCTLogWarn(
          @"react-native-text-balancer: %@. textBreakStrategy=\"balanced\" uses default wrapping on iOS with this React Native version.",
          problem);
    });
#endif
  }
}

// Swizzles RN's builder if the class, the selector and the type encoding all match. Returns nil on
// success, or why it left RN untouched.
+ (NSString *)install
{
  Class cls = NSClassFromString(kHookClass);
  if (cls == nil) {
    return [NSString stringWithFormat:@"%@ not found", kHookClass];
  }
  Method method = class_getInstanceMethod(cls, NSSelectorFromString(kHookSelector));
  if (method == nullptr) {
    return [NSString stringWithFormat:@"-[%@ %@] not found", kHookClass, kHookSelector];
  }
  Method expected = class_getInstanceMethod(self, @selector(rntb_expectedSignature:paragraphAttributes:size:));
  const char *actualTypes = method_getTypeEncoding(method);
  const char *expectedTypes = method_getTypeEncoding(expected);
  if (actualTypes == nullptr || expectedTypes == nullptr || strcmp(actualTypes, expectedTypes) != 0) {
    return [NSString stringWithFormat:@"-[%@ %@] has an unexpected signature", kHookClass, kHookSelector];
  }
  gOriginalBuild = (RNTBBuildIMP)method_setImplementation(method, (IMP)RNTBBuild);
  return nil;
}

@end
