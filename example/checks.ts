// What a sample expects of a `Text`, compared with the same string under stock wrapping:
// - balanced: the same line count, with line widths that vary less than stock's;
// - stock: identical lines (the fallback cases);
// - unchanged: identical lines, for a `Text` that doesn't ask for balancing.
export type Expectation = 'balanced' | 'stock' | 'unchanged';

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

export function check(expect: Expectation, stock: Line[], actual: Line[]): Result {
  if (expect === 'balanced') {
    if (actual.length !== stock.length) {
      return { pass: false, detail: `${actual.length} lines, stock has ${stock.length}` };
    }
    const before = variance(stock);
    const after = variance(actual);
    return {
      pass: after < before,
      detail: `width variance ${before.toFixed(0)} → ${after.toFixed(0)}`,
    };
  }
  return sameLines(stock, actual)
    ? { pass: true, detail: 'identical to stock' }
    : { pass: false, detail: 'differs from stock' };
}

// RN's text measure cache ignores some paragraph attributes (`lineBreakStrategy`), so two `Text`s
// with the same string can share one `onTextLayout` result. A different number of trailing word
// joiners (U+2060, zero width, no break opportunity) keeps each rendering's string distinct.
export const distinct = (text: string, variant: number) => text + '\u2060'.repeat(variant);

// Undoes `distinct` on a reported line, so line texts compare across renderings.
export const undistinct = (text: string) => text.replace(/\u2060/g, '');
