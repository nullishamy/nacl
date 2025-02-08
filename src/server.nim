import std/net
import std/strformat
import std/strutils
import argparse
import ./print
import ./lang
import ./util
import std/tables
import std/asyncdispatch
import std/asyncnet
import system
import system/exceptions

type
  Server = ref object
    sock: AsyncSocket
    env: Environment
    acceptFut: Future[ClientHandle]
    clients: seq[ClientHandle]
    running: bool
    clientId: int
    
  ClientHandle = object
    id: int
    sock: AsyncSocket
    clientAddr: string
    fut: Future[void]

proc recvMessage(client: ClientHandle): Future[string] {.async.} =
  let sizeRaw = await client.sock.recv(4)
  if sizeRaw == "":
    return ""

  let size = parseInt(sizeRaw)
  print size
  await client.sock.recv(size)    

proc `==`(self: ClientHandle, other: ClientHandle): bool =
  self.id == other.id
  
proc cmdClose(server: Server): Value =
  proc impl_cmdClose(args: seq[Value]): Future[Value] {.async.} =
    server.running = false
    # Force the server to stop trying to listen to new connections
    server.acceptFut.fail(new IOError)
    Value(kind: vkNil)
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdClose))

proc cmdHello(server: Server): Value =
  proc impl_cmdHello(args: seq[Value]): Future[Value] {.async.} =
    # Nothing more to it at the moment, just acknowledge we got the connection
    # and are ready to communicate
    let name = args[0]
    print name
    @[L, @[L, "state".lString, "ok".lString].lList, @[L, "msg".lString, "ack".lString].lList].lList

  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdHello))
  
proc cmdStatus(server: Server): Value =
  proc impl_cmdStatus(args: seq[Value]): Future[Value] {.async.} =
    @[server.clients.len.intToStr.lString].lList

  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdStatus))

proc cmdExec(server: Server): Value =
  proc impl_cmdExec(args: seq[Value]): Future[Value] {.async.} =
    let name = args[0].asString
    if name == nil:
      print "expected string got", name
      return L_nil

    let cmdArgs = args[1].asList
    if cmdArgs == nil:
      print "expected list got", cmdArgs
      return L_nil
      
    let cmd = name.str
    var builtArgs = @[L]

    for a in cmdArgs.values:
        builtArgs.add(a)

    let msg = @["exec".lIdent, cmd.lString, builtArgs.lList].lList.toString.lenPrefixed
    for client in server.clients:
      await client.sock.send(msg)

    L_nil
  Value(kind: vkFunc, fn: FuncValue(fn: impl_cmdExec))
  
proc initEnv(server: var Server) =
  let values = {
    "close": cmdClose(server),
    "hello": cmdHello(server),
    "status": cmdStatus(server),
    "exec": cmdExec(server)
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
  ClientHandle(sock: client[1], clientAddr: client[0], id: server.clientId)

proc handleClient(server: Server, client: ClientHandle) {.async.} =
  while true:
    let msg = await client.recvMessage
    # Socket closed
    if msg == "":
      server.clients.delete(server.clients.find(client))
      return

    print "client said", msg
    let command = parseSource msg
    echo &"Parsed: {command.dbg}"
    let res = interpretTree(server.env, command).await.toString
    await client.sock.send(align(intToStr(res.len), 4, '0') & res)

proc mainLoop(server: Server) {.async.} =
  while server.running:
    echo "Waiting for client"

    let fut = server.waitForClient
    server.acceptFut = fut

    var client: ClientHandle
    try:
      client = await server.acceptFut
    except:
      return

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
  echo "Server up on localhost:6969"
  
  try:
    waitFor mainLoop(server)
  except:
    print getCurrentException()
  finally:
    echo "Close server"
    for client in server.clients:
      # Wait 5 seconds for clients to finish, don't care if they can't
      # finish in time, we're closing!
      echo &"Closing {client.clientAddr}"
      discard waitFor client.fut.withTimeout(5_000)
      echo &"Closed {client.clientAddr}"
    quit(QuitSuccess)
    
