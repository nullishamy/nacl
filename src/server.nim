import std/net
import std/strformat
import std/strutils
import argparse
import ./log
import ./stdlib
import ./print
import ./lang
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
    
    jobId: int
    requests: seq[string]
    
  Server = ref object
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
    ty: ClientType
    sock: AsyncSocket
    clientAddr: string
    fut: Future[void]

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
      raise newTypeError("Expected list got {args[0].toString}")
      
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
    logger.info("Client {clientId} self identifies as {clientType}".fmt)

    @[L, @[L, "state".lString, "ok".lString].lList, @[L, "msg".lString, "ack".lString].lList].lList

  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdHello, name: "hello"))
  
proc cmdStatus(): Value =
  proc impl_cmdStatus(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    @[server.clients.len.intToStr.lString].lList

  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdStatus, name: "status"))

proc cmdExec(): Value =
  proc impl_cmdExec(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    let name = args[0].asString
    if name == nil:
      raise newTypeError("expected string")

    let cmdArgs = args[1].asList
    if cmdArgs == nil:
      raise newTypeError("expected list")
    
    let cmd = name.str
    var builtArgs = @[L]

    for a in cmdArgs.values:
        builtArgs.add(a)

    let taskId = server.taskId
    server.taskId.inc
    var task = Task(id: taskId)
    
    for client in server.clients:
      case client.ty:
      of ctAgent:
        task.jobsRunning.inc
        
        let jobId = task.jobId
        task.jobId.inc
        let tracker = "{task.id}/{jobId}".fmt
        task.requests.add("running")
            
        let msg = @[
          "exec".lSymbol,
          tracker.lString,
          cmd.lString,
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
    let output = args[1].asString.str

    var task = server.tasks.filter(x => (x.id == tracker.taskId))[0]

    task.requests[tracker.jobId] = output
    task.jobsFinished.inc
    
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
  
proc initEnv() =
  let values = {
    "close": cmdClose(),
    "hello": cmdHello(),
    "status": cmdStatus(),
    "exec": cmdExec(),
    "response": cmdResponse(),
    "waitfor": cmdWaitFor()
  }.toTable

  server.env = Environment(parent: stdenv(), values: values)

proc newServer(port: Port): Server =
  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(port)
  server.listen()
  
  Server(sock: server, env: Environment(), running: true, clientId: 0)

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
        
      let msg = @[stubbed("status")].lList
      await client.sock.send(msg.toString.lenPrefixed)

      let res = await client.recvMessage
      logger.debug("Agent {client.id} status: {res}".fmt)
      
    # 10s
    await sleepAsync(10000)


proc runServer* =
  server = newServer(Port(6969))
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
    
