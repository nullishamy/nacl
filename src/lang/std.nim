import ./runtime
import ./parse
import std/asyncdispatch
import std/tables
import std/typeinfo
import std/strformat

proc globalList(): Value =
  proc impl_list(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    Value(kind: vkList, list: ListValue(values: args))

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_list, name: "list"))

proc globalAck(): Value =
  proc impl_ack(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    Value(kind: vkNil)

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_ack, name: "ack"))

proc globalMap(): Value =
  proc impl_map(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    # (map <list> <mapper>)
    let lst = args[0].asList
    let mapper = args[1].asFunc

    var outValues: seq[Value] = @[]
    for value in lst.values:
      outValues.add(await mapper.fn(@[value], ctx))

    outValues.lList

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_map, name: "map"))

proc mapFromPairs*(p: seq[Value]): Table[string, Value] =
  for pair in p:
    let pairValues = pair.asList
    if pairValues == nil or pairValues.values.len != 2:
      raise newTypeError("expected tuple of 2 values got {pair.toString}".fmt)

    let key = pairValues.values[0].asSymbol
    if key == nil:
      raise newTypeError("expected key to be symbol, got {pairValues.values[0].toString}".fmt)
      
    result[key.symbol] = pairValues.values[1]


const stdClSrc = staticRead("./std.cl")
let stdCl = stdClSrc.parseSource

proc stdenv*(): Environment =
  let values = {
    "list": globalList(),
    "l": globalList(),
    "nil": L_nil,
    "ack": globalAck(),
    "map": globalMap()
  }.toTable

  let env = Environment(values: values)
  var ctx = 0
  
  discard waitFor interpretTree(env, stdCl, toAny(ctx))
  
  env
