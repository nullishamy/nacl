import ./lib

echo "--- START ---\n"

proc aptTest() =
  discard
  # testFrom("apt.cl")
  #   .evaluatesTo("(\"git\")")
  #   .run

proc conditionsTest() =
  testFrom("conditions.cl")
    .evaluatesTo("'(t)")
    .run

proc constructListTest() =
  testFrom("construct-list.cl")
    .evaluatesTo("(1 2 3)")
    .run

proc quoteListTest() =
  testFrom("quote-list.cl")
    .evaluatesTo("'(test 1 '(inner) '(ack))")
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

proc dotTest() =
  testFrom("dot.cl")
    .evaluatesTo("(('host \"nixon.cluster\") ('port 6969))")
    .run

proc embedTest() =
  testFrom("embed.cl")
    .evaluatesTo("(104 101 108 108 111)")
    .run

proc secondQuoteTest() =
  testFrom("2nd-level-quote.cl")
    .evaluatesTo("'(quoted)")
    .run
  
let tests = @[
  aptTest,
  conditionsTest,
  constructListTest,
  quoteListTest,
  symbolsTest,
  variablesTest,
  fnStringifyTest,
  defunTest,
  dotTest,
  embedTest,
  secondQuoteTest
]

for test in tests:
  test()
  echo ""
