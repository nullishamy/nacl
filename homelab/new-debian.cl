(set backend backend/mock)

(set node-info (server/use-all-nodes))
(set nodes (nth 0 node-info))
(set node-ids (nth 1 node-info))

(defun init-node (node)
  (set id (nth 0 node))
  (set name (nth 1 node))
  
  (targets/clear)
  (targets/add id)
  
  (packages/install "git")
  (packages/install "curl"))

(targets/clear)
(targets/add-all node-ids)

(packages/update)

(map nodes init-node)

(targets/clear)
(targets/add-all node-ids)
(waitfor (exec "cat" (list "/etc/os-release")))

nodes

;;(plan "initialise new server"
;;  ((packages/update)
;;   (packages/install "git")
;;   (packages/install "net-tools")
;;   (if install-docker
;;     (packages/docker))))

