// Bytecode interpreter: the MoonBit counterpart of the `peg$parseRule`
// function PEG.js generates with `optimize: "size"`.

///|
priv enum Op {
  PushEmptyString
  PushUndefined
  PushNull
  PushFailed
  PushEmptyArray
  PushCurrPos
  Pop
  PopCurrPos
  PopN
  Nip
  Append
  Wrap
  Text
  Pluck
  If
  IfError
  IfNotError
  WhileNotError
  MatchAny
  MatchString
  MatchStringIc
  MatchClass
  AcceptN
  AcceptString
  Expect
  LoadSavedPos
  UpdateSavedPos
  Call
  Rule
  SilentFailsOn
  SilentFailsOff
  ExpectNsBegin
  ExpectNsEnd
  Invalid
}

///|
/// Maps opcode numbers of `ops` to interpreter operations.
fn decode_table(ops : @bytecode.Opcodes) -> Map[Int, Op] {
  Map::from_array([
    (ops.push_empty_string, PushEmptyString),
    (ops.push_undefined, PushUndefined),
    (ops.push_null, PushNull),
    (ops.push_failed, PushFailed),
    (ops.push_empty_array, PushEmptyArray),
    (ops.push_curr_pos, PushCurrPos),
    (ops.pop, Pop),
    (ops.pop_curr_pos, PopCurrPos),
    (ops.pop_n, PopN),
    (ops.nip, Nip),
    (ops.append, Append),
    (ops.wrap, Wrap),
    (ops.text, Text),
    (ops.pluck, Pluck),
    (ops.if_, If),
    (ops.if_error, IfError),
    (ops.if_not_error, IfNotError),
    (ops.while_not_error, WhileNotError),
    (ops.match_any, MatchAny),
    (ops.match_string, MatchString),
    (ops.match_string_ic, MatchStringIc),
    (ops.match_class, MatchClass),
    (ops.accept_n, AcceptN),
    (ops.accept_string, AcceptString),
    (ops.expect, Expect),
    (ops.load_saved_pos, LoadSavedPos),
    (ops.update_saved_pos, UpdateSavedPos),
    (ops.call, Call),
    (ops.rule, Rule),
    (ops.silent_fails_on, SilentFailsOn),
    (ops.silent_fails_off, SilentFailsOff),
    (ops.expect_ns_begin, ExpectNsBegin),
    (ops.expect_ns_end, ExpectNsEnd),
  ])
}

///|
/// A rule's bytecode with opcodes pre-decoded.
priv struct DecodedRule {
  name : String
  code : Array[Int]
  ops : Array[Op]
}

///|
/// Program data shared by all parses of one parser.
priv struct Machine[T] {
  program : @bytecode.Program
  rules : Array[DecodedRule]
  classes : Array[@runtime.ClassMatcher]
  static_bindings : Map[String, ActionFn[T]]
  initializer : InitFn[T]?
}

///|
/// Per-parse execution: the machine plus parse state and resolved actions.
priv struct Run[T] {
  machine : Machine[T]
  state : @runtime.State[T]
  functions : Array[ActionFn[T]]
}

///|
fn[T] slot_value(slot : @runtime.Slot[T]) -> Value[T] {
  match slot {
    Val(v) => v
    Failed => abort("unexpected FAILED marker used as a value")
    Pos(_) => abort("unexpected position used as a value")
  }
}

///|
fn[T] slot_pos(slot : @runtime.Slot[T]) -> Int {
  match slot {
    Pos(p) => p
    _ => abort("expected a saved position on the stack")
  }
}

///|
fn starts_with_at(input : String, pos : Int, lit : String) -> Bool {
  if pos + lit.length() > input.length() {
    return false
  }
  for i in 0..<lit.length() {
    if input.code_unit_at(pos + i) != lit.code_unit_at(i) {
      return false
    }
  }
  true
}

///|
/// `input.substr(pos, n)`.
fn substr(input : String, pos : Int, n : Int) -> String {
  let end = if pos + n > input.length() { input.length() } else { pos + n }
  if pos >= end {
    ""
  } else {
    input.unsafe_substring(start=pos, end~)
  }
}

///|
fn[T] Run::call_function(
  self : Run[T],
  index : Int,
  params : ArrayView[String],
  args : Array[Value[T]],
) -> Value[T] raise {
  let ctx = @runtime.ActionContext::new(self.state, params, args[:])
  self.functions[index](ctx)
}

