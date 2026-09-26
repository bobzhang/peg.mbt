// Mocha `--require` hook that records every interaction the reference test
// suite has with PEG.js, producing a JSONL corpus of differential fixtures:
//
//   {"kind":"meta", input, options, ok, result|error}        grammar parser
//   {"kind":"generate", id, grammar, options, ok, error?}    peg.generate
//   {"kind":"parse", gen, input, options, ok, result|error}  generated parser
//
// Usage: HARVEST_OUT=corpus.jsonl mocha --require tools/harvest.js ...
"use strict";

const fs = require("fs");
const path = require("path");
const peg = require("./pegjs");

const out = process.env.HARVEST_OUT || path.join(__dirname, "corpus.jsonl");
fs.writeFileSync(out, "");
function emit(record) {
  fs.appendFileSync(out, JSON.stringify(record) + "\n");
}

// Encodes JS values losslessly enough for MoonBit's `Value`.
function encode(v, seen = new Set()) {
  if (v === undefined) return { $: "undefined" };
  if (v === null || typeof v === "boolean" || typeof v === "string") return v;
  if (typeof v === "number") return Number.isFinite(v) ? v : { $: "number", value: String(v) };
  if (typeof v === "function") return { $: "function" };
  if (seen.has(v)) return { $: "cycle" };
  seen.add(v);
  let r;
  if (Array.isArray(v)) r = v.map(x => encode(x, seen));
  else {
    r = {};
    for (const k of Object.keys(v)) {
      if (k === "_alwaysConsumesOnSuccess") continue;
      r[k] = encode(v[k], seen);
    }
  }
  seen.delete(v);
  return r;
}

function encodeError(e) {
  return {
    name: e && e.name,
    message: e && e.message,
    location: e && e.location !== undefined ? encode(e.location) : undefined,
    expected: e && e.expected !== undefined ? encode(e.expected) : undefined,
    found: e && e.found !== undefined ? encode(e.found) : undefined,
  };
}

function record(base, thunk) {
  try {
    const result = thunk();
    emit(Object.assign(base, { ok: true, result: encode(result) }));
    return result;
  } catch (e) {
    emit(Object.assign(base, { ok: false, error: encodeError(e) }));
    throw e;
  }
}

const origMetaParse = peg.parser.parse;
peg.parser.parse = function (input, options) {
  return record({ kind: "meta", input, options: encode(options) }, () => origMetaParse.call(this, input, options));
};

// Direct compiler-pass invocations (the pass unit specs):
//   {"kind":"pass", name, grammar, options, ruleProps, ok, result|error, warnings}
let inGenerate = 0;
const origSessionParse = peg.compiler.Session.prototype.parse;
peg.compiler.Session.prototype.parse = function (input, options) {
  this.__grammar = input;
  return origSessionParse.call(this, input, options);
};
for (const stage of Object.keys(peg.compiler.passes)) {
  const passes = peg.compiler.passes[stage];
  for (const name of Object.keys(passes)) {
    const pass = passes[name];
    if (name === "generateJS") continue;
    passes[name] = function (ast, session, options) {
      if (inGenerate > 0 || typeof session.__grammar !== "string") return pass.call(this, ast, session, options);
      const warnings = [];
      const origWarn = session.warn;
      session.warn = function (message, location) {
        warnings.push({ message, location: encode(location) });
        return origWarn.call(this, message, location);
      };
      const base = {
        kind: "pass", name, grammar: session.__grammar, options: encode(options),
        ruleProps: ast.rules.map(r => ({ reportFailures: r.reportFailures })),
      };
      try {
        pass.call(this, ast, session, options);
        emit(Object.assign(base, { ok: true, result: encode(ast), warnings }));
      } catch (e) {
        emit(Object.assign(base, { ok: false, error: encodeError(e), warnings }));
        throw e;
      } finally {
        session.warn = origWarn;
      }
    };
  }
}

let nextId = 0;
const origGenerate = peg.generate;
peg.generate = function (grammar, options) {
  const id = nextId++;
  inGenerate++;
  try {
    return generateImpl(id, grammar, options);
  } finally {
    inGenerate--;
  }
};
function generateImpl(id, grammar, options) {
  const base = { kind: "generate", id, grammar, options: encode(options) };
  let parser;
  try {
    parser = origGenerate.call(this, grammar, options);
  } catch (e) {
    emit(Object.assign(base, { ok: false, error: encodeError(e) }));
    throw e;
  }
  emit(Object.assign(base, { ok: true, source: typeof parser === "string" }));
  if (parser && typeof parser.parse === "function") {
    const origParse = parser.parse;
    parser.parse = function (input, options) {
      return record({ kind: "parse", gen: id, input, options: encode(options) }, () => origParse.call(this, input, options));
    };
  }
  return parser;
}
