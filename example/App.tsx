import * as React from 'react';
import { useState } from 'react';
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';
// PROTOTYPE (ticket 10): deep import from the bun-copied package (rsync src/ after edits).
import { BalancedText } from 'react-native-text-balancer/src/BalancedText';

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

// PROTOTYPE (ticket 10): rows per sample/width.
//   stock     plain RN <Text>
//   stockFlag plain RN <Text textBreakStrategy="balanced" android_hyphenationFrequency="full">
//             (the 04-08 swizzle flags; must render exactly like `stock` now)
//   ours      <BalancedText balance> -> BalancedParagraph host component
type Row = 'stock' | 'stockFlag' | 'ours';
const ROWS: Row[] = ['stock', 'stockFlag', 'ours'];
const ROW_LABEL: Record<Row, string> = {
  stock: 'RN Text',
  stockFlag: 'RN Text textBreakStrategy=balanced',
  ours: 'BalancedParagraph',
};
const STOCK_FLAG = { textBreakStrategy: 'balanced', android_hyphenationFrequency: 'full' } as const;

const WIDTHS = [320, 240, 180];

// Count "Text strings must be rendered within a <Text>" errors (criterion 2a).
let textStringErrors = 0;
const origError = console.error;
console.error = (...args: unknown[]) => {
  if (String(args[0]).includes('Text strings must be rendered')) textStringErrors++;
  origError(...args);
};

type Lines = Record<string, string>;
const layoutKey = (sample: string, w: number, row: Row) => `${sample}|${w}|${row}`;
const linesOf = (e: { nativeEvent: { lines: { text: string; width: number }[] } }) =>
  e.nativeEvent.lines.map((l) => `${l.text.trimEnd()}@${Math.round(l.width)}`).join(' / ');

function SampleText({ row, ...props }: { row: Row } & React.ComponentProps<typeof Text>) {
  if (row === 'ours') return <BalancedText balance {...props} />;
  return <Text {...(row === 'stockFlag' ? STOCK_FLAG : {})} {...props} />;
}

function Probe({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.group}>
      <Text style={styles.label}>{title}</Text>
      {children}
    </View>
  );
}

function Pair({ render }: { render: (row: Row) => React.ReactNode }) {
  return (
    <View style={{ flexDirection: 'row', gap: 8 }}>
      {(['stock', 'ours'] as Row[]).map((r) => (
        <View key={r} style={styles.box}>
          <Text style={styles.width}>{ROW_LABEL[r]}</Text>
          {render(r)}
        </View>
      ))}
    </View>
  );
}

function PressProbe() {
  const [taps, setTaps] = useState<Record<string, number>>({});
  const [layout, setLayout] = useState<Record<string, string>>({});
  const tap = (k: string) => setTaps((t) => ({ ...t, [k]: (t[k] ?? 0) + 1 }));
  return (
    <Probe title={`Nested onPress spans + highlight · taps ${JSON.stringify(taps)}`}>
      <Pair
        render={(r) => (
          <SampleText
            row={r}
            onTextLayout={(e) => setLayout((l) => ({ ...l, [r]: linesOf(e) }))}
            style={{ width: 160, fontSize: 17, color: '#111' }}>
            Balanced lines route taps to the{' '}
            <Text style={{ color: '#06c' }} onPress={() => tap(`${r}:span`)}>
              right nested span
            </Text>{' '}
            and the rest of the text
          </SampleText>
        )}
      />
      <Pair
        render={(r) => (
          <SampleText
            row={r}
            onPress={() => tap(`${r}:root`)}
            style={{ width: 160, fontSize: 17, color: '#060' }}>
            Whole text pressable (root onPress) wraps to lines
          </SampleText>
        )}
      />
      <Text style={styles.width}>onTextLayout stock: {layout.stock}</Text>
      <Text style={styles.width}>onTextLayout ours: {layout.ours}</Text>
    </Probe>
  );
}

