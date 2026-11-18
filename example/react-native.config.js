const path = require('path');

const pkg = require('../package.json');

// Link the library straight from the repo root rather than installing a copy, so a native
// rebuild picks up edits to the library with no copy or sync step.
module.exports = {
  dependencies: {
    [pkg.name]: {
      root: path.resolve(__dirname, '..'),
    },
  },
};
