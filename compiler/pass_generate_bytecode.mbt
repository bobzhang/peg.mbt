// Bytecode generation (`generate-bytecode.js`). See that file for the
// instruction set semantics; the implementation below follows it closely,
// including its label-environment cloning rules.

///|
priv struct BytecodeContext {
  sp : Int
  /// Label name -> stack position.
  env : JsDict[Int]
  /// Stack positions of plucked (`@`) elements of the enclosing sequence.
  pluck : Array[Int]?
  /// Action node whose code the enclosing sequence calls.
  action : @ast.Node?
  report_failures : Bool
}

///|
priv struct BytecodeTables {
  literals : Array[String]
  classes : Array[@bytecode.ClassConst]
  expectations : Array[@runtime.Expectation]
  functions : Array[@bytecode.FunctionConst]
}

///|
fn[X : Eq] add_const(table : Array[X], value : X) -> Int {
  for i, x in table {
    if x == value {
      return i
    }
  }
  table.push(value)
  table.length() - 1
}

///|
fn build_condition(
  match_ : Int,
  cond_code : Array[Int],
  then_code : Array[Int],
  else_code : Array[Int],
) -> Array[Int] {
  if match_ > 0 {
    return then_code
  }
  if match_ < 0 {
    return else_code
  }
  [
    ..cond_code,
    then_code.length(),
    else_code.length(),
    ..then_code,
    ..else_code,
  ]
}

///|
fn build_loop(cond_code : Array[Int], body_code : Array[Int]) -> Array[Int] {
  [..cond_code, body_code.length(), ..body_code]
}

///|
fn match_of(node : @ast.Node) -> Int {
  node.match_result.unwrap_or(0)
}

