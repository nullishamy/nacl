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
  Task = object
    id: int
    requestId: int
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

proc recvMessage(client: ClientHandle): Future[string] {.async.} =
  let sizeRaw = await client.sock.recv(4)
  if sizeRaw == "":
    return ""

  let size = parseInt(sizeRaw)
  await client.sock.recv(size)    

proc `==`(self: ClientHandle, other: ClientHandle): bool =
  self.id == other.id
  
proc cmdClose(server: Server): Value =
  proc impl_cmdClose(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    server.running = false
    # Force the server to stop trying to listen to new connections
    server.acceptFut.fail(new IOError)
    Value(kind: vkNil)
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdClose))

proc cmdHello(server: Server): Value =
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

  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdHello))
  
proc cmdStatus(server: Server): Value =
  proc impl_cmdStatus(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    @[server.clients.len.intToStr.lString].lList

  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdStatus))

proc cmdExec(server: Server): Value =
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
        let requestId = task.requestId
        task.requestId.inc
        let tracker = "{task.id}/{requestId}".fmt
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
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdExec))

proc cmdResponse(server: Server): Value =
  proc impl_cmdReponse(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    print args, server.tasks
    # Indicate that we don't want to send anything back to the client
    # This is the response handler for the request we already sent
    # So any further messages to the client would be treated as a new request
    return nil
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdReponse))
  
proc initEnv(server: var Server) =
  let values = {
    "close": cmdClose(server),
    "hello": cmdHello(server),
    "status": cmdStatus(server),
    "exec": cmdExec(server),
    "response": cmdResponse(server)
  }.toTable

  server.env = Environment(parent: stdenv(), values: values)

proc newServer(port: Port): Server =
  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(port)
  server.listen()
  
  Server(sock: server, env: Environment(), running: true, clientId: 0)

proc waitForClient(server: Server): Future[ClientHandle] {.async.} = 
  let client = await server.sock.acceptAddr()
  server.clientId.inc
  ClientHandle(sock: client[1], clientAddr: client[0], id: server.clientId, ty: ctUnknown)

proc handleClient(server: Server, client: ClientHandle) {.async.} =
  while true:
    let msg = await client.recvMessage
    # Socket closed
    if msg == "":
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

proc mainLoop(server: Server) {.async.} =
  while server.running:
    logger.info("Waiting for client")

    let fut = server.waitForClient
    server.acceptFut = fut

    var client: ClientHandle
    try:
      client = await server.acceptFut
    except:
      return

    logger.info("Client connected from {client.clientAddr}!".fmt)
    let clientFut = handleClient(server, client)
    asyncCheck clientFut

    client.fut = clientFut
    server.clients.add(client)

# Stored as a global so all futures can share it
# Needed so we can mutate e.g acceptFut from the other future
var server: Server

proc runServer* =
  server = newServer(Port(6969))
  server.initEnv
  logger.info("Server up on 0.0.0.0:6969")
  
  try:
    waitFor mainLoop(server)
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
    
