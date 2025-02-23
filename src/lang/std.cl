(defun . (k v)
  '(k v))

(defun installer/apt (pkg)
  (exec "apt" '("install" pkg "-y")))

(defun updater/apt ()
  (exec "apt" '("update")))

(defun packages/install (pkg)
  (installer pkg))

(defun packages/update ()
  (updater))

(defun packages/docker-deps ()
  (set 'cmd "'echo deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable > /etc/apt/sources.list.d/docker.list'")
  
  (waitfor (packages/install "ca-certificates"))
  (waitfor (packages/install "curl"))
  
  (waitfor (exec "install" '("-m" "0755" "-d" "/etc/apt/keyrings")))
  (waitfor (exec "curl" '("-fsSL" "https://download.docker.com/linux/debian/gpg" "-o" "/etc/apt/keyrings/docker.asc")))
  (waitfor (exec "bash" '("-c" cmd)))
  
  (waitfor (packages/update))
  (waitfor (packages/install "docker-ce"))
  (waitfor (packages/install "docker-ce-cli"))
  (waitfor (packages/install "containerd.io"))
  (waitfor (packages/install "docker-buildx-plugin"))
  (waitfor (packages/install "docker-compose-plugin")))

(defun packages/docker ()
  (packages/docker-deps)
  (exec "docker" '("run" "hello-world")))
