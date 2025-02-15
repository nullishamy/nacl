import ./lib

echo "--- START ---\n"

proc aptTest() =
  discard
  # testFrom("apt.cl")
  #   .evaluatesTo("(\"git\")")
  #   .run

proc conditionsTest() =
  testFrom("conditions.cl")
    .evaluatesTo("('t)")
    .run

proc constructListTest() =
  testFrom("construct-list.cl")
    .evaluatesTo("(1 2 3)")
    .run

proc quoteListTest() =
  testFrom("quote-list.cl")
    .evaluatesTo("('test 1 ('inner) nil)")
    .run

proc symbolsTest() =
  testFrom("symbols.cl")
    .evaluatesTo("('test 1 'test2)")
    .run

proc variablesTest() =
  testFrom("variables.cl")
    .evaluatesTo("(12)")
    .run

proc fnStringifyTest() =
  testFrom("fn-strings.cl")
    .evaluatesTo("(list (\"arg1\" 2))")
    .run

proc defunTest() =
  testFrom("defun.cl")
    .evaluatesTo("(('exec 'apt 'install (\"git\")) ('exec 'apt 'install (\"curl\")))")
    .run
  
let tests = @[
  aptTest,
  conditionsTest,
  constructListTest,
  quoteListTest,
  symbolsTest,
  variablesTest,
  fnStringifyTest,
  defunTest
]

for test in tests:
  test()
  echo ""
