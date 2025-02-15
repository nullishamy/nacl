# nacl - saltstack but with extra Nim

## get started:
build the binary:
```sh
nim --passL:-static --out=bin/nacl --opt:speed compile src/main.nim
```

start the server:
```sh
./bin/nacl server
```

create the agent file (agent.cl):
```cl
'(
  '('host "your server")
  '('port 6969))
```

copy the nacl binary and agent file to the server,
then start the agent:
```sh
./nacl agent
```

the agent will now handshake with the server, and then await instruction

you can execute instructions through the CLI:
```nushell
# This is nushell syntax, replace open with `cat` or similar
./bin/nacl exec (open ./init-server.cl)
```
```cl
; init-server.cl
(defun install-package (pkg)
  (exec "apt" '("install" pkg)))

(defun update-package-set ()
  (exec "apt" '("update")))

(set 'do-docker 1)
(defun docker-init ()
  (exec "echo" '("docker installation not implemented yet")))

(plan "initialise new server"
  ((update-package-set)
   (install-package "git")
   (install-package "net-tools")
   (if do-docker
     (docker-init))))
```

observe the results!
