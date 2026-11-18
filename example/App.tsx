import { type ReactNode, useEffect, useRef, useState } from 'react';
import {
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  type TextLayoutEvent,
  useWindowDimensions,
  View,
} from 'react-native';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';

import {
  check,
  distinct,
  kinsoku,
  noWorse,
  rebalanced,
  undistinct,
  type Line,
  type Result,
} from './checks';
import { DYNAMIC_TYPE_SAMPLES, type DynamicTypeSample, SAMPLES, type Sample } from './samples';

// Self-checking test screen. Each sample renders three times at a fixed width and a fixed text
// size (`allowFontScaling={false}`, since the samples are tuned to wrap raggedly at it):
// - default: no textBreakStrategy;
// - twin: textBreakStrategy="highQuality", which must render exactly like default;
// - test: textBreakStrategy="balanced", checked against the sample's expectation.
// Each Dynamic Type sample scales with the text size and renders three times too: default, a
// balanced copy that stays mounted through text size changes, and a balanced copy mounted fresh
// at the current size (see DynamicTypeCard).
export default function App() {
  return (
    <SafeAreaProvider>
      <Screen />
    </SafeAreaProvider>
  );
}

// Each sample's results by check name: unchanged and expected for a sample, rebalanced and valid
// for a Dynamic Type sample.
type Results = Record<string, Record<string, Result | undefined>>;

const TOTAL_CHECKS = (SAMPLES.length + DYNAMIC_TYPE_SAMPLES.length) * 2;

// The summary goes to the native log, where `example/scripts/sweep-text-sizes.sh` reads it. A
// Release build passes only console.error there (and has no LogBox to show it); Debug logs
// console.log too.
const report = __DEV__ ? console.log : console.error;

function Screen() {
  const insets = useSafeAreaInsets();
  const { fontScale } = useWindowDimensions();
  const generation = useGeneration(fontScale);
  const [results, setResults] = useState<Results>({});

  const checks = Object.values(results).flatMap((r) => Object.values(r));
  const done = checks.filter(Boolean).length === TOTAL_CHECKS;
  const passed = checks.filter((r) => r?.pass).length;
  const scale = fontScale.toFixed(2);

  // Logs once the results have settled, at launch and after each text size change: a size change
  // updates the Dynamic Type samples over several layouts.
  const signature = JSON.stringify(results);
  useEffect(() => {
    if (!done) return;
    const timer = setTimeout(() => {
      report(`[test screen] ${Platform.OS} @ text ×${scale}: ${passed}/${TOTAL_CHECKS} passed`);
      for (const s of SAMPLES) {
        const r = results[s.id];
        report(
          `[test screen] ${s.id}: unchanged ${mark(r.unchanged)} · ${s.expect} ${mark(r.expected)} (${r.expected?.detail})`
        );
      }
      for (const s of DYNAMIC_TYPE_SAMPLES) {
        const r = results[s.id];
        report(
          `[test screen] ${s.id}: rebalanced ${mark(r.rebalanced)} · no worse ${mark(r.valid)} (${r.valid?.detail})`
        );
      }
    }, 1500);
    return () => clearTimeout(timer);
  }, [done, scale, signature]);

  const onResult = (id: string) => (key: string, result: Result) =>
    setResults((prev) => ({ ...prev, [id]: { ...prev[id], [key]: result } }));

  return (
    <View style={styles.container}>
      <View style={[styles.bar, { paddingTop: 12 + insets.top }]}>
        <Text style={styles.barText}>
          textBreakStrategy="balanced" · {Platform.OS} · text ×{scale}
        </Text>
        <Text style={styles.barText}>{done ? `${passed}/${TOTAL_CHECKS} ✅` : '…'}</Text>
      </View>
      <ScrollView contentContainerStyle={[styles.scroll, { paddingBottom: 16 + insets.bottom }]}>
        <Text style={styles.section}>Samples · fixed text size</Text>
        {SAMPLES.map((s) => (
          <SampleCard key={s.id} sample={s} onResult={onResult(s.id)} />
        ))}
        <Text style={styles.section}>Dynamic Type · scales with text size</Text>
        {DYNAMIC_TYPE_SAMPLES.map((s) => (
          <DynamicTypeCard
            key={s.id}
            sample={s}
            generation={generation}
            onResult={onResult(s.id)}
          />
        ))}
      </ScrollView>
    </View>
  );
}

