import { useState } from 'react';
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';

// Test strings for balance behaviour: short/long, multi-line, mixed scripts, RTL, emoji.
const SAMPLES: {
  label: string;
  text: string;
  fontSize?: number;
  fontFamily?: string;
  textAlign?: 'center';
}[] = [
  {
    label: 'Centred headline',
    text: 'Balanced text wrapping keeps centred headlines tidy',
    fontSize: 26,
    textAlign: 'center',
  },
  { label: 'Short headline', text: 'Balanced text wrapping for React Native', fontSize: 28 },
  {
    label: 'Long headline',
    text: 'The quick brown fox jumps over the lazy dog while the rest of the pack watches from a distance',
    fontSize: 24,
  },
  {
    label: 'Paragraph',
    text: 'Text balancing distributes words evenly across lines so that no single line is noticeably shorter than the others, avoiding orphans and ragged endings.',
    fontSize: 16,
  },
  {
    label: 'Single long word',
    text: 'Supercalifragilisticexpialidocious is a very long word',
    fontSize: 22,
  },
  {
    label: 'Emoji',
    text: 'Shipping balanced text 🚀 to every screen 🎉 on every device 📱 today',
    fontSize: 22,
  },
  {
    label: 'RTL (Arabic)',
    text: 'تغليف النص المتوازن لتطبيقات رياكت نيتف على جميع الأجهزة والشاشات',
    fontSize: 22,
  },
  {
    label: 'Mixed font',
    text: 'Monospaced text balances differently than proportional text does',
    fontSize: 22,
    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace' }),
  },
  // PROTOTYPE (ticket 08): multi-paragraph text; squeeze shares one strip, min-raggedness plans per paragraph.
  {
    label: 'Multi-paragraph',
    text: 'A short first paragraph that wraps onto two lines.\nThe second paragraph is a fair bit longer, so it wraps onto three or maybe four lines at this width.',
    fontSize: 17,
  },
];

// PROTOTYPE (ticket 08): balance mode. iOS min-raggedness is flagged by the Android-only
// android_hyphenationFrequency="full" (parsed into ParagraphAttributes on iOS, otherwise unused).
type Mode = 'off' | 'squeeze' | 'minrag';
const MODES: Mode[] = ['off', 'squeeze', 'minrag'];
function modeProps(mode: Mode): object {
  return {
    textBreakStrategy: mode === 'off' ? 'highQuality' : 'balanced',
    ...(Platform.OS === 'ios' && mode === 'minrag' ? { android_hyphenationFrequency: 'full' } : {}),
  };
}
const COMPARE: Mode[] = Platform.OS === 'ios' ? ['squeeze', 'minrag'] : ['squeeze'];
const MODE_LABEL: Record<Mode, string> =
  Platform.OS === 'ios'
    ? { off: 'off', squeeze: 'squeeze', minrag: 'min-raggedness' }
    : { off: 'off', squeeze: 'balanced', minrag: 'balanced' };

const WIDTHS = [320, 240, 180];

// PROTOTYPE (ticket 04): checks hit-testing and onTextLayout agree with the balanced draw.
function HitTestProbe({ mode }: { mode: Mode }) {
  const [taps, setTaps] = useState(0);
  const [lines, setLines] = useState('');
  return (
    <View style={styles.group}>
      <Text style={styles.label}>Hit-test + onTextLayout (tap the blue span)</Text>
      <View style={styles.box}>
        <Text
          key={mode}
          {...modeProps(mode)}
          onTextLayout={(e) =>
            setLines(e.nativeEvent.lines.map((l) => `${Math.round(l.width)}`).join(' / '))
          }
          style={{ width: 240, fontSize: 20, color: '#111' }}>
          Balanced lines should still route taps to the{' '}
          <Text style={{ color: '#06c' }} onPress={() => setTaps((t) => t + 1)}>
            right nested span
          </Text>{' '}
          at the end
        </Text>
      </View>
      <Text style={styles.width}>
        taps: {taps} · line widths: {lines}
      </Text>
    </View>
  );
}

// PROTOTYPE (ticket 06): press highlight on a nested span that wraps across lines.
// `pinned` forces the native isHighlighted attribute (normally only set while pressed) so the
// highlight can be screenshotted; the unpinned span is the real pressable one.
const HIGHLIGHT_CASES: {
  label: string;
  before: string;
  span: string;
  after: string;
  textAlign?: 'center' | 'right';
  writingDirection?: 'rtl';
}[] = [
  {
    label: 'LTR',
    before: 'Balanced lines keep the pressed',
    span: 'nested span highlight inside the narrowed',
    after: 'edge of the text',
  },
  {
    label: 'Centred',
    before: 'Balanced lines keep the pressed',
    span: 'nested span highlight inside the narrowed',
    after: 'edge of the text',
    textAlign: 'center',
  },
  {
    label: 'Right-aligned',
    before: 'Balanced lines keep the pressed',
    span: 'nested span highlight inside the narrowed',
    after: 'edge of the text',
    textAlign: 'right',
  },
  {
    label: 'RTL (Arabic)',
    before: 'تغليف النص المتوازن',
    span: 'لتطبيقات رياكت نيتف على جميع',
    after: 'الأجهزة والشاشات',
  },
  {
    label: 'RTL writingDirection',
    before: 'تغليف النص المتوازن',
    span: 'لتطبيقات رياكت نيتف على جميع',
    after: 'الأجهزة والشاشات',
    writingDirection: 'rtl',
  },
];

