(set 'update (waitfor (apt 'update (""))))
(set 'install (waitfor (apt 'install ("git" "curl" "net-tools" "-y"))))

'("finished plan" update install)
