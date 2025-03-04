import std/typeinfo
import std/asyncdispatch
import std/tables
import std/sugar
import std/sequtils
import std/strutils
import std/strformat

type
  ValueKind* = enum
    vkList, vkString, vkSymbol, vkNil, vkFunc, vkNumeric

  LispFunc* = proc (args: seq[Value], ctx: Any): Future[Value]

  ListValue* = ref object
    quoted*: bool
    values*: seq[Value]
  StringValue* = ref object
    str*: string
  SymbolValue* = ref object
    symbol*: string
    quoted*: bool
  NumericValue* = ref object
    num*: int
  FuncValue* = ref object
    fn*: LispFunc
    name*: string
    
  Value* = ref object
    case kind*: ValueKind
    of vkList:
      list*: ListValue
    of vkString:
      str*: StringValue
    of vkSymbol:
      symbol*: SymbolValue
    of vkNumeric:
      num*: NumericValue
    of vkFunc:
      fn*: FuncValue
    of vkNil:
      discard

  Environment* = ref object
    parent*: Environment
    values*: Table[string, Value]

type
  RuntimeError* = object of CatchableError
  TypeError* = object of RuntimeError
  ReferenceError* = object of RuntimeError
  ConnectionError* = object of RuntimeError

proc newReferenceError*(cause: string): ref ReferenceError =
  var err = new ReferenceError
  err.msg = cause
  return err

proc newConnectionError*(cause: string): ref ConnectionError =
  var err = new ConnectionError
  err.msg = cause
  return err

proc newTypeError*(cause: string): ref TypeError =
  var err = new TypeError
  err.msg = cause
  return err
  
proc isNil*(self: Value): bool =
  if self == nil:
    return false
    
  case self.kind:
  of vkNil:
    true
  else:
    false

proc asList*(self: Value): ListValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkList:
    self.list
  else:
    nil

proc asNumeric*(self: Value): NumericValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkNumeric:
    self.num
  else:
    nil
    
proc toString(str: seq[char]): string =
  result = newStringOfCap(len(str))
  for ch in str:
    add(result, ch)
  
proc asStringFromBytes*(self: Value): StringValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkList:
    let bytes: seq[char] = self.list.values.map(x => char(x.asNumeric.num))
    StringValue(str: bytes.toString)
  else:
    nil
    
proc asString*(self: Value): StringValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkString:
    self.str
  else:
    nil

proc asSymbol*(self: Value): SymbolValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkSymbol:
    self.symbol
  else:
    nil

proc asFunc*(self: Value): FuncValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkFunc:
    self.fn
  else:
    nil
    
proc toString*(self: Value): string =
  case self.kind:
  of vkList:
    let items = self.list.values.map(i => i.toString).join " "
    var quote = ""
    if self.list.quoted:
      quote = "'"
    fmt"{quote}({items})"
  of vkString:
    # Using the double quote method causes nim to treat it as a multiline string
    # which removes the quote characters entirely, so do it the old fashioned way :^)
    '"' & self.str.str & '"'
  of vkSymbol:
    var quote = ""
    if self.symbol.quoted:
      quote = "'"
      
    fmt "{quote}{self.symbol.symbol}"
  of vkNumeric:
    intToStr(self.num.num)
  of vkFunc:
    "<func>"
  of vkNil:
    "nil"

proc get*(self: Environment, key: string): Value =
  if self.values.hasKey(key):
    return self.values[key]

  if self.parent != nil:
     return self.parent.get(key)
     
  return nil

proc set*(self: Environment, key: string, value: Value) =
  self.values[key] = value

proc lIdent*(self: string): Value =
  Value(kind: vkSymbol, symbol: SymbolValue(symbol: self, quoted: false))
  
proc lSymbol*(self: string): Value =
  Value(kind: vkSymbol, symbol: SymbolValue(symbol: self, quoted: true))

proc lString*(self: string): Value =
  Value(kind: vkString, str: StringValue(str: self))

proc lNumeric*(self: int): Value =
  Value(kind: vkNumeric, num: NumericValue(num: self))

proc lByteArray*(self: string): Value =
  var bytes = @[
    "list".lIdent
  ]

  for ch in self.items.toSeq:
    bytes.add(ord(ch).lNumeric)
  
  Value(kind: vkList, list: ListValue(values: bytes))

proc lList*(self: seq[Value]): Value =
  Value(kind: vkList, list: ListValue(values: self))

proc lListLit*(self: seq[Value]): Value =
  Value(kind: vkList, list: ListValue(values: self))
  
let L_nil* = Value(kind: vkNil)