function MiscProbe() {
  const [balanced, setBalanced] = useState(true);
  return (
    <>
      <Probe title={`Raw string child · "Text strings" errors so far: ${textStringErrors}`}>
        <Pair render={(r) => <SampleText row={r} style={{ width: 160, fontSize: 17 }}>Just a raw string that wraps onto lines</SampleText>} />
      </Probe>
      <Probe title="selectable (long-press → Copy)">
        <Pair render={(r) => <SampleText row={r} selectable style={{ width: 160, fontSize: 17 }}>Selectable text that should offer a copy menu</SampleText>} />
      </Probe>
      <Probe title="Inline View attachment">
        <Pair
          render={(r) => (
            <SampleText row={r} style={{ width: 160, fontSize: 17 }}>
              Inline <View style={{ width: 24, height: 14, backgroundColor: '#c33' }} /> attachment inside wrapped text here
            </SampleText>
          )}
        />
      </Probe>
      <Probe title="Accessibility (link span + label)">
        <Pair
          render={(r) => (
            <SampleText row={r} accessibilityHint="hint" style={{ width: 160, fontSize: 17 }}>
              Read the{' '}
              <Text style={{ color: '#06c' }} onPress={() => {}}>
                terms of service
              </Text>{' '}
              before continuing please
            </SampleText>
          )}
        />
      </Probe>
      <Probe title="Toggle balance (remount)">
        <Pressable onPress={() => setBalanced((b) => !b)} style={styles.toggle}>
          <Text>balance: {String(balanced)}</Text>
        </Pressable>
        <BalancedText balance={balanced} style={{ width: 240, fontSize: 22, backgroundColor: '#f6f6f6' }}>
          The quick brown fox jumps over the lazy dog while the pack watches
        </BalancedText>
      </Probe>
    </>
  );
}

// adjustsFontSizeToFit and numberOfLines (from 06), stock vs ours.
const FIT_TEXT =
  'The quick brown fox jumps over the lazy dog while the rest of the pack watches from a distance';
const FIT_CASES: { label: string; props: object; style: object }[] = [
  { label: 'adjustsFontSizeToFit, 170x90 box', props: { adjustsFontSizeToFit: true }, style: { width: 170, height: 90, fontSize: 28 } },
  { label: 'adjustsFontSizeToFit + numberOfLines=2', props: { adjustsFontSizeToFit: true, numberOfLines: 2 }, style: { width: 170, fontSize: 28 } },
  { label: 'numberOfLines=2 truncates (no balance)', props: { numberOfLines: 2 }, style: { width: 170, fontSize: 20 } },
  { label: 'numberOfLines=6 fits (balance)', props: { numberOfLines: 6 }, style: { width: 170, fontSize: 20 } },
];

function FitProbe() {
  return (
    <Probe title="Font scaling + numberOfLines">
      {FIT_CASES.map((c) => (
        <View key={c.label} style={{ gap: 2 }}>
          <Text style={styles.width}>{c.label}</Text>
          <Pair render={(r) => <SampleText row={r} {...c.props} style={[{ color: '#111', backgroundColor: '#f6f6f6' }, c.style]}>{FIT_TEXT}</SampleText>} />
        </View>
      ))}
    </Probe>
  );
}


