import std/net
import std/os
import std/osproc
import std/strformat
import std/strutils
import argparse
import ./print
import ./lang
import ./rpc
import std/tables
import sugar
import std/asyncdispatch
import std/asyncnet
import system
import system/exceptions

type
  Server = ref object
    sock: AsyncSocket
    acceptFut: Future[ClientHandle]
    
    runtime: Runtime
    clients: seq[ClientHandle]
    running: bool
    clientId: int
    
  ClientHandle = object
    id: int
    sock: AsyncSocket
    clientAddr: string
    fut: Future[void]

  Func = proc (server: Server): Future[string]
               
  Runtime = object
    funcs: Table[string, Func]

proc recvMessage(client: ClientHandle): Future[string] {.async.} =
  let sizeRaw = await client.sock.recv(4)
  if sizeRaw == "":
    return ""

  let size = parseInt(sizeRaw)
  print size
  await client.sock.recv(size)    

proc `==`(self: ClientHandle, other: ClientHandle): bool =
  self.id == other.id
  
proc impl_cmdClose(server: Server): Future[string] {.async.} =
  server.running = false
  # Force the server to stop trying to listen to new connections
  server.acceptFut.fail(new IOError)
  "(ack)"

proc impl_cmdHello(server: Server): Future[string] {.async.} =
  # Nothing more to it at the moment, just acknowledge we got the connection
  # and are ready to communicate
  "(ack)"

proc impl_cmdStatus(server: Server): Future[string] {.async.} =
  fmt"(list (""clients"" {server.clients.len}))"

proc impl_cmdExec(server: Server): Future[string] {.async.} =
  for client in server.clients:
    let msg = Message(kind: rqExec, id: 1, params: @["echo", "test"]).serialise
    await client.sock.send(msg)
    let response = client.recvMessage
    print response
  "(ack)"

# Nim doesn't want to infer it when we use it in the map
let cmdClose: Func = impl_cmdClose
let cmdHello: Func = impl_cmdHello
let cmdStatus: Func = impl_cmdStatus
let cmdExec: Func = impl_cmdExec

proc newServer(port: Port): Server =
  let funcs = {
    "close": cmdClose,
    "hello": cmdHello,
    "status": cmdStatus,
    "exec": cmdExec
  }.toTable
  
  let runtime = Runtime(funcs: funcs)
  
  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(port)
  server.listen()
  
  Server(sock: server, runtime: runtime, running: true, clientId: 0)

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
      
    let command = parseSource msg
    echo &"Parsed: {command.dbg}"

    case command.kind:
    of exList:
      let cmdName = command.lValues[0]
      case cmdName.kind 
      of exName:
        let text = cmdName.nValue
        var res = ""
        
        if server.runtime.funcs.hasKey(text):
          let fn = server.runtime.funcs[text]
          res = await fn(server)
        else:
          print text, "does not exist"
          res = fmt"(failure ""commmand {text} not recognised"")"

        await client.sock.send(align(intToStr(res.len), 4, '0') & res)
      else:
        print "Expected Name got ", cmdName
    else:
      print "Expected List got ", command

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
    
