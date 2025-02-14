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
    values*: seq[Value]
  StringValue* = ref object
    str*: string
  SymbolValue* = ref object
    symbol*: string
  NumericValue* = ref object
    num*: int
  FuncValue* = ref object
    fn*: LispFunc
    
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

proc asNumeric*(self: Value): NumericValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkNumeric:
    self.num
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
    fmt"({items})"
  of vkString:
    # Using the double quote method causes nim to treat it as a multiline string
    # which removes the quote characters entirely, so do it the old fashioned way :^)
    '"' & self.str.str & '"'
  of vkSymbol:
    # If we have a SymbolValue it will always be quoted. If it was unquoted in the source
    # it would have been used as a variable
    "'" & self.symbol.symbol
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

proc lSymbol*(self: string): Value =
  Value(kind: vkSymbol, symbol: SymbolValue(symbol: self))

proc lString*(self: string): Value =
  Value(kind: vkString, str: StringValue(str: self))

proc lNumeric*(self: int): Value =
  Value(kind: vkNumeric, num: NumericValue(num: self))

proc lList*(self: seq[Value]): Value =
  Value(kind: vkList, list: ListValue(values: self))

proc lListLit*(self: seq[Value]): Value =
  Value(kind: vkList, list: ListValue(values: self))

let L* = "l".lSymbol
let L_nil* = Value(kind: vkNil)

proc globalList(): Value =
  proc impl_list(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    Value(kind: vkList, list: ListValue(values: args))

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_list))

proc globalAck(): Value =
  proc impl_ack(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    Value(kind: vkNil)

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_ack))

proc mapFromPairs*(p: seq[Value]): Table[string, Value] =
  for pair in p:
    let pairValues = pair.asList
    if pairValues == nil or pairValues.values.len != 2:
      raise newTypeError("expected tuple of 2 values got {pair.toString}".fmt)

    let key = pairValues.values[0].asSymbol
    if key == nil:
      raise newTypeError("expected key to be symbol, got {pairValues.values[0].toString}".fmt)
      
    result[key.symbol] = pairValues.values[1]

proc stdenv*(): Environment =
  let values = {
    "list": globalList(),
    "l": globalList(),
    "nil": L_nil,
    "ack": globalAck()
  }.toTable

  Environment(values: values)