const mark = (r?: Result) => (r ? (r.pass ? '✅' : '❌') : '…');

// Counts changes of `value`: 0 at mount, then one more each time it changes.
function useGeneration(value: number) {
  const ref = useRef({ value, generation: 0 });
  if (ref.current.value !== value) {
    ref.current = { value, generation: ref.current.generation + 1 };
  }
  return ref.current.generation;
}

type Rendering = 'default' | 'twin' | 'test';

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

  const { default: defaultLines, twin, test } = lines;
  const unchanged = defaultLines && twin ? check('unchanged', defaultLines, twin) : undefined;
  const expected =
    defaultLines && test
      ? withKinsoku(sample, check(sample.expect, defaultLines, test), test)
      : undefined;

  useEffect(() => {
    if (unchanged) onResult('unchanged', unchanged);
  }, [unchanged?.pass, unchanged?.detail]);
  useEffect(() => {
    if (expected) onResult('expected', expected);
  }, [expected?.pass, expected?.detail]);

  // A `noFixedWidth` sample sets no width, only a maximum: its box comes from RN's measure.
  const textStyle = [
    styles.text,
    sample.style,
    sample.noFixedWidth ? { maxWidth: sample.width } : { width: sample.width },
  ];
  const content = (variant: number) =>
    withInlineView(
      withLinks(distinct(sample.text, variant), sample.links, (link) => setPressed(link)),
      sample.inlineView
    );

  return (
    <View style={styles.card}>
      <Text style={styles.label}>
        {sample.label} · {sample.noFixedWidth ? '≤' : ''}
        {sample.width}pt
      </Text>
      <Badge name="unchanged" result={unchanged} />
      <Badge name={sample.expect} result={expected} />

      <Text style={styles.caption}>default</Text>
      <View style={styles.row}>
        <View style={styles.box}>
          <Text
            style={textStyle}
            allowFontScaling={false}
            {...sample.props}
            onTextLayout={onLayout('default')}>
            {content(0)}
          </Text>
        </View>
        {sample.noFixedWidth && <Neighbour />}
      </View>

      <Text style={styles.caption}>textBreakStrategy="balanced"</Text>
      <View style={styles.row}>
        <View style={styles.box}>
          <Text
            style={textStyle}
            allowFontScaling={false}
            {...sample.props}
            textBreakStrategy="balanced"
            onTextLayout={onLayout('test')}>
            {content(1)}
          </Text>
        </View>
        {sample.noFixedWidth && <Neighbour />}
      </View>
      {sample.links && <Text style={styles.caption}>last press: {pressed ?? 'none'}</Text>}

      {/* The unchanged twin: hidden from view, but still laid out so onTextLayout fires. */}
      <View style={styles.hidden} pointerEvents="none">
        <Text
          style={textStyle}
          allowFontScaling={false}
          {...sample.props}
          textBreakStrategy="highQuality"
          onTextLayout={onLayout('twin')}>
          {content(2)}
        </Text>
      </View>
    </View>
  );
}

const toLines = (e: TextLayoutEvent): Line[] =>
  e.nativeEvent.lines.map((l) => ({ text: undistinct(l.text), width: l.width }));

