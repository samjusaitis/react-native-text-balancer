import { type ReactNode, useEffect, useState } from 'react';
import { Platform, ScrollView, StyleSheet, Text, type TextLayoutEvent, View } from 'react-native';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';

import { check, distinct, undistinct, type Expectation, type Line, type Result } from './checks';
import { SAMPLES, type Sample } from './samples';

// Self-checking test screen. Each sample renders three times at a fixed width:
// - stock: no textBreakStrategy;
// - twin: textBreakStrategy="highQuality", which must render exactly like stock;
// - test: textBreakStrategy="balanced", checked against the sample's expectation.
export default function App() {
  return (
    <SafeAreaProvider>
      <Screen />
    </SafeAreaProvider>
  );
}

type Results = Record<string, { unchanged?: Result; expected?: Result }>;

function Screen() {
  const insets = useSafeAreaInsets();
  const [results, setResults] = useState<Results>({});

  const checks = Object.values(results).flatMap((r) => [r.unchanged, r.expected]);
  const done = checks.filter(Boolean).length === SAMPLES.length * 2;
  const passed = checks.filter((r) => r?.pass).length;

  useEffect(() => {
    if (done) {
      console.log(`[test screen] ${Platform.OS}: ${passed}/${checks.length} passed`);
      for (const s of SAMPLES) {
        const r = results[s.id];
        console.log(
          `[test screen] ${s.id}: unchanged ${mark(r.unchanged)} · ${s.expect} ${mark(r.expected)} (${r.expected?.detail})`
        );
      }
    }
  }, [done]);

  return (
    <View style={styles.container}>
      <View style={[styles.bar, { paddingTop: 12 + insets.top }]}>
        <Text style={styles.barText}>textBreakStrategy="balanced" · {Platform.OS}</Text>
        <Text style={styles.barText}>{done ? `${passed}/${checks.length} ✅` : '…'}</Text>
      </View>
      <ScrollView contentContainerStyle={[styles.scroll, { paddingBottom: 16 + insets.bottom }]}>
        {SAMPLES.map((s) => (
          <SampleCard
            key={s.id}
            sample={s}
            onResult={(key, result) =>
              setResults((prev) => ({ ...prev, [s.id]: { ...prev[s.id], [key]: result } }))
            }
          />
        ))}
      </ScrollView>
    </View>
  );
}

const mark = (r?: Result) => (r ? (r.pass ? '✅' : '❌') : '…');

type Rendering = 'stock' | 'twin' | 'test';

function SampleCard({
  sample,
  onResult,
}: {
  sample: Sample;
  onResult: (key: 'unchanged' | 'expected', result: Result) => void;
}) {
  const [lines, setLines] = useState<Partial<Record<Rendering, Line[]>>>({});
  const [pressed, setPressed] = useState<string>();

  const onLayout = (rendering: Rendering) => (e: TextLayoutEvent) => {
    const next = e.nativeEvent.lines.map((l) => ({
      text: undistinct(l.text),
      width: l.width,
    }));
    setLines((prev) => ({ ...prev, [rendering]: next }));
  };

  const { stock, twin, test } = lines;
  const unchanged = stock && twin ? check('unchanged', stock, twin) : undefined;
  const expected = stock && test ? check(sample.expect, stock, test) : undefined;

  useEffect(() => {
    if (unchanged) onResult('unchanged', unchanged);
  }, [unchanged?.pass, unchanged?.detail]);
  useEffect(() => {
    if (expected) onResult('expected', expected);
  }, [expected?.pass, expected?.detail]);

  const textStyle = [styles.text, sample.style, { width: sample.width }];
  const content = (variant: number) =>
    withLinks(distinct(sample.text, variant), sample.links, (link) => setPressed(link));

  return (
    <View style={styles.card}>
      <Text style={styles.label}>
        {sample.label} · {sample.width}pt
      </Text>
      <Badge name="unchanged" result={unchanged} />
      <Badge name={sample.expect} result={expected} />

      <Text style={styles.caption}>stock</Text>
      <View style={styles.box}>
        <Text style={textStyle} {...sample.props} onTextLayout={onLayout('stock')}>
          {content(0)}
        </Text>
      </View>

      <Text style={styles.caption}>textBreakStrategy="balanced"</Text>
      <View style={styles.box}>
        <Text
          style={textStyle}
          {...sample.props}
          textBreakStrategy="balanced"
          onTextLayout={onLayout('test')}>
          {content(1)}
        </Text>
      </View>
      {sample.links && <Text style={styles.caption}>last press: {pressed ?? 'none'}</Text>}

      {/* The unchanged twin: hidden from view, but still laid out so onTextLayout fires. */}
      <View style={styles.hidden} pointerEvents="none">
        <Text
          style={textStyle}
          {...sample.props}
          textBreakStrategy="highQuality"
          onTextLayout={onLayout('twin')}>
          {content(2)}
        </Text>
      </View>
    </View>
  );
}

// Splits `text` so each of `links` becomes a nested pressable span.
function withLinks(text: string, links: string[] | undefined, onPress: (link: string) => void) {
  if (!links?.length) return text;
  const parts: ReactNode[] = [];
  let rest = text;
  for (const link of links) {
    const at = rest.indexOf(link);
    if (at < 0) continue;
    parts.push(rest.slice(0, at));
    parts.push(
      <Text key={link} style={styles.link} onPress={() => onPress(link)}>
        {link}
      </Text>
    );
    rest = rest.slice(at + link.length);
  }
  parts.push(rest);
  return parts;
}

function Badge({ name, result }: { name: Expectation; result?: Result }) {
  return (
    <Text style={[styles.badge, result && !result.pass && styles.fail]}>
      {mark(result)} {name}
      {result ? ` · ${result.detail}` : ''}
    </Text>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#eee' },
  bar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingBottom: 12,
    backgroundColor: '#fff',
  },
  barText: { fontSize: 15, fontWeight: '600', color: '#111' },
  scroll: { padding: 16, gap: 16 },
  card: { backgroundColor: '#fff', borderRadius: 10, padding: 12, gap: 6 },
  label: { fontSize: 14, fontWeight: '700', color: '#555' },
  badge: { fontSize: 12, color: '#262' },
  fail: { color: '#b00' },
  caption: { fontSize: 10, color: '#999', marginTop: 4 },
  box: {
    alignSelf: 'flex-start',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#bbb',
  },
  text: { color: '#111' },
  link: { color: '#06c', textDecorationLine: 'underline' },
  hidden: { position: 'absolute', opacity: 0, left: 12, top: 12 },
});
