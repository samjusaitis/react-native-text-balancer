import type { TextProps, TextStyle } from 'react-native';

import type { Expectation } from './checks';

// One test-screen sample: a string at a fixed width and text size (Dynamic Type doesn't scale it), and what `textBreakStrategy="balanced"`
// should do to it compared with default wrapping. Later build tickets append their samples here.
// A 'balanced' sample must wrap raggedly under default wrapping on both platforms: if default wrapping is
// already as even as it can be, balancing rightly changes nothing and the check reads ❌.
export type Sample = {
  id: string;
  label: string;
  text: string;
  width: number; // the Text's width, or its maximum width when `noFixedWidth` is set
  // Set no width, only `width` as a maximum, to check that the box keeps its default size. Shown
  // beside a neighbouring view.
  noFixedWidth?: boolean;
  expect: Exclude<Expectation, 'unchanged'>;
  style?: TextStyle;
  // Extra props for every rendering of the sample (for example `selectable`).
  props?: TextProps;
  // Substrings of `text` rendered as nested pressable spans, for checking taps and the press
  // highlight by eye.
  links?: string[];
  // A `View` rendered inside the `Text`, straight after the first occurrence of `after`.
  inlineView?: { after: string; width: number; height: number };
  // Japanese line-start rules: the balanced copy must not start a line with closing punctuation
  // or small kana.
  kinsoku?: boolean;
};

