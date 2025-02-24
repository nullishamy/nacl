(defun install-package (package)
  ; Emulate a call to exec, which doesn't exist in tests.
  (list 'exec 'apt 'install (list package)))

(defun install-packages (xs)
  (map xs install-package))

(install-packages '("git" "curl"))