// PROTOTYPE (ticket 14): one sample per script/feature for ticket 11's plan inputs.
const T14: {
  label: string;
  fontSize: number;
  props?: object;
  children: React.ReactNode;
  text: string; // for logs
}[] = [
  {
    label: 'Hyphenated compounds',
    fontSize: 22,
    text: 'hyphen',
    children: 'State-of-the-art, well-known and up-to-date cross-platform text-wrapping for real-world apps',
  },
  {
    label: 'Japanese (kinsoku)',
    fontSize: 20,
    text: 'ja',
    children: '吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。',
  },
  {
    label: 'Chinese',
    fontSize: 20,
    text: 'zh',
    children: '平衡文本换行让标题在每一行上看起来更加整齐，避免最后一行只剩下一两个字的情况。',
  },
  {
    label: 'Korean (default)',
    fontSize: 20,
    text: 'ko',
    children: '균형 잡힌 텍스트 줄바꿈은 제목을 여러 줄에 걸쳐 고르게 나누어 마지막 줄에 단어 하나만 남는 것을 막아 줍니다.',
  },
  {
    label: 'Korean (hangul-word)',
    fontSize: 20,
    text: 'ko-hw',
    props: { lineBreakStrategyIOS: 'hangul-word' },
    // Different string on purpose: RN's TextMeasureCache ignores lineBreakStrategy, so an identical
    // string would reuse the default sample's measurement and lines (stock RN bug, found in ticket 14).
    children: '균형 잡힌 텍스트 줄바꿈은 제목을 여러 줄에 걸쳐 고르게 나누어 마지막 줄에 단어 하나만 남는 것을 막아 줍니다!',
  },
  {
    label: 'Thai',
    fontSize: 20,
    text: 'th',
    children: 'การตัดบรรทัดข้อความให้สมดุลช่วยให้หัวข้อดูเรียบร้อยบนทุกหน้าจอและทุกอุปกรณ์ของผู้ใช้',
  },
  {
    label: 'Arabic + English',
    fontSize: 20,
    text: 'ar-en',
    children: 'استخدم React Native لبناء تطبيقات iOS و Android بنص متوازن على كل الشاشات',
  },
  {
    label: 'View inside Text',
    fontSize: 18,
    text: 'view',
    children: (
      <>
        Inline <View style={{ width: 24, height: 14, backgroundColor: '#c33' }} /> attachment inside wrapped text here and a
        bit more text after it
      </>
    ),
  },
  {
    label: 'Soft hyphen',
    fontSize: 20,
    text: 'shy',
    children:
      'Extra­ordinarily long compounds like Donau­dampf­schiff­fahrts­gesell­schaft test soft hyphens',
  },
  {
    label: 'Tab (skipped)',
    fontSize: 18,
    text: 'tab',
    children: 'Name:\tA tab makes widths depend on position, so this paragraph is skipped by the plan',
  },
  // Ticket 15 rule: pushOut is cleared only while a verified plan is applied.
  {
    label: 'push-out (balanced, pushOut cleared)',
    fontSize: 20,
    text: 'push',
    props: { lineBreakStrategyIOS: 'push-out' },
    children: 'Push-out line breaking fights the plan so this paragraph keeps stock wrapping',
  },
  {
    label: 'push-out + tab (stock, pushOut kept)',
    fontSize: 18,
    text: 'push-tab',
    props: { lineBreakStrategyIOS: 'push-out' },
    // Same words as the tab sample plus "too": distinct string so RN's measure cache (which ignores
    // lineBreakStrategy) doesn't reuse the plain tab sample's layout.
    children: 'Name:\tA tab makes widths depend on position, so this paragraph is skipped by the plan\u2060',
  },
  {
    label: 'tab, no push-out (reference for the row above)',
    fontSize: 18,
    text: 'tab2',
    children: 'Name:\tA tab makes widths depend on position, so this paragraph is skipped by the plan\u2060\u2060',
  },
  {
    label: 'no push-out (reference for push-out balanced row)',
    fontSize: 20,
    text: 'push-ref',
    children: 'Push-out line breaking fights the plan so this paragraph keeps stock wrapping\u2060',
  },
];

function T14Samples({ record, lines }: { record: (k: string, v: string) => void; lines: Lines }) {
  return (
    <>
      {T14.map((s) => (
        <View key={s.label} style={styles.group}>
          <Text style={styles.label}>{s.label}</Text>
          {WIDTHS.map((w) => {
            const a = lines[layoutKey(s.label, w, 'stock')];
            const c = lines[layoutKey(s.label, w, 'ours')];
            return (
              <View key={w} style={{ gap: 4 }}>
                <Text style={styles.width}>
                  {w}pt · ours {a && c ? (a === c ? 'same as stock' : 'balanced') : '…'}
                </Text>
                {(['stock', 'ours'] as Row[]).map((r) => (
                  <View key={r} style={styles.box}>
                    <Text style={styles.width}>{ROW_LABEL[r]}</Text>
                    <SampleText
                      row={r}
                      {...s.props}
                      onTextLayout={(e) => record(layoutKey(s.label, w, r), linesOf(e))}
                      style={{
                        width: w,
                        fontSize: s.fontSize,
                        color: '#111',
                        backgroundColor: r === 'ours' ? '#eef6ff' : '#f6f6f6',
                      }}>
                      {s.children}
                    </SampleText>
                  </View>
                ))}
              </View>
            );
          })}
        </View>
      ))}
    </>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <Screen />
    </SafeAreaProvider>
  );
}

