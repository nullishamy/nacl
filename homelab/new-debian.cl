(set 'installer installer/apt)
(set 'updater updater/apt)

(set 'install-docker 1)

(plan "initialise new server"
  ((packages/update)
   (packages/install "git")
   (packages/install "net-tools")
   (if install-docker
     (packages/docker))))
