let () =
  let greeting = Mylib.greet "Test" in
  if greeting = "Hello, Test!" then
    print_endline "Test passed"
  else
    failwith "Test failed"