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

let nextId = 0;
const origGenerate = peg.generate;
peg.generate = function (grammar, options) {
  const id = nextId++;
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
};
