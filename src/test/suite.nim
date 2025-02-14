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
  
let tests = @[
  aptTest,
  conditionsTest,
  constructListTest,
  quoteListTest,
  symbolsTest,
  variablesTest
]

for test in tests:
  test()
  echo ""
