// Writes internal/self_host/parser.pegjs: PEG.js' own grammar
// (src/parser.pegjs) with its JavaScript code blocks rewritten in MoonBit.
// `pegmbt --value-type Meta` then turns it into internal/self_host/parser.mbt,
// which must behave exactly like the bootstrap grammar parser.
//
//   node tools/gen-self-host.js
"use strict";
const fs = require("fs");
const path = require("path");
const peg = require("./pegjs");

const root = path.join(__dirname, "..");
const source = fs.readFileSync(path.join(root, ".repos", "pegjs", "src", "parser.pegjs"), "utf8");

const initializer = `
  // Words that cannot be used as labels.
  let reserved : Map[String, Bool] = Map([])
  let words : Array[String] = match ctx.options().get("reservedWords") {
    Some(Arr(xs)) => xs.filter_map(x => x.as_str())
    Some(v) if v.truthy() => []
    _ => js_reserved_words()
  }
  for w in words {
    if w != "__proto__" {
      reserved[w] = true
    }
  }

  // Comments collected for the Grammar AST (the \`extractComments\` option).
  let extract_comments = match ctx.options().get("extractComments") {
    Some(v) => v.truthy()
    None => false
  }
  let comments : Map[Int, @ast.Comment] = Map([])
  fn add_comment(text : PegValue, multiline : Bool) -> PegValue raise {
    if extract_comments {
      let location = ctx.location()
      comments[location.start.offset] = { text: str(text), multiline, location }
    }
    text
  }

  // Creates an AST node at the current location.
  fn create_node(kind : @ast.Kind) -> PegValue raise {
    Custom(N(@ast.Node::new(kind, ctx.location())))
  }
`;

