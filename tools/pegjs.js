// Loads the reference PEG.js implementation from .repos/pegjs.
"use strict";
const path = require("path");
module.exports = require(path.join(__dirname, "..", ".repos", "pegjs", "packages", "pegjs", "lib", "peg"));
