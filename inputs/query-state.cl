(defun package-installed (pkg)
  (set 'tracker (exec "dpkg" '("--get-selections" pkg)))
  (set 'installed (waitfor tracker))

  (defun handle-one-install (output)
	(if (str/contains output "no packages found")
		'(pkg "not installed")
		'(pkg "installed")))

  '(tracker (map installed handle-one-install)))

'(
  (package-installed "git")
  (package-installed "postgresql"))
