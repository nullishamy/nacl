import std/net
import std/strformat
import std/strutils
import argparse
import ./log
import ./print
import ./lang/std
import ./lang/runtime
import ./lang/parse
import ./util
import std/tables
import std/asyncdispatch
import std/asyncnet
import std/typeinfo
import system
import system/exceptions
import std/sugar

type
  Tracker = object
    taskId: int
    jobId: int
    
  Task = ref object
    id: int

    jobsFinished: int
    jobsRunning: int
    completionSent: bool
    
    jobId: int
    requests: seq[string]

  Config = ref object
    port: int
    
  Server = ref object
    config: Config
    
    sock: AsyncSocket
    env: Environment
    acceptFut: Future[ClientHandle]
    clients: seq[ClientHandle]
    tasks: seq[Task]
    running: bool
    clientId: int
    taskId: int

  ClientType = enum
    ctAgent, ctCli, ctUnknown
    
  ClientHandle = ref object
    id: int
    name: string
    ty: ClientType
    sock: AsyncSocket
    clientAddr: string
    fut: Future[void]
    targetList: seq[int]
    trackingTasks: seq[Task]
    clientIdForLogs: int
    
proc `$`(self: Config): string =
  "(port: {self.port})".fmt
  
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
  
  let port = map["port"].asNumeric

  if port == nil:
    raise newTypeError("expected numeric for port".fmt)

  Config(port: port.num)

# Stored as a global so all futures can share it
# Needed so we can mutate e.g acceptFut from the other future
var server: Server

proc newTracker(taskId: int, jobId: int): Tracker =
  Tracker(taskId: taskId, jobId: jobId)

proc parseTracker(input: string): Tracker =
  let parts = input.split('/')
  if parts.len != 2:
    raise newTypeError("invalid tracker length")

  let taskId = parseInt(parts[0])
  let jobId = parseInt(parts[1])
  
  Tracker(taskId: taskId, jobId: jobId)

proc sendLog(client: ClientHandle, log: string) {.async.} =
  if client.clientIdForLogs == 0:
    logger.debug("No log client for {client.id}".fmt)
    return

  let loggerClients = server.clients.filter(x => x.id == client.clientIdForLogs)
  if loggerClients.len == 0:
    logger.warn("Could not locate log client for {client.id} even though it should exist (set as {client.clientIdForLogs})".fmt)
    return

  let loggerClient = loggerClients[0]
  await loggerClient.sock.send(log.lenPrefixed)
  logger.debug("Sent log '{log}' to {client.clientIdForLogs}".fmt)
  
proc recvMessage(client: ClientHandle): Future[string] {.async.} =
  let sizeRaw = await client.sock.recv(4)
  if sizeRaw == "":
    return ""

  let size = parseInt(sizeRaw)
  await client.sock.recv(size)    

proc complete(task: Task): bool =
  task.jobsRunning == task.jobsFinished

proc `==`(self: ClientHandle, other: ClientHandle): bool =
  self.id == other.id
  
proc cmdClose(): Value =
  proc impl_cmdClose(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    server.running = false
    # Force the server to stop trying to listen to new connections
    server.acceptFut.fail(new IOError)
    Value(kind: vkNil)
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdClose, name: "close"))

proc cmdHello(): Value =
  proc impl_cmdHello(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    let clientId = ctx.getInt
    var clientHandles = server.clients.filter(c => c.id == clientId)
    if clientHandles.len == 0:
      logger.error("Client {clientId} was not found".fmt)
      return L_nil

    var clientHandle = clientHandles[0]
    logger.info("Client {clientId} says hello".fmt)

    let meta = args[0].asList
    if meta == nil:
      raise newTypeError("Expected list got {args[0].toString}".fmt)
      
    let nameObj = meta.values[0].asString
    let tyObj = meta.values[1].asNumeric
    if nameObj == nil or tyObj == nil:
      raise newTypeError("name or ty was nil")
      
    let name = nameObj.str
    let ty = tyObj.num

    let clientType = case ty
                     of ord(ctAgent): ctAgent
                     of ord(ctCli): ctCli
                     else: ctUnknown
    clientHandle.ty = clientType
    clientHandle.name = name
    logger.info("Client {clientId} self identifies as {clientType}".fmt)

    clientHandle.id.lNumeric

  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdHello, name: "hello"))
  
proc cmdStatus(): Value =
  proc impl_cmdStatus(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    @[server.clients.len.intToStr.lString].lList

  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdStatus, name: "status"))

