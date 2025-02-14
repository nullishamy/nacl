import std/net
import std/os
import std/osproc
import std/strformat
import std/strutils
import std/asyncdispatch
import std/asyncnet
import argparse
import std/tables
import std/typeinfo
import ./util
import ./print
import ./lang
import ./stdlib
import ./log

proc execCmd(): Value =
  proc impl_execCmd(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    # (exec "<tracker>" "cmd" (l "arg1" "arg2" "arg3")
    let tracker = args[0]
    let cmd = args[1].asString
    let cmdArgs = args[2].asList
    if cmd == nil:
      raise newTypeError("invalid command name {args[0].toString}".fmt)
    if cmdArgs == nil:
      raise newTypeError("invalid command args {args[1].toString}".fmt)
    
    var builtArgs = newSeq[string]()

    for arg in cmdArgs.values:
      let argStr = arg.asString
      if argStr == nil:
        raise newTypeError("invalid command arg {arg.toString}".fmt)
        
      builtArgs.add(arg.str.str)

    let argstr = builtArgs.join(" ")
    # var result = execCmdEx(&"{cmd.str} {argstr}")
    var result = @["ran {cmd.str} {argstr}".fmt]
    let escaped = result[0].replace('"'&"", '`'&'"')
    
    return @["response".lSymbol, tracker, escaped.lString].lList
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_execCmd))

proc recvMessage(socket: AsyncSocket, env: Environment): Future[Value] {.async.} =
  let size = await socket.recv(4)
  if size == "":
    # Disconnected
    raise newConnectionError("server closed")
    
  let source = await socket.recv(parseInt(size))
  let expr = parseSource(source)
  var ctx = 0
  await interpretTree(env, expr, toAny(ctx))

proc sendMessage(socket: AsyncSocket, msg: Value) {.async.} =
  await socket.send(msg.toString.lenPrefixed)

type
  Config = ref object
    host: string
    port: int

proc `$`(self: Config): string =
  "(host: {self.host}, port: {self.port})".fmt
  
proc readConfig(path: string): Future[Config] {.async.} =
  let content = readFile(path)
  let env = stdenv()
  var ctx = 0
  let expr = parseSource(content)
  let lsp = await interpretTree(env, expr, toAny(ctx))

  let pairs = lsp.asList
  if pairs == nil:
    raise newTypeError("expected list got {lsp.toString}".fmt)

  let map = pairs.values.mapFromPairs
  
  let host = map["host"].asString
  let port = map["port"].asNumeric

  if host == nil or port == nil:
    raise newTypeError("expected string, numeric for host, port".fmt)

  Config(host: host.str, port: port.num)
  
proc mainLoop {.async.} =
  let cfg = await readConfig("./agent.cl")
  logger.info("Agent starting up, config: {cfg}".fmt)
  let socket = newAsyncSocket()

  while true:
    try:
      await socket.connect(cfg.host, Port(cfg.port))
      logger.info("Connected to {cfg.host}:{cfg.port}!".fmt)
      break
    except OSError:
      logger.warn("Failed to connect to {cfg.host}:{cfg.port}, retry in 5s".fmt)
      sleep(5_000)

  let env = Environment(parent: stdenv(), values: {
    "exec": execCmd()
  }.toTable)

  logger.info("Saying hello to server...")
  await socket.sendMessage(@["hello".lSymbol, @[L, "agent".lString, 0.lNumeric].lList].lList)
  let helloRes = await socket.recvMessage(env)
  logger.info("Server said {helloRes.toString} to our hello".fmt)

  logger.info("Waiting for instructions")
  while true:
    let res = await socket.recvMessage(env)
    logger.debug("Execution: {res.toString}".fmt)
    await socket.sendMessage(res)
  
proc runAgent* =
  waitFor mainLoop()