///|
fn[T] Run::parse_rule(self : Run[T], index : Int) -> @runtime.Slot[T] raise {
  let machine = self.machine
  let program = machine.program
  let state = self.state
  let rule = machine.rules[index]
  let bc = rule.code
  let ops = rule.ops
  let start_pos = state.curr_pos
  let rule_expectations : Array[@runtime.Expectation] = []
  if program.trace {
    state.trace(RuleEnter, rule.name, start_pos)
  }
  if program.cache {
    if state.cache_lookup(index) is Some(entry) {
      if program.trace {
        state.trace(
          if entry.result is Failed {
            RuleFail
          } else {
            RuleMatch
          },
          rule.name,
          start_pos,
          result=entry.result,
        )
      }
      return entry.result
    }
  }
  let stack : Array[@runtime.Slot[T]] = []
  let ips : Array[Int] = []
  let ends : Array[Int] = []
  let mut ip = 0
  let mut end = bc.length()
  fn top() {
    stack[stack.length() - 1]
  }

  // Pushes the current block, then continues in the then/else branch.
  fn condition(cond : Bool, args_length : Int) {
    let base = args_length + 3
    let then_length = bc[ip + base - 2]
    let else_length = bc[ip + base - 1]
    ends.push(end)
    ips.push(ip + base + then_length + else_length)
    if cond {
      end = ip + base + then_length
      ip += base
    } else {
      end = ip + base + then_length + else_length
      ip += base + then_length
    }
  }

  let input = state.input
  while true {
    while ip < end {
      match ops[ip] {
        PushEmptyString => {
          stack.push(Val(Str("")))
          ip += 1
        }
        PushUndefined => {
          stack.push(Val(Undefined))
          ip += 1
        }
        PushNull => {
          stack.push(Val(Null))
          ip += 1
        }
        PushFailed => {
          stack.push(Failed)
          ip += 1
        }
        PushEmptyArray => {
          stack.push(Val(Arr([])))
          ip += 1
        }
        PushCurrPos => {
          stack.push(Pos(state.curr_pos))
          ip += 1
        }
        Pop => {
          stack.pop() |> ignore
          ip += 1
        }
        PopCurrPos => {
          state.curr_pos = slot_pos(stack.pop().unwrap())
          ip += 1
        }
        PopN => {
          stack.truncate(stack.length() - bc[ip + 1])
          ip += 2
        }
        Nip => {
          let v = stack.pop().unwrap()
          stack[stack.length() - 1] = v
          ip += 1
        }
        Append => {
          let v = slot_value(stack.pop().unwrap())
          match top() {
            Val(Arr(arr)) => arr.push(v)
            _ => abort("APPEND target is not an array")
          }
          ip += 1
        }
        Wrap => {
          let n = bc[ip + 1]
          let base = stack.length() - n
          let values = Array::makei(n, i => slot_value(stack[base + i]))
          stack.truncate(base)
          stack.push(Val(Arr(values)))
          ip += 2
        }
        Text => {
          let start = slot_pos(stack.pop().unwrap())
          stack.push(
            Val(Str(@runtime.js_substring(input, start, state.curr_pos))),
          )
          ip += 1
        }
        Pluck => {
          let n = bc[ip + 1]
          let k = bc[ip + 2]
          let len = stack.length()
          let value = if k == 1 {
            slot_value(stack[len - 1 - bc[ip + 3]])
          } else {
            Arr(
              Array::makei(k, i => slot_value(stack[len - 1 - bc[ip + 3 + i]])),
            )
          }
          stack.truncate(len - n)
          stack.push(Val(value))
          ip += 3 + k
        }
        If => condition(slot_value(top()).truthy(), 0)
        IfError => condition(top() is Failed, 0)
        IfNotError => condition(!(top() is Failed), 0)
        WhileNotError => {
          let body_length = bc[ip + 1]
          if !(top() is Failed) {
            ends.push(end)
            ips.push(ip)
            end = ip + 2 + body_length
            ip += 2
          } else {
            ip += 2 + body_length
          }
        }
        MatchAny => condition(input.length() > state.curr_pos, 0)
        MatchString =>
          condition(
            starts_with_at(input, state.curr_pos, program.literals[bc[ip + 1]]),
            1,
          )
        MatchStringIc => {
          let lit = program.literals[bc[ip + 1]]
          let chunk = substr(input, state.curr_pos, lit.length())
          condition(@runtime.js_to_lower(chunk) == lit, 1)
        }
        MatchClass =>
          condition(
            machine.classes[bc[ip + 1]].matches_at(input, state.curr_pos),
            1,
          )
        AcceptN => {
          let n = bc[ip + 1]
          stack.push(Val(Str(substr(input, state.curr_pos, n))))
          state.curr_pos += n
          ip += 2
        }
        AcceptString => {
          let lit = program.literals[bc[ip + 1]]
          stack.push(Val(Str(lit)))
          state.curr_pos += lit.length()
          ip += 2
        }
        Expect => {
          let e = program.expectations[bc[ip + 1]]
          state.rule_expects(e)
          if program.cache {
            rule_expectations.push(e)
          }
          ip += 2
        }
        LoadSavedPos => {
          state.saved_pos = slot_pos(stack[stack.length() - 1 - bc[ip + 1]])
          ip += 2
        }
        UpdateSavedPos => {
          state.saved_pos = state.curr_pos
          ip += 1
        }
        Call => {
          let f = bc[ip + 1]
          let n = bc[ip + 2]
          let pc = bc[ip + 3]
          let len = stack.length()
          let args = Array::makei(pc, i => {
            slot_value(stack[len - 1 - bc[ip + 4 + i]])
          })
          let value = self.call_function(
            f,
            program.functions[f].params[:],
            args,
          )
          stack.truncate(len - n)
          stack.push(Val(value))
          ip += 4 + pc
        }
        Rule => {
          stack.push(self.parse_rule(bc[ip + 1]))
          ip += 2
        }
        SilentFailsOn => {
          state.silent_fails += 1
          ip += 1
        }
        SilentFailsOff => {
          state.silent_fails -= 1
          ip += 1
        }
        ExpectNsBegin => {
          state.begin()
          ip += 1
        }
        ExpectNsEnd => {
          state.end(bc[ip + 1] != 0)
          ip += 2
        }
        Invalid =>
          abort(
            "Rule #\{index} ('\{rule.name}'), position \{ip}: Invalid opcode \{bc[ip]}.",
          )
      }
    }
    if ends.length() > 0 {
      end = ends.pop().unwrap()
      ip = ips.pop().unwrap()
    } else {
      break
    }
  }
  let result = stack[0]
  if program.cache {
    state.cache_store(index, start_pos, result, rule_expectations)
  }
  if program.trace {
    state.trace(
      if result is Failed {
        RuleFail
      } else {
        RuleMatch
      },
      rule.name,
      start_pos,
      result~,
    )
  }
  result
}

