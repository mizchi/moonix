///| xsh test CLI

///|
fn main() -> Unit {
  let args = @env.args()
  let (cycle_debug, script_mode, files) = parse_args(args)
  if files.is_empty() {
    print_usage()
    return
  }
  let mut total = 0
  let mut passed = 0
  let mut failed = 0
  for path in files {
    if script_mode {
      let report = run_file_script(path, cycle_debug)
      print_script_report(path, report)
      total += 1
      if report.ok {
        passed += 1
      } else {
        failed += 1
      }
    } else {
      let report = try {
        run_file_tests(path, cycle_debug)
      } catch {
        e => {
          println("error: " + path + ": " + e.to_string())
          @abort.abort("xsh test failed")
        }
      }
      print_report(path, report)
      total += report.total
      passed += report.passed
      failed += report.failed
    }
  }
  println("total: " + total.to_string() + ", passed: " + passed.to_string() + ", failed: " + failed.to_string())
  if failed > 0 {
    @abort.abort("xsh test failed")
  }
}

fn print_usage() -> Unit {
  println("usage: xsh-test [--cycle-debug] [--script] <file> [file...]")
}

fn print_report(path : String, report : @xsh.TestReport) -> Unit {
  println("\n" + path)
  println("  total: " + report.total.to_string() + ", passed: " + report.passed.to_string() + ", failed: " + report.failed.to_string())
  for failure in report.failures {
    let name = match failure.name {
      Some(n) => n
      None => "<unnamed>"
    }
    println("  - " + name + ": " + failure.error)
  }
}

fn run_file_tests(path : String, cycle_debug : Bool) -> @xsh.TestReport raise CliError {
  let content = read_os_file(path)
  run_tests_with_reader(path, content, cycle_debug, read_os_file)
}

fn print_script_report(path : String, report : ScriptReport) -> Unit {
  let passed = if report.ok { 1 } else { 0 }
  let failed = if report.ok { 0 } else { 1 }
  println("\n" + path)
  println("  total: 1, passed: " + passed.to_string() + ", failed: " + failed.to_string())
  if not(report.ok) {
    let msg = match report.error {
      Some(m) => m
      None => "<error>"
    }
    println("  - script: " + msg)
  }
}

fn run_file_script(path : String, cycle_debug : Bool) -> ScriptReport {
  let content = try {
    read_os_file(path)
  } catch {
    e => return script_failure_report(e.to_string())
  } noraise {
    c => c
  }
  run_script_with_reader(path, content, cycle_debug, read_os_file)
}

fn read_os_file(path : String) -> String raise CliError {
  @xfs.read_file_to_string(path, encoding="utf8") catch {
    e => raise CliError::Io(e.to_string())
  }
}

fn parse_args(args : Array[String]) -> (Bool, Bool, Array[String]) {
  let mut cycle_debug = false
  let mut script_mode = false
  let files : Array[String] = []
  for i in 1..<args.length() {
    let arg = args[i]
    if arg == "--cycle-debug" {
      cycle_debug = true
    } else if arg == "--script" {
      script_mode = true
    } else {
      files.push(arg)
    }
  }
  (cycle_debug, script_mode, files)
}
