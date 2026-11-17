// PROTOTYPE (ticket 10): codegen spec for the iOS-only BalancedParagraph host component.
// interfaceOnly: the shadow node, descriptor and view are hand-written (ios/BalancedParagraph.mm),
// subclassing RN's Paragraph. This spec only feeds the static view config (JS) and the
// RCTThirdPartyComponentsProvider registration (codegenConfig.ios.components in package.json).
import type { CodegenTypes, HostComponent, ViewProps } from 'react-native';
import { codegenNativeComponent } from 'react-native';

type TextLayoutEvent = Readonly<{
  lines: {
    text: string;
    x: CodegenTypes.Double;
    y: CodegenTypes.Double;
    width: CodegenTypes.Double;
    height: CodegenTypes.Double;
    ascender: CodegenTypes.Double;
    descender: CodegenTypes.Double;
    capHeight: CodegenTypes.Double;
    xHeight: CodegenTypes.Double;
  }[];
}>;

export interface NativeProps extends ViewProps {
  // Paragraph-level props (ParagraphProps / ParagraphAttributes) that must sit on the host
  // paragraph, not on the inner virtual Text.
  numberOfLines?: CodegenTypes.Int32;
  ellipsizeMode?: CodegenTypes.WithDefault<'head' | 'middle' | 'tail' | 'clip', 'tail'>;
  allowFontScaling?: CodegenTypes.WithDefault<boolean, true>;
  maxFontSizeMultiplier?: CodegenTypes.Double;
  dynamicTypeRamp?: string;
  adjustsFontSizeToFit?: boolean;
  minimumFontScale?: CodegenTypes.Double;
  selectable?: boolean;
  disabled?: boolean;
  textBreakStrategy?: string;
  lineBreakStrategyIOS?: string;
  dataDetectorType?: string;
  onTextLayout?: CodegenTypes.DirectEventHandler<TextLayoutEvent>;
}

export default codegenNativeComponent<NativeProps>('BalancedParagraph', {
  interfaceOnly: true,
  excludedPlatforms: ['android'],
}) as HostComponent<NativeProps>;