function HighlightProbe({ mode }: { mode: Mode }) {
  const [taps, setTaps] = useState(0);
  return (
    <View style={styles.group}>
      <Text style={styles.label}>Wrapped span highlight (orange = pinned, blue = press) · taps: {taps}</Text>
      {HIGHLIGHT_CASES.map((c) => (
        <View key={c.label} style={{ flexDirection: 'row', gap: 8 }}>
          {[true, false].map((pinned) => (
            <View key={String(pinned)} style={styles.box}>
              <Text style={styles.width}>{c.label} 170pt</Text>
              <Text
                key={mode}
          {...modeProps(mode)}
                style={{ width: 170, fontSize: 17, color: '#111', textAlign: c.textAlign, writingDirection: c.writingDirection }}>
                {c.before}{' '}
                {pinned ? (
                  <Text style={{ color: '#c60' }} {...({ isHighlighted: true } as object)}>
                    {c.span}
                  </Text>
                ) : (
                  <Text style={{ color: '#06c' }} onPress={() => setTaps((t) => t + 1)}>
                    {c.span}
                  </Text>
                )}{' '}
                {c.after}
              </Text>
            </View>
          ))}
        </View>
      ))}
    </View>
  );
}

// PROTOTYPE (ticket 06): adjustsFontSizeToFit and numberOfLines interaction.
const FIT_TEXT =
  'The quick brown fox jumps over the lazy dog while the rest of the pack watches from a distance';
const FIT_CASES: { label: string; props: object; style: object }[] = [
  {
    label: 'adjustsFontSizeToFit, 240x90 box',
    props: { adjustsFontSizeToFit: true },
    style: { width: 240, height: 90, fontSize: 28 },
  },
  {
    label: 'adjustsFontSizeToFit + numberOfLines=2, 240pt',
    props: { adjustsFontSizeToFit: true, numberOfLines: 2 },
    style: { width: 240, fontSize: 28 },
  },
  {
    label: 'numberOfLines=2 truncates (expect no balance)',
    props: { numberOfLines: 2 },
    style: { width: 240, fontSize: 22 },
  },
  {
    label: 'numberOfLines=5 fits (expect balance)',
    props: { numberOfLines: 5 },
    style: { width: 240, fontSize: 22 },
  },
];

function FitProbe({ mode }: { mode: Mode }) {
  return (
    <View style={styles.group}>
      <Text style={styles.label}>Font scaling + numberOfLines</Text>
      {FIT_CASES.map((c) => (
        <View key={c.label} style={styles.box}>
          <Text style={styles.width}>{c.label}</Text>
          <Text
            key={mode}
          {...modeProps(mode)}
            {...c.props}
            style={[{ color: '#111', backgroundColor: '#f6f6f6' }, c.style]}>
            {FIT_TEXT}
          </Text>
        </View>
      ))}
    </View>
  );
}

// TODO(ticket 03): android compares `textBreakStrategy`. Replace with the library's
// `Text` + `balance` prop once it exists.
export default function App() {
  return (
    <SafeAreaProvider>
      <Screen />
    </SafeAreaProvider>
  );
}

function Screen() {
  const insets = useSafeAreaInsets();
  const [mode, setMode] = useState<Mode>('squeeze');
  const [probes, setProbes] = useState(false);
  const rows: Mode[] = mode === 'off' ? ['off'] : COMPARE;

  return (
    <View style={styles.container}>
      <View style={[styles.bar, { paddingTop: styles.bar.padding + insets.top }]}>
        <Text style={styles.barText}>
          {Platform.OS === 'android' ? 'textBreakStrategy' : 'iOS 08: squeeze vs min-rag'}
        </Text>
        <Pressable
          onPress={() => setMode((m) => (m === 'off' ? 'squeeze' : 'off'))}
          style={styles.toggle}>
          <Text>{mode === 'off' ? 'OFF' : 'ON'}</Text>
        </Pressable>
        <Pressable onPress={() => setProbes((p) => !p)} style={styles.toggle}>
          <Text>probes: {probes ? (mode === 'off' ? 'off' : 'min-rag') : 'hidden'}</Text>
        </Pressable>
      </View>
      <ScrollView
        contentContainerStyle={[
          styles.scroll,
          { paddingBottom: styles.scroll.padding + insets.bottom },
        ]}>
        {probes && <HighlightProbe mode={mode === 'off' ? 'off' : 'minrag'} />}
        {probes && <FitProbe mode={mode === 'off' ? 'off' : 'minrag'} />}
        {probes && <HitTestProbe mode={mode === 'off' ? 'off' : 'minrag'} />}
        {SAMPLES.map((s) => (
          <View key={s.label} style={styles.group}>
            <Text style={styles.label}>{s.label}</Text>
            {WIDTHS.map((w) => (
              <View key={w} style={{ gap: 4 }}>
                {rows.map((m) => (
                  <View key={m} style={styles.box}>
                    <Text style={styles.width}>
                      {w}pt · {MODE_LABEL[m]}
                    </Text>
                    <Text
                      {...modeProps(m)}
                      style={{
                        width: w,
                        fontSize: s.fontSize,
                        fontFamily: s.fontFamily,
                        textAlign: s.textAlign,
                        color: '#111',
                        backgroundColor: m === 'minrag' ? '#eef6ff' : '#f6f6f6',
                      }}>
                      {s.text}
                    </Text>
                  </View>
                ))}
              </View>
            ))}
          </View>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#eee' },
  bar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
    backgroundColor: '#fff',
  },
  barText: { fontSize: 16, fontWeight: '600' },
  scroll: { padding: 16, gap: 16 },
  group: { backgroundColor: '#fff', borderRadius: 10, padding: 12, gap: 8 },
  label: { fontSize: 14, fontWeight: '700', color: '#555' },
  box: {
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#bbb',
    alignSelf: 'flex-start',
    padding: 4,
  },
  width: { fontSize: 10, color: '#999' },
  toggle: { paddingHorizontal: 10, paddingVertical: 4, borderWidth: 1, borderColor: '#999', borderRadius: 6 },
});