///|
/// Generates bytecode for every rule and stores the constant tables on the
/// grammar.
#warnings("-unused_error_type")
pub fn[T] generate_bytecode(
  grammar : @ast.Grammar,
  session : Session[T],
  _options : Options[T],
) -> Unit raise {
  let op = session.opcodes
  let tables : BytecodeTables = {
    literals: [],
    classes: [],
    expectations: [],
    functions: [],
  }
  fn add_function_const(
    predicate : Bool,
    params : Array[String],
    code : String,
  ) -> Int {
    add_const(tables.functions, { predicate, params, body: code, })
  }

  fn build_call(
    function_index : Int,
    delta : Int,
    env : JsDict[Int],
    sp : Int,
  ) -> Array[Int] {
    let params = env.keys().map(k => sp - env.get(k).unwrap())
    [op.call, function_index, delta, params.length(), ..params]
  }

  fn generate(node : @ast.Node, context : BytecodeContext) -> Array[Int] {
    fn build_simple_predicate(
      expression : @ast.Node,
      negative : Bool,
      context : BytecodeContext,
    ) -> Array[Int] {
      let match_ = match_of(expression)
      [
        op.push_curr_pos,
        op.expect_ns_begin,
        ..generate(expression, {
          sp: context.sp + 1,
          env: context.env.clone(),
          pluck: None,
          action: None,
          report_failures: context.report_failures,
        }),
        op.expect_ns_end,
        if negative {
          1
        } else {
          0
        },
        ..build_condition(
          if negative {
            -match_
          } else {
            match_
          },
          [if negative { op.if_error } else { op.if_not_error }],
          [
            op.pop,
            if negative {
              op.pop
            } else {
              op.pop_curr_pos
            },
            op.push_undefined,
          ],
          [
            op.pop,
            if negative {
              op.pop_curr_pos
            } else {
              op.pop
            },
            op.push_failed,
          ],
        ),
      ]
    }

    fn build_semantic_predicate(
      node : @ast.Node,
      code : String,
      negative : Bool,
      context : BytecodeContext,
    ) -> Array[Int] {
      let function_index = add_function_const(true, context.env.keys(), code)
      [
        op.update_saved_pos,
        ..build_call(function_index, 0, context.env, context.sp),
        ..build_condition(
          match_of(node),
          [op.if_],
          [op.pop, if negative { op.push_failed } else { op.push_undefined }],
          [op.pop, if negative { op.push_undefined } else { op.push_failed }],
        ),
      ]
    }

    match node.kind {
      Named(expression, name~) => {
        let name_index = if context.report_failures {
          add_const(tables.expectations, Other(description=name))
        } else {
          -1
        }
        let expression_code = generate(expression, {
          sp: context.sp,
          env: context.env,
          pluck: None,
          action: context.action,
          report_failures: false,
        })
        if context.report_failures {
          [
            op.expect,
            name_index,
            op.silent_fails_on,
            ..expression_code,
            op.silent_fails_off,
          ]
        } else {
          expression_code
        }
      }
      Choice(alternatives) => {
        fn build_alternatives(
          alternatives : ArrayView[@ast.Node],
        ) -> Array[Int] {
          let first = generate(alternatives[0], {
            sp: context.sp,
            env: context.env.clone(),
            pluck: None,
            action: None,
            report_failures: context.report_failures,
          })
          if alternatives.length() < 2 {
            return first
          }
          [
            ..first,
            ..build_condition(
              -match_of(alternatives[0]),
              [op.if_error],
              [op.pop, ..build_alternatives(alternatives[1:])],
              [],
            ),
          ]
        }

        build_alternatives(alternatives[:])
      }
      Action(expression, code~) => {
        let env = context.env.clone()
        let emit_call = match expression.kind {
          Sequence(elements) => elements.is_empty()
          _ => true
        }
        let expression_code = generate(expression, {
          sp: context.sp + (if emit_call { 1 } else { 0 }),
          env,
          pluck: None,
          action: Some(node),
          report_failures: context.report_failures,
        })
        let match_ = match_of(expression)
        let function_index = if emit_call && match_ >= 0 {
          add_function_const(false, env.keys(), code)
        } else {
          -1
        }
        if !emit_call {
          expression_code
        } else {
          [
            op.push_curr_pos,
            ..expression_code,
            ..build_condition(
              match_,
              [op.if_not_error],
              [
                op.load_saved_pos,
                1,
                ..build_call(function_index, 1, env, context.sp + 2),
              ],
              [],
            ),
            op.nip,
          ]
        }
      }
      Sequence(elements) => {
        let total = elements.length()
        fn build_elements(
          elements : ArrayView[@ast.Node],
          context : BytecodeContext,
        ) -> Array[Int] {
          if elements.length() > 0 {
            let processed_count = total - elements[1:].length()
            let first = generate(elements[0], {
              sp: context.sp,
              env: context.env,
              pluck: context.pluck,
              action: None,
              report_failures: context.report_failures,
            })
            return [
              ..first,
              ..build_condition(
                match_of(elements[0]),
                [op.if_not_error],
                build_elements(elements[1:], {
                  sp: context.sp + 1,
                  env: context.env,
                  pluck: context.pluck,
                  action: context.action,
                  report_failures: context.report_failures,
                }),
                [
                  ..if processed_count > 1 {
                    [op.pop_n, processed_count]
                  } else {
                    [op.pop]
                  },
                  op.pop_curr_pos,
                  op.push_failed,
                ],
              ),
            ]
          }
          let pluck = context.pluck.unwrap()
          if pluck.length() > 0 {
            return [
              op.pluck,
              total + 1,
              pluck.length(),
              ..pluck.map(e_sp => context.sp - e_sp),
            ]
          }
          if context.action is Some(action) {
            guard action.kind is Action(_, code~) else {
              abort("sequence action context must be an action node")
            }
            return [
              op.load_saved_pos,
              total,
              ..build_call(
                add_function_const(false, context.env.keys(), code),
                total + 1,
                context.env,
                context.sp,
              ),
            ]
          }
          [op.wrap, total, op.nip]
        }

        [
          op.push_curr_pos,
          ..build_elements(elements[:], {
            sp: context.sp + 1,
            env: context.env,
            pluck: Some([]),
            action: context.action,
            report_failures: context.report_failures,
          }),
        ]
      }
      Labeled(expression, label~, pick~) => {
        let mut env = context.env
        let sp = context.sp + 1
        if label is Some(label) {
          env = context.env.clone()
          context.env.set(label, sp)
        }
        if context.pluck is Some(pluck) && pick {
          pluck.push(sp)
        }
        generate(expression, {
          sp: context.sp,
          env,
          pluck: None,
          action: None,
          report_failures: context.report_failures,
        })
      }
      Text(expression) =>
        [
          op.push_curr_pos,
          ..generate(expression, {
            sp: context.sp + 1,
            env: context.env.clone(),
            pluck: None,
            action: None,
            report_failures: context.report_failures,
          }),
          ..build_condition(
            match_of(expression),
            [op.if_not_error],
            [op.pop, op.text],
            [op.nip],
          ),
        ]
      SimpleAnd(expression) =>
        build_simple_predicate(expression, false, context)
      SimpleNot(expression) => build_simple_predicate(expression, true, context)
      Optional(expression) =>
        [
          ..generate(expression, {
            sp: context.sp,
            env: context.env.clone(),
            pluck: None,
            action: None,
            report_failures: context.report_failures,
          }),
          ..build_condition(
            -match_of(expression),
            [op.if_error],
            [op.pop, op.push_null],
            [],
          ),
        ]
      ZeroOrMore(expression) => {
        let expression_code = generate(expression, {
          sp: context.sp + 1,
          env: context.env.clone(),
          pluck: None,
          action: None,
          report_failures: context.report_failures,
        })
        [
          op.push_empty_array,
          ..expression_code,
          ..build_loop([op.while_not_error], [op.append, ..expression_code]),
          op.pop,
        ]
      }
      OneOrMore(expression) => {
        let expression_code = generate(expression, {
          sp: context.sp + 1,
          env: context.env.clone(),
          pluck: None,
          action: None,
          report_failures: context.report_failures,
        })
        [
          op.push_empty_array,
          ..expression_code,
          ..build_condition(
            match_of(expression),
            [op.if_not_error],
            [
              ..build_loop([op.while_not_error], [op.append, ..expression_code]),
              op.pop,
            ],
            [op.pop, op.pop, op.push_failed],
          ),
        ]
      }
      Group(expression) =>
        generate(expression, {
          sp: context.sp,
          env: context.env.clone(),
          pluck: None,
          action: None,
          report_failures: context.report_failures,
        })
      SemanticAnd(code~) => build_semantic_predicate(node, code, false, context)
      SemanticNot(code~) => build_semantic_predicate(node, code, true, context)
      RuleRef(name~) => [op.rule, grammar.index_of_rule(name)]
      Literal(value~, ignore_case~) =>
        if value != "" {
          let match_ = match_of(node)
          let need_const = match_ == 0 || (match_ > 0 && !ignore_case)
          let string_index = if need_const {
            add_const(
              tables.literals,
              if ignore_case {
                @runtime.js_to_lower(value)
              } else {
                value
              },
            )
          } else {
            -1
          }
          let expect_code = if context.report_failures {
            [
              op.expect,
              add_const(tables.expectations, Literal(text=value, ignore_case~)),
            ]
          } else {
            []
          }
          [
            ..expect_code,
            ..build_condition(
              match_,
              if ignore_case {
                [op.match_string_ic, string_index]
              } else {
                [op.match_string, string_index]
              },
              if ignore_case {
                [op.accept_n, value.length()]
              } else {
                [op.accept_string, string_index]
              },
              [op.push_failed],
            ),
          ]
        } else {
          [op.push_empty_string]
        }
      Class(parts~, inverted~, ignore_case~) => {
        let match_ = match_of(node)
        let class_index = if match_ == 0 {
          add_const(tables.classes, { parts, inverted, ignore_case, })
        } else {
          -1
        }
        let expect_code = if context.report_failures {
          [
            op.expect,
            add_const(
              tables.expectations,
              Class(parts~, inverted~, ignore_case~),
            ),
          ]
        } else {
          []
        }
        [
          ..expect_code,
          ..build_condition(
            match_,
            [op.match_class, class_index],
            [op.accept_n, 1],
            [op.push_failed],
          ),
        ]
      }
      Any => {
        let expect_code = if context.report_failures {
          [op.expect, add_const(tables.expectations, Any)]
        } else {
          []
        }
        [
          ..expect_code,
          ..build_condition(match_of(node), [op.match_any], [op.accept_n, 1], [
            op.push_failed,
          ]),
        ]
      }
    }
  }

  for rule in grammar.rules {
    rule.bytecode = Some(
      generate(rule.expression, {
        sp: -1,
        env: JsDict::new(),
        pluck: None,
        action: None,
        report_failures: rule.report_failures.unwrap_or(false),
      }),
    )
  }
  grammar.literals = Some(tables.literals)
  grammar.classes = Some(tables.classes)
  grammar.expectations = Some(tables.expectations)
  grammar.functions = Some(tables.functions)
}
