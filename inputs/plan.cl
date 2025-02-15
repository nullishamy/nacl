(plan "name" (
  (exec "apt" '("update"))
  (apt 'install ("git" "curl"))))