proc cmdExec(): Value =
  proc impl_cmdExec(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    let clientId = ctx.getInt
    var clientHandles = server.clients.filter(c => c.id == clientId)
    if clientHandles.len == 0:
      logger.error("Client {clientId} was not found".fmt)
      return L_nil

    var clientHandle = clientHandles[0]
    
    let name = args[0].asString
    if name == nil:
      raise newTypeError("expected string")

    let cmdArgs = args[1].asList
    if cmdArgs == nil:
      raise newTypeError("expected list")
    
    let cmd = name.str
    var builtArgs = @["list".lIdent]

    for a in cmdArgs.values:
      case a.kind:
      of vkString:
        builtArgs.add(a.str.str.lByteArray)
      else:
        continue

    let taskId = server.taskId
    server.taskId.inc
    var task = Task(id: taskId)

    clientHandle.trackingTasks.add(task)
    await clientHandle.sendLog("! starting new task {task.id} !".fmt)

    for client in server.clients:
      if not clientHandle.targetList.contains(client.id):
        continue
        
      case client.ty:
      of ctAgent:
        task.jobsRunning.inc
        
        let jobId = task.jobId
        task.jobId.inc
        let tracker = "{task.id}/{jobId}".fmt
        task.requests.add("running")

        await clientHandle.sendLog(" => spinning up job {jobId} on {client.name}".fmt)
            
        let msg = @[
          "exec".lIdent,
          tracker.lString,
          cmd.lByteArray,
          builtArgs.lList
        ].lList.toString.lenPrefixed
        
        await client.sock.send(msg)
      else:
        continue
        
    server.tasks.add(task)

    "{taskId}".fmt.lString
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdExec, name: "exec"))

proc cmdResponse(): Value =
  proc impl_cmdReponse(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    let tracker = args[0].asString.str.parseTracker
    let output = args[1].asStringFromBytes.str

    var task = server.tasks.filter(x => (x.id == tracker.taskId))[0]

    task.requests[tracker.jobId] = output
    task.jobsFinished.inc

    let clientsInterested = server.clients.filter(x => x.trackingTasks.contains(task))
    for client in clientsInterested:
      var log = ""
      log = log & " > job {tracker.jobId} finished in task {tracker.taskId}\n".fmt
      
      for line in output.strip.splitLines:
        log = log & (" $ " & line & "\n")
        
      if task.complete and not task.completionSent:
        task.completionSent = true
        log = log & "== task {task.id} complete! ==\n\n".fmt
        
      await client.sendLog(log)
    
    # Indicate that we don't want to send anything back to the client
    # This is the response handler for the request we already sent
    # So any further messages to the client would be treated as a new request
    return nil
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdReponse, name: "reponse"))

proc cmdWaitFor(): Value =
  proc impl_cmdWaitFor(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    if args.len == 0:
      return L_nil

    if args[0].isNil:
      return L_nil

    let taskId = parseInt(args[0].asString.str)
    var task = server.tasks.filter(x => (x.id == taskId))[0]
    
    while not task.complete:
      # 2.5s
      await sleepAsync(2500)

    return task.requests.map(x => x.lString).lList
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdWaitFor, name: "waitfor"))

proc cmdNodes(): Value =
  proc impl_cmdNodes(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    let nodes = server.clients.filter(x => x.ty == ctAgent)
    let mapped = nodes.map(x => @[x.id.lNumeric, x.name.lString].lList)
    mapped.lList
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdNodes, name: "server/nodes"))


proc cmdClearTargets(): Value =
  proc impl_clearTargets(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    let clientId = ctx.getInt
    var clientHandles = server.clients.filter(c => c.id == clientId)
    if clientHandles.len == 0:
      logger.error("Client {clientId} was not found".fmt)
      return L_nil

    var clientHandle = clientHandles[0]
    clientHandle.targetList = @[]
    L_nil
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_clearTargets, name: "targets/clear"))

proc cmdAddTarget(): Value =
  proc impl_addTarget(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    let clientId = ctx.getInt
    var clientHandles = server.clients.filter(c => c.id == clientId)
    if clientHandles.len == 0:
      logger.error("Client {clientId} was not found".fmt)
      return L_nil

    var clientHandle = clientHandles[0]

    let targetId = args[0].asNumeric.num
    clientHandle.targetList.add(targetId)
    
    targetId.lNumeric
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_addTarget, name: "targets/add"))

