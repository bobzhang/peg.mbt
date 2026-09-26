// Parse-time state shared by the bytecode interpreter and generated parsers.
// This is the MoonBit counterpart of the `peg$*` variables and helper
// functions that PEG.js emits inside every generated `peg$parse`.

///|
/// A slot of the parsing machine's stack: a value, a saved input position or
/// the `peg$FAILED` marker. Actions never observe `Failed` or `Pos`.
pub(all) enum Slot[T] {
  Failed
  Pos(Int)
  Val(Value[T])
} derive(Eq, Debug)

///|
/// Which helpers the generated parser provides (the PEG.js `features`
/// option). Disabled action helpers raise `FeatureDisabled`.
pub(all) struct Features {
  text : Bool
  offset : Bool
  range : Bool
  location : Bool
  expected : Bool
  error : Bool
  filename : Bool
  default_tracer : Bool
} derive(Eq, Debug)

///|
pub fn Features::all() -> Features {
  {
    text: true,
    offset: true,
    range: true,
    location: true,
    expected: true,
    error: true,
    filename: true,
    default_tracer: true,
  }
}

///|
pub(all) enum TraceType {
  RuleEnter
  RuleMatch
  RuleFail
} derive(Eq, Debug)

///|
pub fn TraceType::name(self : TraceType) -> String {
  match self {
    RuleEnter => "rule.enter"
    RuleMatch => "rule.match"
    RuleFail => "rule.fail"
  }
}

///|
pub(all) struct TraceEvent[T] {
  type_ : TraceType
  rule : String
  result : Value[T]?
  location : Location
} derive(Eq, Debug)

///|
/// Receives rule enter/match/fail events when tracing is enabled.
pub(all) struct Tracer[T] {
  trace : (TraceEvent[T]) -> Unit raise
}

///|
/// The PEG.js `DefaultTracer`: logs indented events through `log`
/// (`println` by default).
pub fn[T] Tracer::default(log? : (String) -> Unit = println) -> Tracer[T] {
  let indent = Ref(0)
  fn emit(event : TraceEvent[T]) {
    let loc = event.location
    let sb = StringBuilder()
    sb.write_string(
      "\{loc.start.line}:\{loc.start.column}-\{loc.end.line}:\{loc.end.column} ",
    )
    let name = event.type_.name()
    sb.write_string(name)
    for _ in name.length()..<10 {
      sb.write_char(' ')
    }
    sb.write_char(' ')
    for _ in 0..<indent.val {
      sb.write_string("  ")
    }
    sb.write_string(event.rule)
    log(sb.to_string())
  }

  {
    trace: event => {
      match event.type_ {
        RuleEnter => {
          emit(event)
          indent.val += 1
        }
        RuleMatch | RuleFail => {
          indent.val -= 1
          emit(event)
        }
      }
    },
  }
}

///|
priv struct ExpectFrame {
  mut pos : Int
  mut variants : Array[Expectation]
}

///|
/// A memoized rule result (the `cache` option).
pub(all) struct CacheEntry[T] {
  next_pos : Int
  result : Slot[T]
  expectations : Array[Expectation]
}

///|
pub(all) struct State[T] {
  input : String
  mut curr_pos : Int
  mut saved_pos : Int
  mut silent_fails : Int
  priv expected : Array[ExpectFrame]
  priv pos_cache : PosCache
  priv results_cache : Map[(Int, Int), CacheEntry[T]]
  tracer : Tracer[T]?
  options : Map[String, Value[T]]
  features : Features
}

///|
pub fn[T] State::new(
  input : String,
  options~ : Map[String, Value[T]],
  features~ : Features,
  tracer? : Tracer[T],
) -> State[T] {
  let filename = match options.get("filename") {
    Some(Str(f)) if features.filename && f != "" => Some(f)
    _ => None
  }
  {
    input,
    curr_pos: 0,
    saved_pos: 0,
    silent_fails: 0,
    expected: [],
    pos_cache: PosCache::new(input, filename?),
    results_cache: {},
    tracer,
    options,
    features,
  }
}

