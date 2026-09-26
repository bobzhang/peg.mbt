// The "check" passes: semantic validation of the grammar AST.

///|
/// Visits `node` and all its descendants in pre-order.
fn walk(node : @ast.Node, f : (@ast.Node) -> Unit raise) -> Unit raise {
  f(node)
  for child in node.children() {
    walk(child, f)
  }
}

///|
/// Visits every expression node of every rule in pre-order.
fn walk_grammar(
  grammar : @ast.Grammar,
  f : (@ast.Node) -> Unit raise,
) -> Unit raise {
  for rule in grammar.rules {
    walk(rule.expression, f)
  }
}

///|
/// Checks that all referenced rules exist (`report-undefined-rules.js`).
pub fn[T] report_undefined_rules(
  grammar : @ast.Grammar,
  session : Session[T],
  options : Options[T],
) -> Unit raise {
  walk_grammar(grammar, node => {
    if node.kind is RuleRef(name~) && grammar.find_rule(name) is None {
      session.report_error(
        "Rule \"\{name}\" is not defined.",
        location=node.location,
      )
    }
  })
  for rule in options.start_rules(grammar) {
    if grammar.find_rule(rule) is None {
      session.report_error("Start rule \"\{rule}\" is not defined.")
    }
  }
}

///|
/// Checks that each rule is defined only once (`report-duplicate-rules.js`).
pub fn[T] report_duplicate_rules(
  grammar : @ast.Grammar,
  session : Session[T],
  _options : Options[T],
) -> Unit raise {
  let rules : JsDict[@runtime.Location] = JsDict::new()
  for rule in grammar.rules {
    if rules.get(rule.name) is Some(previous) {
      let start = previous.start
      session.report_error(
        "Rule \"\{rule.name}\" is already defined at line \{start.line}, column \{start.column}.",
        location=rule.location,
      )
    }
    rules.set(rule.name, rule.location)
  }
}

///|
/// Warns about rules that are never referenced (`report-unused-rules.js`).
pub fn[T] report_unused_rules(
  grammar : @ast.Grammar,
  session : Session[T],
  options : Options[T],
) -> Unit raise {
  let used : JsDict[Bool] = JsDict::new()
  for rule in options.start_rules(grammar) {
    used.set(rule, true)
  }
  walk_grammar(grammar, node => {
    if node.kind is RuleRef(name~) {
      used.set(name, true)
    }
  })
  for rule in grammar.rules {
    if used.get(rule.name) is None {
      session.report_warning(
        "Rule \"\{rule.name}\" is not referenced.",
        location=rule.location,
      )
    }
  }
}

///|
/// Checks that each label is defined only once within each scope
/// (`report-duplicate-labels.js`).
pub fn[T] report_duplicate_labels(
  grammar : @ast.Grammar,
  session : Session[T],
  _options : Options[T],
) -> Unit raise {
  fn check(node : @ast.Node, env : JsDict[@runtime.Location]) -> Unit raise {
    match node.kind {
      Choice(alternatives) =>
        for alternative in alternatives {
          check(alternative, env.clone())
        }
      Labeled(expression, label~, ..) => {
        if label is Some(label) && env.get(label) is Some(previous) {
          let start = previous.start
          session.report_error(
            "Label \"\{label}\" is already defined at line \{start.line}, column \{start.column}.",
            location=node.location,
          )
        }
        check(expression, env)
        if label is Some(label) {
          env.set(label, node.location)
        }
      }
      Action(expression, ..)
      | Text(expression)
      | SimpleAnd(expression)
      | SimpleNot(expression)
      | Optional(expression)
      | ZeroOrMore(expression)
      | OneOrMore(expression)
      | Group(expression) => check(expression, env.clone())
      Named(expression, ..) => check(expression, env)
      Sequence(elements) =>
        for element in elements {
          check(element, env)
        }
      SemanticAnd(..)
      | SemanticNot(..)
      | RuleRef(..)
      | Literal(..)
      | Class(..)
      | Any => ()
    }
  }

  for rule in grammar.rules {
    check(rule.expression, JsDict::new())
  }
}

