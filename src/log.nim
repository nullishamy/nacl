type
  LogSink = ref object of RootObj
  StderrSink = ref object of LogSink

method write(self: LogSink, stream: string) {.base.} =
  quit "Unimplemented!"

method write(self: StderrSink, stream: string) =
  stderr.writeLine(stream)

type
  LogLevel = enum
    logTrace, logDebug, logInfo, logWarn, logError

  Logger = object
    level: LogLevel
    sinks: seq[LogSink]

let sink = new StderrSink
var sinks: seq[LogSink] = @[]
sinks.add(sink)

let logger* = Logger(level: logDebug, sinks: sinks)

method write(self: Logger, prefix: string, msg: string) =
  for s in self.sinks:
    s.write(prefix & msg)

proc trace*(self: Logger, msg: string) =
  self.write("[TRACE]: ", msg)

proc debug*(self: Logger, msg: string) =
  self.write("[DEBUG]: ", msg)

proc info*(self: Logger, msg: string) =
  self.write("[INFO]: ", msg)

proc warn*(self: Logger, msg: string) =
  self.write("[WARN]: ", msg)

proc error*(self: Logger, msg: string) =
  self.write("[ERROR]: ", msg)
