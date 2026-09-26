// MoonBit translations of the JavaScript code blocks used by the grammars of
// the upstream test suite, for differential testing of generated parsers.
//
// Keys are trimmed JavaScript code; `uses` lists the labels a translation
// refers to (a grammar is only usable if they are all in scope — out-of-scope
// references are ReferenceErrors in JavaScript but compile errors in
// MoonBit). Initializer translations are keyed the same way. Helpers
// (js_add, js_join, js_number) live in the harness package.
"use strict";

const loc = "{ filename: None, start: { offset: 1, line: 1, column: 2 }, end: { offset: 2, line: 1, column: 3 } }";

const blocks = {
  "return 'a';": { code: 'Str("a")' },
  "return 'b';": { code: 'Str("b")' },
  "return 'c';": { code: 'Str("c")' },
  "return n;": { code: "Num(n.val)", init: "var n = 0;" },
  "n++;": { code: "n.val += 1.0\nUndefined", init: "var n = 0;" },
  "return result;": { code: "result.val" },
  "return true;": { code: "true" },
  "return false;": { code: "false" },
  "return a === 'a';": { code: 'a is Str("a")', uses: ["a"] },
  "return b === undefined;": { code: "b is Undefined", uses: ["b"] },
  "return b === 'b';": { code: 'b is Str("b")', uses: ["b"] },
  "return a;": { code: "a", uses: ["a"] },
  "return v === 42;": { code: "v == 42" },
  "return f() === 42;": { code: "f() == 42" },
  "result = options; return true;": { code: "result.val = Obj(ctx.options())\ntrue" },
  "result = location(); return true;": { code: "result.val = ctx.location().to_value()\ntrue" },
  "return val;": { code: "val", uses: ["val"] },
  "return offset();": { code: "Num(ctx.offset().to_double())" },
  "return range();": { code: "let (s, e) = ctx.range()\nArr([Num(s.to_double()), Num(e.to_double())])" },
  "return a !== 'a';": { code: '!(a is Str("a"))', uses: ["a"] },
  "return b !== undefined;": { code: "!(b is Undefined)", uses: ["b"] },
  "return b !== 'b';": { code: '!(b is Str("b"))', uses: ["b"] },
  "return v !== 42;": { code: "v != 42" },
  "return f() !== 42;": { code: "f() != 42" },
  "result = options; return false;": { code: "result.val = Obj(ctx.options())\nfalse" },
  "result = location(); return false;": { code: "result.val = ctx.location().to_value()\nfalse" },
  "return n > 0;": { code: "js_number(n) > 0.0", uses: ["n"] },
  "return 42;": { code: "Num(42.0)" },
  "return [a, b, c];": { code: "Arr([a, b, c])", uses: ["a", "b", "c"] },
  "return b;": { code: "b", uses: ["b"] },
  "return v;": { code: "Num(v.to_double())" },
  "return f();": { code: "Num(f().to_double())" },
  "return options;": { code: "Obj(ctx.options())" },
  "return text();": { code: "Str(ctx.text())" },
  "result = location();": { code: "result.val = ctx.location().to_value()\nUndefined" },
  "expected('a');": { code: 'ctx.expected("a")' },
  "expected('a', {\n    start: { offset: 1, line: 1, column: 2 },\n    end: { offset: 2, line: 1, column: 3 }\n  });":
    { code: 'ctx.expected("a", location=' + loc + ")" },
  "error('a');": { code: 'ctx.error("a")' },
  "error('a', {\n    start: { offset: 1, line: 1, column: 2 },\n    end: { offset: 2, line: 1, column: 3 }\n  });":
    { code: 'ctx.error("a", location=' + loc + ")" },
  "throw 'Boom!';": { code: 'fail("Boom!")' },
  "return tail.reduce(function(result, element) {\n          if (element[0] === '+') { return result + element[1]; }\n          if (element[0] === '-') { return result - element[1]; }\n        }, head);":
    { code: 'js_reduce(head, tail, "+", "-")', uses: ["head", "tail"] },
  "return tail.reduce(function(result, element) {\n              if (element[0] === '*') { return result * element[1]; }\n              if (element[0] === '/') { return result / element[1]; }\n            }, head);":
    { code: 'js_reduce(head, tail, "*", "/")', uses: ["head", "tail"] },
  "return parseInt(digits.join(''), 10);": { code: 'Num(js_number(js_join(digits, "")))', uses: ["digits"] },
  "return expr;": { code: "expr", uses: ["expr"] },
  "return begin + ns.join('') + end;": { code: 'js_add(js_add(begin, js_join(ns, "")), end)', uses: ["begin", "ns", "end"] },
  "return z;": { code: "z", uses: ["z"] },
};

const initializers = {
  "var n = 0;": "let n = Ref(0.0)",
  "var result = 42;": "let result : Ref[@runtime.Value[Unit]] = Ref(Num(42.0))",
  "var result = options;": "let result : Ref[@runtime.Value[Unit]] = Ref(Obj(ctx.options()))",
  "var v = 42": "let v = 42",
  "function f() { return 42; }": "fn f() { 42 }",
  "var result;": "let result : Ref[@runtime.Value[Unit]] = Ref(Undefined)",
};

module.exports = { blocks, initializers };