///|
/// JavaScript `String.prototype.substring`: clamps and swaps its bounds.
pub fn js_substring(s : String, start : Int, end : Int) -> String {
  let len = s.length()
  let a = if start < 0 { 0 } else if start > len { len } else { start }
  let b = if end < 0 { 0 } else if end > len { len } else { end }
  if a <= b {
    s.unsafe_substring(start=a, end=b)
  } else {
    s.unsafe_substring(start=b, end=a)
  }
}

///|
pub fn[T] State::compute_location(
  self : State[T],
  start : Int,
  end : Int,
) -> Location {
  self.pos_cache.location(start, end)
}

///|
/// `peg$begin`: opens a new expectation namespace at the current position.
pub fn[T] State::begin(self : State[T]) -> Unit {
  self.expected.push({ pos: self.curr_pos, variants: [], })
}

///|
/// `peg$expect`: records an expectation at the current position.
pub fn[T] State::expect(self : State[T], expected : Expectation) -> Unit {
  let top = self.expected[self.expected.length() - 1]
  if self.curr_pos < top.pos {
    return
  }
  if self.curr_pos > top.pos {
    top.pos = self.curr_pos
    top.variants = []
  }
  top.variants.push(expected)
}

///|
/// `peg$end`: closes the innermost namespace, merging its expectations into
/// the enclosing one (negated when `invert`) if both are at the same position.
pub fn[T] State::end(self : State[T], invert : Bool) -> Unit {
  let expected = self.expected.pop().unwrap()
  let top = self.expected[self.expected.length() - 1]
  if top.pos != expected.pos {
    return
  }
  for e in expected.variants {
    top.variants.push(
      if invert {
        match e {
          Not(inner) => inner
          _ => Not(e)
        }
      } else {
        e
      },
    )
  }
}

///|
/// `rule$expects` without caching: records unless failures are silenced.
pub fn[T] State::rule_expects(self : State[T], expected : Expectation) -> Unit {
  if self.silent_fails == 0 {
    self.expect(expected)
  }
}

///|
/// Looks up a memoized result for `rule` at the current position. On a hit,
/// restores the position and replays the recorded expectations.
pub fn[T] State::cache_lookup(self : State[T], rule : Int) -> CacheEntry[T]? {
  match self.results_cache.get((self.curr_pos, rule)) {
    Some(entry) => {
      self.curr_pos = entry.next_pos
      if self.silent_fails == 0 {
        for e in entry.expectations {
          self.expect(e)
        }
      }
      Some(entry)
    }
    None => None
  }
}

///|
pub fn[T] State::cache_store(
  self : State[T],
  rule : Int,
  start_pos : Int,
  result : Slot[T],
  expectations : Array[Expectation],
) -> Unit {
  self.results_cache[(start_pos, rule)] = {
    next_pos: self.curr_pos,
    result,
    expectations,
  }
}

///|
/// Emits a trace event if tracing is enabled.
pub fn[T] State::trace(
  self : State[T],
  type_ : TraceType,
  rule : String,
  start_pos : Int,
  result? : Slot[T],
) -> Unit raise {
  guard self.tracer is Some(tracer) else { return }
  let (location, value) = match (type_, result) {
    (RuleMatch, Some(Val(v))) =>
      (self.compute_location(start_pos, self.curr_pos), Some(v))
    (RuleMatch, _) => (self.compute_location(start_pos, self.curr_pos), None)
    _ => (self.compute_location(start_pos, start_pos), None)
  }
  (tracer.trace)({ type_, rule, result: value, location, })
}