///|
fn[T] Machine::run(
  self : Machine[T],
  input : String,
  options : Map[String, Value[T]],
  tracer : Tracer[T]?,
) -> Value[T] raise {
  let program = self.program
  let start_index = match options.get("startRule") {
    Some(Str(name)) =>
      match program.allowed_start_rules.contains(name) {
        true => program.rule_index(name).unwrap()
        false => raise @runtime.InvalidStartRule(name)
      }
    Some(other) => raise @runtime.InvalidStartRule(other.js_string())
    None => program.rule_index(program.allowed_start_rules[0]).unwrap()
  }
  let tracer = if program.trace {
    match tracer {
      Some(t) => Some(t)
      None =>
        if program.features.default_tracer {
          Some(Tracer::default())
        } else {
          Some(Tracer::{ trace: _ => (), })
        }
    }
  } else {
    None
  }
  let state = @runtime.State::new(
    input,
    options~,
    features=program.features,
    tracer?,
  )
  // The initializer runs per parse, after start rule validation.
  let bindings = match self.initializer {
    Some(init) => {
      let dynamic = init(@runtime.ActionContext::new(state, [][:], [][:]))
      let merged = self.static_bindings.copy()
      for k, v in dynamic {
        merged[k] = v
      }
      merged
    }
    None => self.static_bindings
  }
  let functions = []
  for i, f in program.functions {
    match lookup_binding(bindings, i, f.body) {
      Some(impl_) => functions.push(impl_)
      None =>
        raise UnboundCode(
          kind=if f.predicate { "predicate" } else { "action" },
          code=f.body,
        )
    }
  }
  let run = { machine: self, state, functions, }
  state.begin()
  let result = run.parse_rule(start_index)
  state.finish(result)
}

///|
/// Builds a parser interpreting `program`.
///
/// Each action / predicate code block is implemented by the entry of
/// `actions` keyed by its exact body or trimmed body (see `lookup_binding`).
/// A grammar initializer requires `initializer`, which runs per parse and may
/// supply further bindings. Raises `UnboundCode` for missing bindings (at
/// parse time for bindings the initializer is expected to provide).
pub fn[T] Parser::from_program(
  program : @bytecode.Program,
  actions? : Map[String, ActionFn[T]] = {},
  initializer? : InitFn[T],
) -> Parser[T] raise UnboundCode {
  if program.initializer is Some(code) && initializer is None {
    raise UnboundCode(kind="initializer", code~)
  }
  if initializer is None {
    for i, f in program.functions {
      if lookup_binding(actions, i, f.body) is None {
        raise UnboundCode(
          kind=if f.predicate { "predicate" } else { "action" },
          code=f.body,
        )
      }
    }
  }
  let table = decode_table(program.opcodes)
  let rules = program.rules.map(r => DecodedRule::{
    name: r.name,
    code: r.bytecode,
    ops: r.bytecode.map(b => {
      match table.get(b) {
        Some(op) => op
        None => Invalid
      }
    }),
  })
  let classes = program.classes.map(c => {
    @runtime.ClassMatcher::new(
      c.parts[:],
      inverted=c.inverted,
      ignore_case=c.ignore_case,
    )
  })
  let machine = {
    program,
    rules,
    classes,
    static_bindings: actions,
    initializer,
  }
  {
    parse_impl: (input, options, tracer) => machine.run(input, options, tracer),
    program: Some(program),
  }
}
