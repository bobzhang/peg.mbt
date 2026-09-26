// Compilation of rule bytecode to straight-line MoonBit (`optimize = speed`),
// following `generateRuleFunction` of PEG.js' generate-js.js: the machine
// stack is tracked at compile time and mapped to variables `s0`, `s1`, ...

///|
priv struct RuleCompiler {
  program : @bytecode.Program
  rule_index : Int
  rule_name : String
  mut sp : Int
  mut max_sp : Int
}

///|
fn RuleCompiler::slot_var(self : RuleCompiler, i : Int) -> String raise {
  if i < 0 {
    raise @compiler.CompilerError(
      "Rule '\{self.rule_name}': Var stack underflow: attempt to use var at index \{i}",
    )
  }
  "s\{i}"
}

///|
fn RuleCompiler::push(self : RuleCompiler, expr : String) -> String raise {
  self.sp += 1
  if self.sp > self.max_sp {
    self.max_sp = self.sp
  }
  self.slot_var(self.sp) + " = " + expr
}

///|
fn RuleCompiler::pop(self : RuleCompiler) -> String raise {
  let v = self.slot_var(self.sp)
  self.sp -= 1
  v
}

///|
fn RuleCompiler::pop_n(self : RuleCompiler, n : Int) -> Array[String] raise {
  let values = []
  for i in 0..<n {
    values.push(self.slot_var(self.sp - n + 1 + i))
  }
  self.sp -= n
  values
}

///|
fn RuleCompiler::top(self : RuleCompiler) -> String raise {
  self.slot_var(self.sp)
}

///|
fn RuleCompiler::index(self : RuleCompiler, i : Int) -> String raise {
  self.slot_var(self.sp - i)
}

///|
fn value_of(v : String) -> String {
  "@runtime.slot_value(" + v + ")"
}

///|
fn pos_of(v : String) -> String {
  "@runtime.slot_pos(" + v + ")"
}

