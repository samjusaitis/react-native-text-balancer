import type { TextStyle } from 'react-native';

import type { Expectation } from './checks';

// One test-screen sample: a string at a fixed width, and what `textBreakStrategy="balanced"`
// should do to it compared with stock wrapping. Later build tickets append their samples here.
// A 'balanced' sample must wrap raggedly under stock wrapping on both platforms: if stock is
// already as even as it can be, balancing rightly changes nothing and the check reads ❌.
export type Sample = {
  id: string;
  label: string;
  text: string;
  width: number;
  expect: Exclude<Expectation, 'unchanged'>;
  style?: TextStyle;
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
];
