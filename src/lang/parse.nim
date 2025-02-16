import std/sequtils
import std/strformat
import std/strutils
import std/asyncdispatch
import std/typeinfo
import std/tables
import ../print
import ./runtime
import std/sugar

type
  ExprType* = enum
    exSymbol, exStr, exList, exNumeric, exSourceFile
  
  Expr* = ref object
    case kind*: ExprType
    of exSourceFile:
      lists: seq[Expr]
    of exSymbol:
      symbol*: string
      quoted*: bool
    of exStr:
      sValue*: string
    of exNumeric:
      num*: int
    of exList:
      lValues*: seq[Expr]

  TokenType = enum
    tkListStart, tkSymbol, tkStr, tkListEnd, tkNumeric

  Token = object
    quoted*: bool
    case kind*: TokenType
    of tkListStart, tkListEnd:
      discard
    of tkSymbol:
      symbol: string
    of tkStr:
      str: string
    of tkNumeric:
      num: int

proc toString*(self: Expr): string =
  case self.kind:
  of exSymbol:
    var quote = ""
    if self.quoted:
      quote = "'"
    fmt "{quote}{self.symbol}"
  of exStr:
    fmt "\"{self.sValue}\""
  of exNumeric:
    fmt "{self.num}"
  of exList:
    let s = self.lValues.map(proc(x: Expr): string = $x.toString).join(" ")
    fmt "({s})"
  of exSourceFile:
    self.lists.map(proc(x: Expr): string = $x.toString).join("\n")
    
proc dbg*(self: Expr): string  =
  case self.kind:
  of exSymbol:
    var quote = ""
    if self.quoted:
      quote = "'"
    fmt "Symbol({quote}{self.symbol})"
  of exStr:
    fmt "Str({self.sValue})"
  of exNumeric:
    fmt "Num({self.num})"
  of exList:
    let s = self.lValues.map(proc(x: Expr): string = $x.dbg).join(", ")
    fmt "List({s})"
  of exSourceFile:
    self.lists.map(proc(x: Expr): string = $x.dbg).join("\n")

func lex(source: string): seq[Token] =
  var toks = newSeq[Token]()
  var i = 0
  var quoted = false
  
  while i < source.len:
    var ch = source[i]
    
    if ch == '(':
      toks.add(Token(kind: tkListStart, quoted: quoted))
      quoted = false
    elif ch == ')':
      toks.add(Token(kind: tkListEnd))
    elif ch == '\'':
      quoted = true
    elif ch.isDigit:
      # Starts with number = numeric, taking priority over idents below
      var numeric = ""

      while i < source.len and ch.isDigit:
        numeric.add(ch)
        i.inc
        ch = source[i]

      # Since we'll have gone 1 over in our loop
      i.dec
      toks.add(Token(kind: tkNumeric, num: parseInt(numeric), quoted: quoted))
      quoted = false
    elif ch.isAlphaNumeric:
      var symbol = ""

      # Symbols can be [a-zA-Z0-9/-]
      while i < source.len and (ch.isAlphaNumeric or ch == '-' or ch == '/'):
        symbol.add(ch)
        i.inc
        ch = source[i]

      # Since we'll have gone 1 over in our loop
      i.dec
      toks.add(Token(kind: tkSymbol, symbol: symbol, quoted: quoted))
      quoted = false
    elif ch == '"':
      var lit = ""

      # Consume quote
      i.inc
      ch = source[i]
      
      while i < source.len and ch != '"':
        if ch == '`':
          i.inc
          i.inc
          ch = source[i]
          lit.add('"'&"")
          continue
          
        lit.add(ch)
        i.inc
        ch = source[i]

      toks.add(Token(kind: tkStr, str: lit, quoted: quoted))
      quoted = false
    elif ch == ';':
      # Comments
      while i < source.len and ch != '\n':
        i.inc
        ch = source[i]
    i.inc

  toks

func pop(toks: var seq[Token]): Token =
  let val = toks[0]
  toks.delete(0)
  return val

type MacroExpander = proc (expr: Expr): Expr
                       
# (plan "name" (
#  (exec "apt" '("update"))
#  (apt 'install ("git" "curl"))))
proc macroPlan(): MacroExpander =
  proc plan_impl(expr: Expr): Expr =
    case expr.kind:
    of exList:
      let args = expr.lValues

      let planName = args[1]
      var name = ""
      case planName.kind:
      of exStr:
        name = planName.sValue
      else:
        raise newTypeError("invalid plan name")

      # list of lists
      # (list (waitfor <step>) (waitfor <step>))
      let stepsRaw = args[2]
      var steps = @[
        Expr(kind: exSymbol, symbol: "list", quoted: false),
        Expr(kind: exStr, sValue: "plan '{name}' finished".fmt)
      ]

      case stepsRaw.kind:
      of exList:
        for step in stepsRaw.lValues:
          steps.add(
            Expr(kind: exList, lValues: @[
              Expr(kind: exSymbol, symbol: "waitfor", quoted: false),
              step
            ])
          )
        
        return Expr(kind: exList, lValues: steps)
      else:
        raise newTypeError("invalid packages")
    else:
      raise newTypeError("invalid func")
             
  plan_impl
  