///|
fn RuleCompiler::compile(
  self : RuleCompiler,
  bc : ArrayView[Int],
) -> Array[String] raise {
  let op = self.program.opcodes
  let program = self.program
  let parts : Array[String] = []
  let mut ip = 0
  fn condition(cond : String, arg_count : Int) raise {
    let pos = ip
    let base = arg_count + 3
    let then_length = bc[ip + base - 2]
    let else_length = bc[ip + base - 1]
    let base_sp = self.sp
    ip += base
    let then_code = self.compile(bc[ip:ip + then_length])
    let then_sp = self.sp
    ip += then_length
    let else_code = if else_length > 0 {
      self.sp = base_sp
      let code = self.compile(bc[ip:ip + else_length])
      let else_sp = self.sp
      ip += else_length
      if then_sp != else_sp {
        raise @compiler.CompilerError(
          "Rule '\{self.rule_name}', position \{pos}: Branches of a condition can't move the stack pointer differently (before: \{base_sp}, after then: \{then_sp}, after else: \{else_sp}).",
        )
      }
      Some(code)
    } else {
      None
    }
    parts.push("if " + cond + " {")
    for line in then_code {
      parts.push("  " + line)
    }
    if else_code is Some(code) {
      parts.push("} else {")
      for line in code {
        parts.push("  " + line)
      }
    }
    parts.push("}")
  }

  fn loop_(cond : String) raise {
    let pos = ip
    let body_length = bc[ip + 1]
    let base_sp = self.sp
    ip += 2
    let body = self.compile(bc[ip:ip + body_length])
    let body_sp = self.sp
    ip += body_length
    if body_sp != base_sp {
      raise @compiler.CompilerError(
        "Rule '\{self.rule_name}', position \{pos}: Body of a loop can't move the stack pointer (before: \{base_sp}, after: \{body_sp}).",
      )
    }
    parts.push("while " + cond + " {")
    for line in body {
      parts.push("  " + line)
    }
    parts.push("}")
  }

  while ip < bc.length() {
    let code = bc[ip]
    if code == op.push_empty_string {
      parts.push(self.push("Val(Str(\"\"))"))
      ip += 1
    } else if code == op.push_curr_pos {
      parts.push(self.push("Pos(state.curr_pos)"))
      ip += 1
    } else if code == op.push_undefined {
      parts.push(self.push("Val(Undefined)"))
      ip += 1
    } else if code == op.push_null {
      parts.push(self.push("Val(Null)"))
      ip += 1
    } else if code == op.push_failed {
      parts.push(self.push("Failed"))
      ip += 1
    } else if code == op.push_empty_array {
      parts.push(self.push("Val(Arr([]))"))
      ip += 1
    } else if code == op.pop {
      self.pop() |> ignore
      ip += 1
    } else if code == op.pop_curr_pos {
      parts.push("state.curr_pos = " + pos_of(self.pop()))
      ip += 1
    } else if code == op.pop_n {
      self.pop_n(bc[ip + 1]) |> ignore
      ip += 2
    } else if code == op.nip {
      let value = self.pop()
      self.pop() |> ignore
      parts.push(self.push(value))
      ip += 1
    } else if code == op.append {
      let value = self.pop()
      parts.push("@runtime.slot_append(" + self.top() + ", " + value + ")")
      ip += 1
    } else if code == op.wrap {
      let values = self.pop_n(bc[ip + 1]).map(value_of)
      parts.push(self.push("Val(Arr([" + values.join(", ") + "]))"))
      ip += 2
    } else if code == op.text {
      let start = pos_of(self.pop())
      parts.push(
        self.push(
          "Val(Str(@runtime.js_substring(input, " +
          start +
          ", state.curr_pos)))",
        ),
      )
      ip += 1
    } else if code == op.pluck {
      let params_length = bc[ip + 2]
      let n = 3 + params_length
      let value = if params_length == 1 {
        self.index(bc[ip + 3])
      } else {
        let values = []
        for i in 0..<params_length {
          values.push(value_of(self.index(bc[ip + 3 + i])))
        }
        "Val(Arr([" + values.join(", ") + "]))"
      }
      self.pop_n(bc[ip + 1]) |> ignore
      parts.push(self.push(value))
      ip += n
    } else if code == op.if_ {
      condition(value_of(self.top()) + ".truthy()", 0)
    } else if code == op.if_error {
      condition(self.top() + " is Failed", 0)
    } else if code == op.if_not_error {
      condition("!(" + self.top() + " is Failed)", 0)
    } else if code == op.while_not_error {
      loop_("!(" + self.top() + " is Failed)")
    } else if code == op.match_any {
      condition("input.length() > state.curr_pos", 0)
    } else if code == op.match_string {
      let lit = program.literals[bc[ip + 1]]
      condition(
        if lit.length() > 1 {
          "@runtime.starts_with_at(input, state.curr_pos, \u{E000}peg_c\{bc[ip + 1]})"
        } else {
          "@runtime.code_unit_is(input, state.curr_pos, \{lit.code_unit_at(0).to_int()})"
        },
        1,
      )
    } else if code == op.match_string_ic {
      condition(
        "@runtime.matches_ignore_case_at(input, state.curr_pos, \u{E000}peg_c\{bc[ip + 1]})",
        1,
      )
    } else if code == op.match_class {
      condition(
        "\u{E000}peg_r\{bc[ip + 1]}.matches_at(input, state.curr_pos)",
        1,
      )
    } else if code == op.accept_n {
      let n = bc[ip + 1]
      parts.push(
        self.push("Val(Str(@runtime.js_substr(input, state.curr_pos, \{n})))"),
      )
      parts.push("state.curr_pos += \{n}")
      ip += 2
    } else if code == op.accept_string {
      let i = bc[ip + 1]
      parts.push(self.push("Val(Str(\u{E000}peg_c\{i}))"))
      parts.push("state.curr_pos += \{program.literals[i].length()}")
      ip += 2
    } else if code == op.expect {
      parts.push("state.rule_expects(\u{E000}peg_e\{bc[ip + 1]})")
      if program.cache {
        parts.push("rule_expectations.push(\u{E000}peg_e\{bc[ip + 1]})")
      }
      ip += 2
    } else if code == op.load_saved_pos {
      parts.push("state.saved_pos = " + pos_of(self.index(bc[ip + 1])))
      ip += 2
    } else if code == op.update_saved_pos {
      parts.push("state.saved_pos = state.curr_pos")
      ip += 1
    } else if code == op.call {
      let f = bc[ip + 1]
      let params_length = bc[ip + 3]
      let args = []
      for i in 0..<params_length {
        args.push(value_of(self.index(bc[ip + 4 + i])))
      }
      let call = "(p.actions.f\{f})(" + args.join(", ") + ")"
      let value = if program.functions[f].predicate {
        "Val(Bool(" + call + "))"
      } else {
        "Val(" + call + ")"
      }
      self.pop_n(bc[ip + 2]) |> ignore
      parts.push(self.push(value))
      ip += 4 + params_length
    } else if code == op.rule {
      parts.push(self.push("\u{E000}peg_parse_\{bc[ip + 1]}(p)"))
      ip += 2
    } else if code == op.silent_fails_on {
      parts.push("state.silent_fails += 1")
      ip += 1
    } else if code == op.silent_fails_off {
      parts.push("state.silent_fails -= 1")
      ip += 1
    } else if code == op.expect_ns_begin {
      parts.push("state.begin()")
      ip += 1
    } else if code == op.expect_ns_end {
      parts.push("state.end(" + bool_literal(bc[ip + 1] != 0) + ")")
      ip += 2
    } else {
      raise @compiler.CompilerError(
        "Rule '\{self.rule_name}', position \{ip}: Invalid opcode \{code}.",
      )
    }
  }
  parts
}