function Screen() {
  const insets = useSafeAreaInsets();
  const [probes, setProbes] = useState(false);
  const [lines, setLines] = useState<Lines>({});
  const record = (k: string, v: string) => setLines((l) => (l[k] === v ? l : { ...l, [k]: v }));
  const total = SAMPLES.length * WIDTHS.length;
  const keys = SAMPLES.flatMap((s) => WIDTHS.map((w) => [s.label, w] as const));
  const done = keys.filter(([s, w]) => ROWS.every((r) => lines[layoutKey(s, w, r)]));
  const same = done.filter(([s, w]) => lines[layoutKey(s, w, 'stock')] === lines[layoutKey(s, w, 'stockFlag')]);
  React.useEffect(() => {
    if (done.length === total) {
      console.log(`[iso] stock==flagged ${same.length}/${total}`);
      for (const [s, w] of keys) {
        console.log(`[iso] ${s} ${w} stock: ${lines[layoutKey(s, w, 'stock')]}`);
        console.log(`[iso] ${s} ${w} ours : ${lines[layoutKey(s, w, 'ours')]}`);
      }
    }
  }, [done.length]);
  const t14Keys = T14.flatMap((s) => WIDTHS.map((w) => [s.label, w] as const));
  const t14Done = t14Keys.filter(([s, w]) => lines[layoutKey(s, w, 'stock')] && lines[layoutKey(s, w, 'ours')]);
  React.useEffect(() => {
    if (t14Done.length !== t14Keys.length) return;
    // Dump once layouts have been quiet for 2s (late re-layouts included).
    const id = setTimeout(() => {
      console.log('[t14] ---- dump ----');
      for (const [s, w] of t14Keys) {
        console.log(`[t14] ${s} ${w} stock: ${lines[layoutKey(s, w, 'stock')]}`);
        console.log(`[t14] ${s} ${w} ours : ${lines[layoutKey(s, w, 'ours')]}`);
      }
    }, 2000);
    return () => clearTimeout(id);
  }, [lines]);

  return (
    <View style={styles.container}>
      <View style={[styles.bar, { paddingTop: styles.bar.padding + insets.top }]}>
        <Text style={styles.barText}>iOS 14: plan inputs</Text>
        <Pressable onPress={() => setProbes((p) => !p)} style={styles.toggle}>
          <Text>{probes ? 'samples' : 'probes'}</Text>
        </Pressable>
      </View>
      <ScrollView
        contentContainerStyle={[styles.scroll, { paddingBottom: styles.scroll.padding + insets.bottom }]}>
        <Text style={styles.label}>
          isolation: stock == flagged stock in {same.length}/{done.length} (of {total})
        </Text>
        {probes && <PressProbe />}
        {probes && <MiscProbe />}
        {probes && <FitProbe />}
        {!probes && <T14Samples record={record} lines={lines} />}
        {!probes &&
          SAMPLES.map((s) => (
            <View key={s.label} style={styles.group}>
              <Text style={styles.label}>{s.label}</Text>
              {WIDTHS.map((w) => {
                const a = lines[layoutKey(s.label, w, 'stock')];
                const b = lines[layoutKey(s.label, w, 'stockFlag')];
                const c = lines[layoutKey(s.label, w, 'ours')];
                return (
                  <View key={w} style={{ gap: 4 }}>
                    <Text style={styles.width}>
                      {w}pt · stock vs flagged stock: {a && b ? (a === b ? 'IDENTICAL' : 'DIFFERENT') : '…'} · ours{' '}
                      {a && c ? (a === c ? 'same as stock' : 'balanced') : '…'}
                    </Text>
                    {ROWS.map((r) => (
                      <View key={r} style={styles.box}>
                        <Text style={styles.width}>{ROW_LABEL[r]}</Text>
                        <SampleText
                          row={r}
                          onTextLayout={(e) => record(layoutKey(s.label, w, r), linesOf(e))}
                          style={{
                            width: w,
                            fontSize: s.fontSize,
                            fontFamily: s.fontFamily,
                            textAlign: s.textAlign,
                            color: '#111',
                            backgroundColor: r === 'ours' ? '#eef6ff' : '#f6f6f6',
                          }}>
                          {s.text}
                        </SampleText>
                      </View>
                    ))}
                  </View>
                );
              })}
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
