// Runs the reference PEG.js compiler on a grammar and prints its internals
// (AST after all passes, bytecode, constant tables) as JSON.
//
//   node tools/dump.js <grammar.pegjs> [options-json]
"use strict";
const fs = require("fs");
const peg = require("./pegjs");

function compileInternals(source, options = {}) {
  const session = new peg.compiler.Session({ passes: peg.util.convertPasses(peg.compiler.passes) });
  const warnings = [];
  session.warn = (message, location) => warnings.push({ message, location });
  const ast = session.parse(source, options.parser || {});
  options = peg.util.processOptions(options, {
    allowedStartRules: [ast.rules[0].name], cache: false, context: {}, dependencies: {},
    exportVar: null, features: null, format: "bare", header: null, optimize: "speed",
    output: "source", trace: false,
  });
  for (const stage of Object.keys(session.passes)) {
    for (const pass of session.passes[stage]) {
      if (pass.name === "generateJS") continue;
      pass(ast, session, options);
    }
  }
  delete ast._alwaysConsumesOnSuccess;
  return { ast, warnings };
}

module.exports = { compileInternals };

if (require.main === module) {
  const source = fs.readFileSync(process.argv[2], "utf8");
  const options = process.argv[3] ? JSON.parse(process.argv[3]) : {};
  process.stdout.write(JSON.stringify(compileInternals(source, options), null, 1) + "\n");
}