const blocks = {
  "return new ast.Grammar( initializer, rules, comments, location() );": `
    let init = match initializer {
      Custom(I(i)) => Some(i)
      _ => None
    }
    let rule_list = arr(rules).map(r => match r {
      Custom(R(rule)) => rule
      _ => abort("expected a rule")
    })
    let comment_list = if extract_comments {
      let sorted = comments.to_array()
      sorted.sort_by_key(c => c.0)
      Some(sorted)
    } else {
      None
    }
    Custom(G(@ast.Grammar::new(init, rule_list, comment_list, ctx.location())))`,
  'return createNode( "initializer", { code } );': `
    Custom(I({ code: str(code), location: ctx.location() }))`,
  'if ( displayName )\n\n            expression = createNode( "named", {\n                name: displayName,\n                expression: expression,\n            } );\n\n        return createNode( "rule", { name, expression } );': `
    let expression = if displayName.truthy() {
      @ast.Node::new(Named(name=str(displayName), node(expression)), ctx.location())
    } else {
      node(expression)
    }
    Custom(R(@ast.Rule::new(str(name), expression, ctx.location())))`,
  'if ( tail.length === 0 ) return head;\n\n        return createNode( "choice", {\n            alternatives: [ head ].concat( tail ),\n        } );': `
    if arr(tail).is_empty() {
      return head
    }
    create_node(Choice([node(head), ..arr(tail).map(node)]))`,
  'if ( code === null ) return expression;\n\n        return createNode( "action", { expression, code } );': `
    if code is Null {
      return expression
    }
    create_node(Action(node(expression), code=str(code)))`,
  'let elements = [ head ];\n\n        if ( tail.length === 0 ) {\n\n            if ( head.type !== "labeled" || ! head.pick ) return head;\n\n        } else {\n\n            elements = elements.concat( tail );\n\n        }\n\n        return createNode( "sequence", { elements } );': `
    if arr(tail).is_empty() && !(node(head).kind is Labeled(_, pick=true, ..)) {
      return head
    }
    create_node(Sequence([node(head), ..arr(tail).map(node)]))`,
  'return createNode( "labeled", { pick, label, expression } );': `
    let label = match label {
      Null => None
      l => Some(str(l))
    }
    create_node(Labeled(label~, pick=true, node(expression)))`,
  'return createNode( "labeled", { label, expression } );': `
    create_node(Labeled(label=Some(str(label)), pick=false, node(expression)))`,
  'if ( RESERVED_WORDS[ name ] !== true ) return name;\n\n        error( `Label can\'t be a reserved word "${ name }".`, location() );': `
    if reserved.contains(str(name)) {
      ctx.error("Label can't be a reserved word \\"" + str(name) + "\\".", location=ctx.location())
    }
    name`,
  "return createNode( operator, { expression } );": `
    create_node(match str(operator) {
      "text" => Text(node(expression))
      "simple_and" => SimpleAnd(node(expression))
      "simple_not" => SimpleNot(node(expression))
      "optional" => Optional(node(expression))
      "zero_or_more" => ZeroOrMore(node(expression))
      _ => OneOrMore(node(expression))
    })`,
  'return "text";': ' Str("text") ',
  'return "simple_and";': ' Str("simple_and") ',
  'return "simple_not";': ' Str("simple_not") ',
  'return "optional";': ' Str("optional") ',
  'return "zero_or_more";': ' Str("zero_or_more") ',
  'return "one_or_more";': ' Str("one_or_more") ',
  '// The purpose of the "group" AST node is just to isolate label scope. We\n        // don\'t need to put it around nodes that can\'t contain any labels or\n        // nodes that already isolate label scope themselves.\n        if ( e.type !== "labeled" && e.type !== "sequence" ) return e;\n\n        // This leaves us with "labeled" and "sequence".\n        return createNode( "group", { expression: e } );': `
    // The purpose of the "group" AST node is just to isolate label scope.
    match node(e).kind {
      Labeled(_, ..) | Sequence(_) => create_node(Group(node(e)))
      _ => e
    }`,
  'return createNode( "rule_ref", { name } );': " create_node(RuleRef(name=str(name))) ",
  "return createNode( operator, { code } );": `
    create_node(match str(operator) {
      "semantic_and" => SemanticAnd(code=str(code))
      _ => SemanticNot(code=str(code))
    })`,
  'return "semantic_and";': ' Str("semantic_and") ',
  'return "semantic_not";': ' Str("semantic_not") ',
  "return addComment( comment, true );": " add_comment(comment, true) ",
  "return addComment( comment, false );": " add_comment(comment, false) ",
  'return head + tail.join("");': " Str(str(head) + joined(tail)) ",
  'return createNode( "literal", {\n            value: value,\n            ignoreCase: ignoreCase !== null,\n        } );': `
    create_node(Literal(value=str(value), ignore_case=!(ignoreCase is Null)))`,
  'return chars.join("");': " Str(joined(chars)) ",
  'return createNode( "class", {\n            parts: parts.filter( part => part !== "" ),\n            inverted: inverted !== null,\n            ignoreCase: ignoreCase !== null,\n        } );': `
    let parts = arr(parts).filter_map(part => match part {
      Str("") => None
      Str(c) => Some(@runtime.ClassPart::Char(c))
      Arr([Str(a), Str(b)]) => Some(Range(a, b))
      _ => abort("bad class part")
    })
    create_node(Class(parts~, inverted=!(inverted is Null), ignore_case=!(ignoreCase is Null)))`,
  'if ( begin.charCodeAt( 0 ) > end.charCodeAt( 0 ) )\n\n            error( "Invalid character range: " + text() + "." );\n\n        return [ begin, end ];': `
    let (b, e) = (str(begin), str(end))
    if b != "" && e != "" && b.code_unit_at(0) > e.code_unit_at(0) {
      ctx.error("Invalid character range: " + ctx.text() + ".")
    }
    Arr([begin, end])`,
  'return "";': ' Str("") ',
  'return "\\0";': ' Str("\\u{0}") ',
  'return "\\b";': ' Str("\\u{8}") ',
  'return "\\f";': ' Str("\\u{c}") ',
  'return "\\n";': ' Str("\\n") ',
  'return "\\r";': ' Str("\\r") ',
  'return "\\t";': ' Str("\\t") ',
  'return "\\v";': ' Str("\\u{b}") ',
  "return String.fromCharCode( parseInt( digits, 16 ) );": " Str(@runtime.string_of_code_units([hex(str(digits))])) ",
  'return createNode( "any" );': " create_node(Any) ",
  'error("Unbalanced brace.");': ' ctx.error("Unbalanced brace.") ',
};

// Labels must be MoonBit identifiers: rename the camelCase ones.
const ast = peg.parser.parse(source);
let out = source;
const codes = [];
(function walk(n) {
  if (!n || typeof n !== "object") return;
  if (typeof n.code === "string" && n.type) codes.push(n);
  for (const k in n) if (k !== "location" && k !== "_alwaysConsumesOnSuccess") walk(n[k]);
})(ast);
for (const node of codes) {
  const key = node.code.trim();
  const mbt = node.type === "initializer" ? initializer : blocks[key];
  if (mbt === undefined) throw new Error("no translation for code block: " + JSON.stringify(key));
  out = out.split("{" + node.code + "}").join("{" + mbt + "\n}");
}
out = out
  .replace(/\bdisplayName\b/g, "display_name")
  .replace(/\bignoreCase\b/g, "ignore_case_flag");
out = "// PEG.js' grammar (src/parser.pegjs) with MoonBit code blocks.\n" +
  "// Generated by tools/gen-self-host.js. DO NOT EDIT.\n\n" + out;
fs.mkdirSync(path.join(root, "internal", "self_host"), { recursive: true });
fs.writeFileSync(path.join(root, "internal", "self_host", "parser.pegjs"), out);
console.log("translated", codes.length, "code blocks");
