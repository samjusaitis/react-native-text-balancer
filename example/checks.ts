// What a sample expects of a `Text`, compared with the same string under default wrapping:
// - balanced: the same line count, with line widths that vary less than default wrapping's;
// - default: identical lines (the fallback cases);
// - unchanged: identical lines, for a `Text` that doesn't ask for balancing.
export type Expectation = 'balanced' | 'default' | 'unchanged';

export type Line = { text: string; width: number };

export type Result = { pass: boolean; detail: string };

const round = (n: number) => Math.round(n * 2) / 2;

const variance = (lines: Line[]) => {
  const mean = lines.reduce((sum, l) => sum + l.width, 0) / lines.length;
  return lines.reduce((sum, l) => sum + (l.width - mean) ** 2, 0) / lines.length;
};

const sameLines = (a: Line[], b: Line[]) =>
  a.length === b.length &&
  a.every((line, i) => line.text === b[i].text && round(line.width) === round(b[i].width));

const sameTexts = (a: Line[], b: Line[]) =>
  a.length === b.length && a.every((line, i) => line.text === b[i].text);

export function check(expect: Expectation, defaultLines: Line[], actual: Line[]): Result {
  if (expect === 'balanced') {
    if (actual.length !== defaultLines.length) {
      return { pass: false, detail: `${actual.length} lines, default has ${defaultLines.length}` };
    }
    // Same breaks can still report a lower variance: a balanced line's narrowed fragment clips
    // its trailing space, which default wrapping's reported width includes. So the breaks must move.
    if (sameTexts(defaultLines, actual)) {
      return { pass: false, detail: 'same breaks as default' };
    }
    const before = variance(defaultLines);
    const after = variance(actual);
    return {
      pass: after < before,
      detail: `width variance ${before.toFixed(0)} → ${after.toFixed(0)}`,
    };
  }
  return sameLines(defaultLines, actual)
    ? { pass: true, detail: 'identical to default' }
    : { pass: false, detail: 'differs from default' };
}

// A balanced layout that's no worse than default wrapping: the same breaks (default wrapping is already as even as it
// can be at this size, or the paragraph fell back), or breaks that lower the width variance. For
// the Dynamic Type samples, whose wrapping changes with the text size.
export function noWorse(defaultLines: Line[], actual: Line[]): Result {
  if (actual.length !== defaultLines.length) {
    return { pass: false, detail: `${actual.length} lines, default has ${defaultLines.length}` };
  }
  if (sameTexts(defaultLines, actual)) {
    return { pass: true, detail: 'same breaks as default' };
  }
  const before = variance(defaultLines);
  const after = variance(actual);
  return {
    pass: after < before,
    detail: `width variance ${before.toFixed(0)} → ${after.toFixed(0)}`,
  };
}

// A balanced Text that has lived through text size changes lays out exactly like one mounted fresh
// at the current size.
export function rebalanced(fresh: Line[], live: Line[]): Result {
  return sameLines(fresh, live)
    ? { pass: true, detail: 'matches a fresh layout' }
    : { pass: false, detail: 'differs from a fresh layout' };
}

// Characters a Japanese line must not start with: closing punctuation and small kana.
const KINSOKU_START = /^[、。，．,.)\]｝〕〉》」』】〙〗〟’”｠»）！？!?：；・ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰ-ㇿ]/;

// Lines that break a kinsoku rule, for the Japanese sample.
export function kinsoku(lines: Line[]): Result {
  const bad = lines.slice(1).filter((l) => KINSOKU_START.test(l.text));
  return bad.length
    ? { pass: false, detail: `line starts with ${bad.map((l) => l.text[0]).join(' ')}` }
    : { pass: true, detail: 'kinsoku kept' };
}

// RN's text measure cache ignores some paragraph attributes (`lineBreakStrategy`), so two `Text`s
// with the same string can share one `onTextLayout` result. A different number of trailing word
// joiners (U+2060, zero width, no break opportunity) keeps each rendering's string distinct.
export const distinct = (text: string, variant: number) => text + '\u2060'.repeat(variant);

// Undoes `distinct` on a reported line, so line texts compare across renderings.
export const undistinct = (text: string) => text.replace(/\u2060/g, '');
