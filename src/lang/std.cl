(defun . (k v)
  (list k v))

(defun --installer/apt (pkg)
  (exec "apt" (list "install" pkg "-y")))

(defun --updater/apt ()
  (exec "apt" (list "update")))

(defun --installer/mock (pkg)
  (exec "echo" (list "would have installed" pkg )))

(defun --updater/mock ()
  (exec "echo" (list "would have updated packages")))

(set backend/apt (list --installer/apt --updater/apt))
(set backend/mock (list --installer/mock --updater/mock))

(defun packages/install (pkg)
  (set installer (nth 0 backend))
  (waitfor (installer pkg)))

(defun packages/update ()
  (set updater (nth 1 backend))
  (waitfor (updater)))

(defun packages/docker-deps ()
  (set arch (str/strip (nth 0 (waitfor (exec "dpkg" (list "--print-architecture"))))))
  (set codename (str/strip (nth 0 (waitfor (exec "sh" (list "-c" "'source /etc/os-release && echo $VERSION_CODENAME'" ))))))

  (set content (str/join
                q "deb [arch=" arch " signed-by=/etc/apt/keyrings/docker.asc] "
                "https://download.docker.com/linux/debian " codename " stable"
                " > /etc/apt/sources.list.d/docker.list" q))

  (waitfor (exec "bash" (list "-c" (str/join "'echo " content " > /etc/apt/sources.list.d/docker.list'"))))
  
  (packages/install "ca-certificates")
  (packages/install "curl")
  
  (waitfor (exec "install" '("-m" "0755" "-d" "/etc/apt/keyrings")))
  (waitfor (exec "curl" '("-fsSL" "https://download.docker.com/linux/debian/gpg" "-o" "/etc/apt/keyrings/docker.asc")))
  (waitfor (exec "bash" '("-c" cmd)))
  
  (packages/update)
  (packages/install "docker-ce")
  (packages/install "docker-ce-cli")
  (packages/install "containerd.io")
  (packages/install "docker-buildx-plugin")
  (packages/install "docker-compose-plugin"))

(defun packages/docker ()
  (packages/docker-deps)
  (exec "docker" '("run" "hello-world")))

(defun targets/add-all (node-ids)
  (map node-ids targets/add))

(defun server/use-all-nodes ()
  (set nodes (server/nodes))
  
  (defun node-id (node)
    (nth 0 node))

  (set node-ids (map nodes node-id))
  (targets/add-all node-ids)
  
  (list nodes node-ids))