proc parse(toks: var seq[Token], macros: Table[string, MacroExpander]): Expr =
  var current = toks.pop()
  if current.kind == tkListStart:
    var children = newSeq[Expr]()
    if current.quoted:
      children.add(Expr(kind: exSymbol, symbol: "list", quoted: false))
      
    var next = toks.parse(macros)
    while next != nil:
      children.add(next)
      next = toks.parse(macros)

    let happy = Expr(kind: exList, lValues: children)
    if children.len == 0:
      return happy
    
    let first = children[0]
    case first.kind:
    of exSymbol:
      let sym = first.symbol
      if not macros.hasKey(sym):
        return happy

      let expander = macros[sym]
      return expander(happy)
    else:
      return happy
  elif current.kind == tkSymbol:
    return Expr(kind: exSymbol, symbol: current.symbol, quoted: current.quoted)
  elif current.kind == tkStr:
    return Expr(kind: exStr, sValue: current.str)
  elif current.kind == tkNumeric:
    return Expr(kind: exNumeric, num: current.num)
  elif current.kind == tkListEnd:
    return nil
  else:
    print "unrecognised tok", current

  return nil

proc parseSource*(source: string): Expr =
  let macros = {
    "plan": macroPlan()
  }.toTable
    
  var toks = source.lex
  var lists = newSeq[Expr]()
  while toks.len > 0:
    lists.add(toks.parse(macros))

  return Expr(kind: exSourceFile, lists: lists)

proc asList*(self: Expr): seq[Expr] =
  if self == nil:
    return @[]
    
  case self.kind:
  of exList:
    self.lValues
  else:
    return @[]

proc asString*(self: Expr): string =
  if self == nil:
    return ""
    
  case self.kind:
  of exStr:
    self.sValue
  else:
    ""

proc asSymbol*(self: Expr): string =
  if self == nil:
    return ""
    
  case self.kind:
  of exSymbol:
    self.symbol
  else:
    ""

proc asNumeric*(self: Expr): int =
  if self == nil:
    return 0
    
  case self.kind:
  of exNumeric:
    self.num
  else:
    0
  
proc interpretTree*(env: Environment, base: Expr, ctx: Any): Future[Value] {.async.} =
  proc defunWrapper(env: Environment, name: string, idents: seq[string], body: Expr): Value =
    proc inner(args: seq[Value], ctx: Any): Future[Value] {.async.} =
      if args.len != idents.len:
        raise newTypeError("expected {idents.len} args got {args.len}".fmt)

      var argMap = initTable[string, Value]()
      var i = 0
      for ident in idents:
        argMap[ident] = args[i]
        i.inc
        
      let innerEnv = Environment(parent: env, values: argMap)
      await interpretTree(innerEnv, body, ctx)
        
    Value(kind: vkFunc, fn: FuncValue(fn: inner, name: name))

  case base.kind:
  of exSourceFile:
    var lastRes = L_nil
    for list in base.lists:
      lastRes = await interpretTree(env, list, ctx)
    return lastRes
  of exSymbol:
    if base.quoted:
      return Value(kind: vkSymbol, symbol: SymbolValue(symbol: base.symbol, quoted: true))
      
    let fromEnv = env.get(base.symbol)
    if fromEnv == nil:
      raise newReferenceError("unknown symbol {base.symbol}".fmt)
    return fromEnv
  of exStr:
    return Value(kind: vkString, str: StringValue(str: base.sValue))
  of exNumeric:
    return Value(kind: vkNumeric, num: NumericValue(num: base.num))
  of exList:
    let vals = base.lValues
    if vals.len == 0:
      return Value(kind: vkList, list: ListValue())

    let funcSymbol = vals[0]
    case funcSymbol.kind:
    of exSymbol:
      if funcSymbol.quoted:
        raise newTypeError("cannot use quoted symbol for func ident")
        
      case funcSymbol.symbol:
      of "defun":
        # (defun name (args) (body))
        let name = vals[1].asSymbol
        let args = vals[2].asList.map(x => x.asSymbol)
        let body = vals[3..^1]

        env.set(name, defunWrapper(env, name, args, Expr(kind: exSourceFile, lists: body)))
      of "if":
        # (if (cond) (when-true) (when-false)?)
        let cond = vals[1]
        let whenTrue = vals[2]

        let isTrue = await interpretTree(env, cond, ctx)
        if not isTrue.isNil:
          return await interpretTree(env, whenTrue, ctx)
        else:
          if vals.len <= 3:
            return L_nil
            
          let whenFalse = vals[3]
          if not whenFalse.isNil:
            return await interpretTree(env, whenFalse, ctx)
          else:
            return L_nil
      of "set":
        # (set name value)
        let sym = interpretTree(env, vals[1], ctx).await.asSymbol
        if sym == nil:
          return L_nil


        let val = await interpretTree(env, vals[2], ctx)
        env.set(sym.symbol, val)
      else:
        let fn = env.get(funcSymbol.symbol).asFunc
        if fn == nil:
          print env
          raise newReferenceError("unknown function {funcSymbol.symbol}".fmt)

        var callArgs = newSeq[Value]()
        for val in vals[1..^1]:
          callArgs.add(await interpretTree(env, val, ctx))
        return await fn.fn(callArgs, ctx)
    else:
      raise newTypeError("invalid value for function call {funcSymbol.kind} {funcSymbol.dbg}".fmt)