///|
/// Generates `fn peg_parse_<index>(p : PegParser) -> PegSlot raise`.
fn rule_function(program : @bytecode.Program, index : Int) -> String raise {
  let rule = program.rules[index]
  let compiler : RuleCompiler = {
    program,
    rule_index: index,
    rule_name: rule.name,
    sp: -1,
    max_sp: -1,
  }
  let body = compiler.compile(rule.bytecode[:])
  let name = string_literal(rule.name)
  let lines = []
  lines.push("///|")
  lines.push("/// Rule \{name}.")
  lines.push("#warnings(\"-unused_value-unused_error_type-unused_mut\")")
  lines.push(
    "fn \u{E000}peg_parse_\{index}(p : \u{E001}PegParser) -> \u{E001}PegSlot raise {",
  )
  lines.push("  let state = p.state")
  lines.push("  let input = state.input")
  lines.push("  let start_pos = state.curr_pos")
  if program.cache {
    lines.push("  let rule_expectations : Array[@runtime.Expectation] = []")
  }
  if program.trace {
    lines.push("  state.trace(RuleEnter, \{name}, start_pos)")
  }
  if program.cache {
    lines.push("  if state.cache_lookup(\{index}) is Some(entry) {")
    if program.trace {
      lines.push(
        "    state.trace(if entry.result is Failed { RuleFail } else { RuleMatch }, \{name}, start_pos, result=entry.result)",
      )
    }
    lines.push("    return entry.result")
    lines.push("  }")
  }
  for i in 0..<=compiler.max_sp {
    lines.push("  let mut s\{i} : \u{E001}PegSlot = Failed")
  }
  for line in body {
    lines.push("  " + line)
  }
  if program.cache {
    lines.push(
      "  state.cache_store(\{index}, start_pos, s0, rule_expectations)",
    )
  }
  if program.trace {
    lines.push(
      "  state.trace(if s0 is Failed { RuleFail } else { RuleMatch }, \{name}, start_pos, result=s0)",
    )
  }
  lines.push("  s0")
  lines.push("}")
  lines.join("\n")
}
