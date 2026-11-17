// PROTOTYPE (ticket 10): JS dispatch for the library's Text on iOS. Throwaway.
//
//   balance false/missing -> plain RN <Text>
//   balance (iOS)         -> <BalancedParagraph {paragraph props}>
//                              <TextAncestorContext value={true}>
//                                <Text {span props}>{children}</Text>      (renders RCTVirtualText)
//                              </TextAncestorContext>
//                            </BalancedParagraph>
//
// What Text.js does for a ROOT text that the wrapper must reproduce on the host paragraph,
// because the inner Text is virtual and Text.js skips its root-only branch:
//   accessible (iOS default true), allowFontScaling (default true), ellipsizeMode (default 'tail'),
//   numberOfLines (clamped >= 0), selectable (+ style.userSelect), the 'link' accessibilityRole
//   when pressable, aria-* -> accessibilityState/label, id -> nativeID.
// Pressability (usePressability, isHighlighted on press-in, onClick, responder handlers) stays on
// the inner Text: Text.js gives virtual text the same PressableVirtualText path, and
// RCTParagraphComponentView routes touches to the span's event emitter.
import * as React from 'react';
import {
  Platform,
  StyleSheet,
  Text,
  type TextProps,
  unstable_TextAncestorContext as TextAncestorContext,
} from 'react-native';

import BalancedParagraph from './BalancedParagraphNativeComponent';

export type BalancedTextProps = TextProps & { balance?: boolean };

export function BalancedText({ balance, ...props }: BalancedTextProps) {
  if (!balance || Platform.OS !== 'ios') {
    return <Text {...props} />;
  }
  const {
    children,
    style,
    numberOfLines,
    ellipsizeMode,
    allowFontScaling,
    maxFontSizeMultiplier,
    dynamicTypeRamp,
    adjustsFontSizeToFit,
    minimumFontScale,
    selectable,
    textBreakStrategy,
    lineBreakStrategyIOS,
    dataDetectorType,
    onTextLayout,
    accessible,
    accessibilityLabel,
    accessibilityRole,
    accessibilityHint,
    accessibilityState,
    'aria-label': ariaLabel,
    role,
    nativeID,
    id,
    testID,
    ...spanProps
  } = props;
  const pressable = spanProps.onPress != null || spanProps.onLongPress != null;
  const flat = StyleSheet.flatten(style) ?? {};
  const userSelect = flat.userSelect;
  return (
    <BalancedParagraph
      style={style}
      numberOfLines={numberOfLines != null && numberOfLines >= 0 ? numberOfLines : undefined}
      ellipsizeMode={ellipsizeMode ?? 'tail'}
      allowFontScaling={allowFontScaling !== false}
      maxFontSizeMultiplier={maxFontSizeMultiplier ?? undefined}
      dynamicTypeRamp={dynamicTypeRamp}
      adjustsFontSizeToFit={adjustsFontSizeToFit}
      minimumFontScale={minimumFontScale}
      selectable={userSelect != null ? userSelect !== 'none' : selectable ?? undefined}
      textBreakStrategy={textBreakStrategy}
      lineBreakStrategyIOS={lineBreakStrategyIOS}
      dataDetectorType={dataDetectorType ?? undefined}
      onTextLayout={onTextLayout as never}
      accessible={accessible !== false}
      accessibilityLabel={ariaLabel ?? accessibilityLabel}
      accessibilityHint={accessibilityHint}
      accessibilityState={accessibilityState}
      accessibilityRole={accessibilityRole ?? (pressable && role == null ? 'link' : undefined)}
      role={role}
      nativeID={id ?? nativeID}
      testID={testID}>
      <TextAncestorContext value>
        <Text {...spanProps}>{children}</Text>
      </TextAncestorContext>
    </BalancedParagraph>
  );
}