proc cmdEnableLogging(): Value =
  proc impl_enableLogging(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    let targetId = args[0].asNumeric.num
    let clientId = ctx.getInt
    
    var clientHandles = server.clients.filter(c => c.id == targetId)
    if clientHandles.len == 0:
      logger.error("Client {clientId} was not found".fmt)
      return L_nil

    var clientHandle = clientHandles[0]
    clientHandle.clientIdForLogs = clientId
    logger.info("Client {clientId} is now tracking logs for {targetId}".fmt)

    # Log only clients don't care about interpreting lisp
    nil
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_enableLogging, name: "enable-logging"))
  
proc initEnv() =
  let values = {
    "close": cmdClose(),
    "hello": cmdHello(),
    "status": cmdStatus(),
    "exec": cmdExec(),
    "response": cmdResponse(),
    "waitfor": cmdWaitFor(),
    "server/nodes": cmdNodes(),
    "targets/clear": cmdClearTargets(),
    "targets/add": cmdAddTarget(),
    "enable-logging": cmdEnableLogging()
  }.toTable

  # Patches an issue where shaker defined variables couldn't be read by the global scope
  # So, invert the scopes. This makes the server env the stdenv, and the stdenv a parent of that.
  # This means every `set` call by shakers (ie set server.env) is actually impacting the stdenv()
  # Which the std.cl funcs are defined in
  # FIXME: We should devise something better for this (some kind of module level env with setters?)
  server.env = stdenv()
  server.env.parent = Environment(parent: nil, values: values)

proc newServer(config: Config): Server =
  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(config.port))
  server.listen()
  
  Server(sock: server, env: Environment(), running: true, clientId: 1)

proc waitForClient(): Future[ClientHandle] {.async.} = 
  let client = await server.sock.acceptAddr()
  server.clientId.inc
  ClientHandle(sock: client[1], clientAddr: client[0], id: server.clientId, ty: ctUnknown)

proc handleClient(client: ClientHandle) {.async.} =
  while true:
    let msg = await client.recvMessage
    # Socket closed
    if msg == "":
      logger.debug("Client disconnect {client.id}".fmt)
      server.clients.delete(server.clients.find(client))
      return

    logger.debug("Client sent us a message: '{msg}'".fmt)
    let command = parseSource msg
    logger.debug("Parsed the message: {command.dbg}".fmt)

    var ctx = client.id
    let res = await interpretTree(server.env, command, toAny(ctx))
    if res == nil:
      logger.debug("Interpreter signalled to not send anything to the client, complying")
      continue
      
    await client.sock.send(res.toString.lenPrefixed)
    await client.sendLog("<close>")

proc mainLoop() {.async.} =
  while server.running:
    logger.info("Waiting for client")

    let fut = waitForClient()
    server.acceptFut = fut

    var client: ClientHandle
    try:
      client = await server.acceptFut
    except:
      return

    logger.info("Client connected from {client.clientAddr}!".fmt)
    let clientFut = handleClient(client)
    asyncCheck clientFut

    client.fut = clientFut
    server.clients.add(client)

proc statusTask() {.async.} =
  # TODO: Make this a Task so it can have a proper req/res cycle
  while false:
    # Client checkup
    if server.clients.len > 0:
      logger.info("Checking in on {server.clients.len} clients".fmt)
    
    for client in server.clients:
      if client.ty != ctAgent:
        logger.debug("Skipping client {client.id} because it is type {client.ty}".fmt)
        continue
        
      let msg = @["status".lIdent].lList
      await client.sock.send(msg.toString.lenPrefixed)

      let res = await client.recvMessage
      logger.debug("Agent {client.id} status: {res}".fmt)
      
    # 10s
    await sleepAsync(10000)


proc runServer*(configPath: string) =
  let config = waitFor readConfig(configPath)
  
  server = newServer(config)
  initEnv()
  logger.info("Server up on 0.0.0.0:6969")
  asyncCheck statusTask()
  
  try:
    waitFor mainLoop()
  except:
    print getCurrentException()
  finally:
    logger.info("Closing server")
    for client in server.clients:
      # Wait 5 seconds for clients to finish, don't care if they can't
      # finish in time, we're closing!
      logger.info("Closing client {client.clientAddr}".fmt)
      discard waitFor client.fut.withTimeout(5_000)
      logger.info("Closed client {client.clientAddr}".fmt)
    quit(QuitSuccess)
    