///|
/// `peg$buildError` + the final end-of-input check of `peg$parse`.
pub fn[T] State::finish(self : State[T], result : Slot[T]) -> Value[T] raise {
  if result is Val(v) && self.curr_pos == self.input.length() {
    return v
  }
  if !(result is Failed) && self.curr_pos < self.input.length() {
    self.expect(End)
  }
  let expected = self.expected[0]
  let fail_pos = expected.pos
  let (found, location) = if fail_pos < self.input.length() {
    (
      Some(self.input.unsafe_substring(start=fail_pos, end=fail_pos + 1)),
      self.compute_location(fail_pos, fail_pos + 1),
    )
  } else {
    (None, self.compute_location(fail_pos, fail_pos))
  }
  raise SyntaxError(
    message=build_message(expected.variants, found),
    expected=Some(expected.variants),
    found~,
    location~,
  )
}

///|
/// The helpers available to actions, predicates and initializers: labeled
/// values plus the PEG.js `text()`, `location()`, `error()`... functions.
pub struct ActionContext[T] {
  state : State[T]
  params : ArrayView[String]
  args : ArrayView[Value[T]]
}

///|
pub fn[T] ActionContext::new(
  state : State[T],
  params : ArrayView[String],
  args : ArrayView[Value[T]],
) -> ActionContext[T] {
  { state, params, args, }
}

///|
/// The value bound to `label`. Aborts if the label is not in scope (a
/// `ReferenceError` in PEG.js).
pub fn[T] ActionContext::label(
  self : ActionContext[T],
  label : String,
) -> Value[T] {
  for i, p in self.params {
    if p == label {
      return self.args[i]
    }
  }
  abort("label \"\{label}\" is not defined")
}

///|
/// Like `label`, but `None` when the label is not in scope.
pub fn[T] ActionContext::label_opt(
  self : ActionContext[T],
  label : String,
) -> Value[T]? {
  for i, p in self.params {
    if p == label {
      return Some(self.args[i])
    }
  }
  None
}

///|
pub fn[T] ActionContext::input(self : ActionContext[T]) -> String {
  self.state.input
}

///|
pub fn[T] ActionContext::options(
  self : ActionContext[T],
) -> Map[String, Value[T]] {
  self.state.options
}

///|
pub fn[T] ActionContext::text(self : ActionContext[T]) -> String raise {
  guard self.state.features.text else { raise FeatureDisabled("text") }
  js_substring(self.state.input, self.state.saved_pos, self.state.curr_pos)
}

///|
pub fn[T] ActionContext::offset(self : ActionContext[T]) -> Int raise {
  guard self.state.features.offset else { raise FeatureDisabled("offset") }
  self.state.saved_pos
}

///|
pub fn[T] ActionContext::range(self : ActionContext[T]) -> (Int, Int) raise {
  guard self.state.features.range else { raise FeatureDisabled("range") }
  (self.state.saved_pos, self.state.curr_pos)
}

///|
pub fn[T] ActionContext::location(self : ActionContext[T]) -> Location raise {
  guard self.state.features.location else { raise FeatureDisabled("location") }
  self.state.compute_location(self.state.saved_pos, self.state.curr_pos)
}

///|
/// Aborts the parse with a "expected <description>" syntax error.
pub fn[T, R] ActionContext::expected(
  self : ActionContext[T],
  description : String,
  location? : Location,
) -> R raise {
  guard self.state.features.expected else { raise FeatureDisabled("expected") }
  let state = self.state
  let location = match location {
    Some(l) => l
    None => state.compute_location(state.saved_pos, state.curr_pos)
  }
  let expected = [Expectation::Other(description~)]
  let found = js_substring(state.input, state.saved_pos, state.curr_pos)
  raise SyntaxError(
    message=build_message(expected, Some(found)),
    expected=Some(expected),
    found=Some(found),
    location~,
  )
}

///|
/// Aborts the parse with a syntax error carrying `message`.
pub fn[T, R] ActionContext::error(
  self : ActionContext[T],
  message : String,
  location? : Location,
) -> R raise {
  guard self.state.features.error else { raise FeatureDisabled("error") }
  let state = self.state
  let location = match location {
    Some(l) => l
    None => state.compute_location(state.saved_pos, state.curr_pos)
  }
  raise SyntaxError(message~, expected=None, found=None, location~)
}