export const SAMPLES: Sample[] = [
  {
    id: 'latin-left',
    label: 'Latin headline, left',
    text: 'Balanced text wrapping keeps written headlines tidy on every device',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 24 },
  },
  {
    id: 'latin-centre',
    label: 'Latin headline, centred',
    text: 'Balanced text wrapping keeps centred headlines tidy on every device',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 24, textAlign: 'center' },
  },
  {
    id: 'latin-right',
    label: 'Latin headline, right-aligned',
    text: 'Right-aligned headlines keep their right edge when the lines balance',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 24, textAlign: 'right' },
  },
  {
    id: 'latin-rtl',
    label: 'Latin headline, RTL direction',
    text: 'A right-to-left paragraph direction keeps its leading edge while balancing',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 24, writingDirection: 'rtl' },
  },
  {
    id: 'multi-paragraph',
    label: 'Multi-paragraph',
    text:
      'Each paragraph balances on its own, so a short one is not left ragged.\n' +
      'The second paragraph is a little longer, which gives it a different number of lines to share out.',
    width: 220,
    expect: 'balanced',
    style: { fontSize: 16 },
  },
  {
    id: 'latin-no-fixed-width',
    label: 'Latin headline, no fixed width',
    text: 'Without a fixed width the box keeps its default size while this headline balances',
    width: 240,
    noFixedWidth: true,
    expect: 'balanced',
    style: { fontSize: 24 },
  },
  {
    id: 'pressable-spans',
    label: 'Nested pressable spans, selectable',
    text: 'Tap the linked words in this headline to check that presses still land on balanced lines',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 22 },
    props: { selectable: true },
    links: ['linked words', 'still land on balanced'],
  },
  {
    id: 'hyphenated',
    label: 'Hyphenated compounds',
    text: 'State-of-the-art, well-known and up-to-date cross-platform text-wrapping for real-world apps',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 22 },
  },
  {
    id: 'soft-hyphen',
    label: 'Soft-hyphen word',
    text: 'Soft hyphens let Donau\u00ADdampf\u00ADschiff\u00ADfahrts\u00ADgesell\u00ADschaft break',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 20 },
  },
  {
    id: 'japanese',
    label: 'Japanese, closing punctuation (kinsoku)',
    text: '吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 20 },
    kinsoku: true,
  },
  {
    id: 'chinese',
    label: 'Chinese',
    text: '平衡文本换行让标题在每一行上看起来更加整齐，避免最后一行只剩下一两个字的情况。',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 20 },
  },
  {
    id: 'korean',
    label: 'Korean, default',
    text: '균형 잡힌 텍스트 줄바꿈은 제목을 여러 줄에 걸쳐 고르게 나누어 마지막 줄에 단어 하나만 남는 것을 막아 줍니다.',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 20 },
  },
  {
    // A different string from the default sample: RN's measure cache ignores lineBreakStrategy.
    id: 'korean-hangul-word',
    label: 'Korean, hangul-word',
    text: '한글 단어 단위 줄바꿈에서도 제목이 고르게 나뉘어 보기 좋습니다.',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 20 },
    props: { lineBreakStrategyIOS: 'hangul-word' },
  },
  {
    id: 'thai',
    label: 'Thai',
    text: 'การตัดบรรทัดข้อความให้สมดุลช่วยให้หัวข้อดูเรียบร้อยบนทุกหน้าจอและทุกอุปกรณ์ของผู้ใช้',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 20 },
  },
  {
    id: 'arabic-english',
    label: 'Arabic mixed with English',
    text: 'استخدم React Native لبناء تطبيقات iOS و Android بنص متوازن على كل الشاشات',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 20 },
  },
  {
    id: 'inline-view',
    label: 'View inside Text',
    text: 'This headline has an inline badge and its lines still balance',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 20 },
    inlineView: { after: 'inline badge', width: 24, height: 14 },
  },
  {
    id: 'adjusts-font-size',
    label: 'adjustsFontSizeToFit, numberOfLines 3',
    text: 'A fitted headline scales its font down to fit three lines first, then balances those lines evenly',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 36 },
    props: { adjustsFontSizeToFit: true, numberOfLines: 3 },
  },
  {
    id: 'number-of-lines-fits',
    label: 'numberOfLines 3, fits',
    text: 'A clamped headline that fits within its line limit still balances its lines',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 22 },
    props: { numberOfLines: 3 },
  },
  {
    id: 'number-of-lines-truncates',
    label: 'numberOfLines 2, truncates',
    text: 'A clamped headline that runs past its line limit keeps default wrapping and the default ellipsis at the end of the last line',
    width: 240,
    expect: 'default',
    style: { fontSize: 22 },
    props: { numberOfLines: 2 },
  },
  {
    id: 'tab',
    label: 'Tab in the paragraph',
    text: 'Tabs\tkeep default wrapping because a tab stop moves with where the tab lands on its line',
    width: 240,
    expect: 'default',
    style: { fontSize: 20 },
  },
  {
    id: 'wide-word',
    label: 'Word wider than the box',
    text: 'Antidisestablishmentarianism-everywhere is one word wider than this box',
    width: 240,
    expect: 'default',
    style: { fontSize: 24 },
  },
  {
    // A different string from the other samples: RN's measure cache ignores lineBreakStrategy.
    id: 'push-out-balanced',
    label: 'push-out, balancing paragraph',
    text: 'With push-out set, this paragraph still balances because push-out is dropped while its breaks apply',
    width: 240,
    expect: 'balanced',
    style: { fontSize: 22 },
    props: { lineBreakStrategyIOS: 'push-out' },
  },
  {
    id: 'push-out-tab',
    label: 'push-out, tab paragraph (falls back)',
    text: 'With push-out set,\ta paragraph that falls back keeps push-out on its original style',
    width: 240,
    expect: 'default',
    style: { fontSize: 20 },
    props: { lineBreakStrategyIOS: 'push-out' },
  },
];

// A Dynamic Type sample: a balanced string that scales with the text size, at a fixed width. Its
// wrapping changes with the size, so it's checked for what holds at any size: the balanced copy
// is no worse than default wrapping, and matches a copy mounted fresh at the current size.
export type DynamicTypeSample = {
  id: string;
  label: string;
  text: string;
  width: number;
  style?: TextStyle;
};

export const DYNAMIC_TYPE_SAMPLES: DynamicTypeSample[] = [
  {
    id: 'dynamic-latin',
    label: 'Latin headline, scales with text size',
    text: 'Headlines rebalance whenever the reader picks a larger or smaller text size',
    width: 240,
    style: { fontSize: 22 },
  },
  {
    id: 'dynamic-japanese',
    label: 'Japanese, scales with text size',
    text: '文字の大きさを変えると、見出しの行の長さもそれに合わせて揃え直されます。',
    width: 240,
    style: { fontSize: 20 },
  },
  {
    id: 'dynamic-multi-paragraph',
    label: 'Multi-paragraph, scales with text size',
    text:
      'Every paragraph rebalances on its own when the text size changes.\n' +
      'A longer second paragraph wraps onto more lines, so it shares its words out differently.',
    width: 240,
    style: { fontSize: 16 },
  },
];