///|
/// Reports left recursion (`report-infinite-recursion.js`).
///
/// If a rule reference can be reached without consuming any input, it can
/// lead to infinite recursion.
pub fn[T] report_infinite_recursion(
  grammar : @ast.Grammar,
  session : Session[T],
  _options : Options[T],
) -> Unit raise {
  let visited_rules : Array[String] = []
  fn check(node : @ast.Node) -> Unit raise {
    match node.kind {
      Sequence(elements) =>
        for element in elements {
          check(element)
          if grammar.always_consumes_on_success(element) {
            break
          }
        }
      RuleRef(name~) => {
        if visited_rules.contains(name) {
          visited_rules.push(name)
          let rule_path = visited_rules.join(" -> ")
          session.report_error(
            "Possible infinite loop when parsing (left recursion: \{rule_path}).",
            location=node.location,
          )
        }
        match grammar.find_rule(name) {
          Some(rule) => {
            visited_rules.push(rule.name)
            check(rule.expression)
            visited_rules.pop() |> ignore
          }
          None =>
            raise CompilerError(
              "Visitor function called with no arguments or a `falsy` node",
            )
        }
      }
      _ =>
        for child in node.children() {
          check(child)
        }
    }
  }

  for rule in grammar.rules {
    visited_rules.push(rule.name)
    check(rule.expression)
    visited_rules.pop() |> ignore
  }
}

///|
/// Reports repetitions of expressions that may not consume input
/// (`report-infinite-repetition.js`). Like PEG.js, a checked repetition's
/// operand is not searched further.
pub fn[T] report_infinite_repetition(
  grammar : @ast.Grammar,
  session : Session[T],
  _options : Options[T],
) -> Unit raise {
  fn check(node : @ast.Node) -> Unit raise {
    match node.kind {
      ZeroOrMore(expression) | OneOrMore(expression) =>
        if !grammar.always_consumes_on_success(expression) {
          session.report_error(
            "Possible infinite loop when parsing (repetition used with an expression that may not consume any input).",
            location=node.location,
          )
        }
      _ =>
        for child in node.children() {
          check(child)
        }
    }
  }

  for rule in grammar.rules {
    check(rule.expression)
  }
}

///|
/// Ensures `@` is not combined with an action block or used on a semantic
/// predicate (`report-incorrect-plucking.js`).
pub fn[T] report_incorrect_plucking(
  grammar : @ast.Grammar,
  session : Session[T],
  _options : Options[T],
) -> Unit raise {
  fn visit(node : @ast.Node, in_action : Bool) -> Unit raise {
    match node.kind {
      Action(expression, ..) => visit(expression, true)
      Labeled(expression, pick~, ..) => {
        if !pick {
          return
        }
        if in_action {
          session.report_error(
            "\"@\" cannot be used with an action block.",
            location=node.location,
          )
        }
        if expression.kind is (SemanticAnd(..) | SemanticNot(..)) {
          session.report_error(
            "\"@\" cannot be used on a semantic predicate.",
            location=node.location,
          )
        }
        visit(expression, false)
      }
      _ =>
        for child in node.children() {
          visit(child, in_action)
        }
    }
  }

  for rule in grammar.rules {
    visit(rule.expression, false)
  }
}

///|
/// Removes rules that only delegate to another rule, redirecting references
/// (`remove-proxy-rules.js`). Proxies listed as start rules are kept.
pub fn[T] remove_proxy_rules(
  grammar : @ast.Grammar,
  _session : Session[T],
  options : Options[T],
) -> Unit raise {
  let allowed_start_rules = options.start_rules(grammar)
  let rules = []
  for rule in grammar.rules {
    if rule.expression.kind is RuleRef(name=real) {
      let proxy = rule.name
      walk_grammar(grammar, node => {
        if node.kind is RuleRef(name~) && name == proxy {
          node.kind = RuleRef(name=real)
        }
      })
      if !allowed_start_rules.contains(rule.name) {
        continue
      }
    }
    rules.push(rule)
  }
  grammar.rules = rules
}