// A Dynamic Type sample, rendered three times at its width, scaling with the text size:
// - default: no textBreakStrategy;
// - live: textBreakStrategy="balanced", mounted since launch, so it has to rebalance on each text
//   size change;
// - fresh: the same, remounted at each text size change with a string no other Text has had
//   (`distinct`), so no measure, lines or break cache entry can serve it: laid out from scratch.
// Checks: the live copy matches the fresh one (rebalanced), and is no worse than default (valid).
function DynamicTypeCard({
  sample,
  generation,
  onResult,
}: {
  sample: DynamicTypeSample;
  generation: number;
  onResult: (key: 'rebalanced' | 'valid', result: Result) => void;
}) {
  const [defaultLines, setDefaultLines] = useState<Line[]>();
  const [live, setLive] = useState<Line[]>();
  // Tagged with the generation it was mounted at, so a fresh copy from before the latest text
  // size change isn't compared.
  const [fresh, setFresh] = useState<{ generation: number; lines: Line[] }>();

  const current = fresh?.generation === generation ? fresh.lines : undefined;
  const isRebalanced = current && live ? rebalanced(current, live) : undefined;
  const valid = defaultLines && live ? noWorse(defaultLines, live) : undefined;

  useEffect(() => {
    if (isRebalanced) onResult('rebalanced', isRebalanced);
  }, [isRebalanced?.pass, isRebalanced?.detail]);
  useEffect(() => {
    if (valid) onResult('valid', valid);
  }, [valid?.pass, valid?.detail]);

  const textStyle = [styles.text, sample.style, { width: sample.width }];

  return (
    <View style={styles.card}>
      <Text style={styles.label}>
        {sample.label} · {sample.width}pt
      </Text>
      <Badge name="rebalanced" result={isRebalanced} />
      <Badge name="no worse" result={valid} />

      <Text style={styles.caption}>default</Text>
      <View style={styles.box}>
        <Text style={textStyle} onTextLayout={(e) => setDefaultLines(toLines(e))}>
          {distinct(sample.text, 0)}
        </Text>
      </View>

      <Text style={styles.caption}>textBreakStrategy="balanced"</Text>
      <View style={styles.box}>
        <Text
          style={textStyle}
          textBreakStrategy="balanced"
          onTextLayout={(e) => setLive(toLines(e))}>
          {distinct(sample.text, 1)}
        </Text>
      </View>

      {/* The fresh copy: hidden from view, but still laid out so onTextLayout fires. */}
      <View style={styles.hidden} pointerEvents="none">
        <Text
          key={generation}
          style={textStyle}
          textBreakStrategy="balanced"
          onTextLayout={(e) => setFresh({ generation, lines: toLines(e) })}>
          {distinct(sample.text, 2 + generation)}
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

// Adds the kinsoku check to a balanced result, for samples that ask for it.
function withKinsoku(sample: Sample, result: Result, lines: Line[]): Result {
  if (!sample.kinsoku) return result;
  const k = kinsoku(lines);
  return { pass: result.pass && k.pass, detail: `${result.detail} · ${k.detail}` };
}

// Puts a `View` inside the text, straight after `inlineView.after`.
function withInlineView(content: ReactNode, inlineView: Sample['inlineView']) {
  if (!inlineView || typeof content !== 'string') return content;
  const at = content.indexOf(inlineView.after);
  if (at < 0) return content;
  const end = at + inlineView.after.length;
  return [
    content.slice(0, end),
    <View
      key="inline-view"
      style={[styles.inlineView, { width: inlineView.width, height: inlineView.height }]}
    />,
    content.slice(end),
  ];
}

// A view beside a `noFixedWidth` sample's text, to show where neighbouring layout lands.
function Neighbour() {
  return <View style={styles.neighbour} />;
}

function Badge({ name, result }: { name: string; result?: Result }) {
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
  section: { fontSize: 13, fontWeight: '700', color: '#777', textTransform: 'uppercase' },
  badge: { fontSize: 12, color: '#262' },
  fail: { color: '#b00' },
  caption: { fontSize: 10, color: '#999', marginTop: 4 },
  row: { flexDirection: 'row', alignItems: 'stretch', gap: 4 },
  neighbour: { width: 12, borderRadius: 3, backgroundColor: '#e8a33d' },
  box: {
    alignSelf: 'flex-start',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#bbb',
  },
  text: { color: '#111' },
  inlineView: { borderRadius: 3, backgroundColor: '#c33' },
  link: { color: '#06c', textDecorationLine: 'underline' },
  hidden: { position: 'absolute', opacity: 0, left: 12, top: 12 },
});
