(defun install-package (pkg)
  (exec "apt" '("install" pkg)))

(defun update-package-set ()
  (exec "apt" '("update")))

(set 'do-docker nil)
(defun docker-init ()
  (exec "echo" '("docker installation not implemented yet")))

(plan "initialise new server"
  ((update-package-set)
   (install-package "git")
   (install-package "net-tools")
   (if do-docker
     (docker-init))))
