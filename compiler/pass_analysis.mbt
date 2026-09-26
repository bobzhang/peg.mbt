///|
/// Marks the rules whose failures can be visible (`calc-report-failures.js`):
/// start rules, and rules reachable from them outside named rules.
#warnings("-unused_error_type")
pub fn[T] calc_report_failures(
  grammar : @ast.Grammar,
  _session : Session[T],
  options : Options[T],
) -> Unit raise {
  for rule in grammar.rules {
    rule.report_failures = Some(false)
  }
  let changed_rules : Array[@ast.Rule] = []
  for name in options.start_rules(grammar) {
    let rule = grammar.find_rule(name).unwrap()
    rule.report_failures = Some(true)
    changed_rules.push(rule)
  }
  fn calc(node : @ast.Node) -> Unit {
    match node.kind {
      // Failures inside a named rule are never reported.
      Named(_, ..) => ()
      RuleRef(name~) => {
        let rule = grammar.find_rule(name).unwrap()
        if rule.report_failures is Some(false) {
          rule.report_failures = Some(true)
          changed_rules.push(rule)
        }
      }
      _ =>
        for child in node.children() {
          calc(child)
        }
    }
  }

  while changed_rules.pop() is Some(rule) {
    calc(rule.expression)
  }
}

///|
priv struct Inference[T] {
  grammar : @ast.Grammar
  session : Session[T]
}

///|
fn[T] Inference::rule(self : Inference[T], rule : @ast.Rule) -> Int raise {
  match rule.match_result {
    Some(m) => m
    None => {
      rule.match_result = Some(0)
      let mut count = 0
      for ;; {
        let old = rule.match_result.unwrap()
        rule.match_result = Some(self.node(rule.expression))
        count += 1
        if count > 6 {
          self.session.report_error(
            "Infinity cycle detected when trying to evaluate node match result",
            location=rule.location,
          )
        }
        if old == rule.match_result.unwrap() {
          break
        }
      }
      rule.match_result.unwrap()
    }
  }
}

///|
fn[T] Inference::elements(
  self : Inference[T],
  elements : Array[@ast.Node],
  for_choice : Bool,
) -> Int raise {
  let length = elements.length()
  let mut always = 0
  let mut never = 0
  for element in elements {
    let result = self.node(element)
    if result > 0 {
      always += 1
    }
    if result < 0 {
      never += 1
    }
  }
  if always == length {
    1
  } else if for_choice {
    if never == length {
      -1
    } else {
      0
    }
  } else if never > 0 {
    -1
  } else {
    0
  }
}

///|
fn[T] Inference::node(self : Inference[T], node : @ast.Node) -> Int raise {
  let result = match node.kind {
    Named(e, ..)
    | Action(e, ..)
    | Labeled(e, ..)
    | Text(e)
    | SimpleAnd(e)
    | OneOrMore(e)
    | Group(e) => self.node(e)
    Choice(alternatives) => self.elements(alternatives, true)
    Sequence(elements) => self.elements(elements, false)
    SimpleNot(e) => -self.node(e)
    Optional(e) | ZeroOrMore(e) => {
      self.node(e) |> ignore
      1
    }
    SemanticAnd(..) | SemanticNot(..) | Any => 0
    RuleRef(name~) => self.rule(self.grammar.find_rule(name).unwrap())
    // An empty literal always matches.
    Literal(value~, ..) => if value == "" { 1 } else { 0 }
    // An empty class never matches (even inverted: `[^]` always fails).
    Class(parts~, ..) => if parts.is_empty() { -1 } else { 0 }
  }
  node.match_result = Some(result)
  result
}

///|
/// Infers whether each node always (1), sometimes (0) or never (-1) matches
/// (`inference-match-result.js`).
pub fn[T] inference_match_result(
  grammar : @ast.Grammar,
  session : Session[T],
  _options : Options[T],
) -> Unit raise {
  let inference = { grammar, session, }
  for rule in grammar.rules {
    inference.rule(rule) |> ignore
  }
}
