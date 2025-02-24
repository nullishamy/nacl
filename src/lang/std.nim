import ./runtime
import ./parse
import std/asyncdispatch
import std/tables
import std/typeinfo
import std/strformat
import std/strutils

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


proc globalFilter(): Value =
  proc impl_filter(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    # (filter <list> <predicate>)
    let lst = args[0].asList
    let predicate = args[1].asFunc

    var outValues: seq[Value] = @[]
    for value in lst.values:
      let decision = await predicate.fn(@[value], ctx)
      if not decision.isNil:
        outValues.add(value)

    outValues.lList

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_filter, name: "filter"))

proc globalNth(): Value =
  proc impl_nth(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    # (nth <index> <list>)
    let idx = args[0].asNumeric
    let lst = args[1].asList

    lst.values[idx.num]

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_nth, name: "nth"))

proc globalStrContains(): Value =
  proc impl_strcontains(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    # (str/contains haystack needle)
    let haystack = args[0].asString
    let needle = args[1].asString

    if needle.str in haystack.str:
      return 1.lNumeric
    else:
      return L_nil

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_strcontains, name: "str/contains"))

proc globalStrJoin(): Value =
  proc impl_strjoin(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    # (str/join s1 s2 3)
    var joined = ""
    for val in args:
      case val.kind:
      of vkString:
        joined &= val.str.str
      else:
        continue

    joined.lString

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_strjoin, name: "str/join"))


proc globalStrStrip(): Value =
  proc impl_strstrip(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    # (str/strip str)
    args[0].asString.str.strip().lString

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_strstrip, name: "str/strip"))

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
    "q": Value(kind: vkString, str: StringValue(str: "\"")),
    "list": globalList(),
    "l": globalList(),
    "nil": L_nil,
    "ack": globalAck(),
    "map": globalMap(),
    "filter": globalFilter(),
    "nth": globalNth(),
    "str/contains": globalStrContains(),
    "str/join": globalStrJoin(),
    "str/strip": globalStrStrip()
  }.toTable

  let env = Environment(values: values)
  var ctx = 0
  
  discard waitFor interpretTree(env, stdCl, toAny(ctx))
  
  env
