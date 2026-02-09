///| Process representation for cooperative multitasking

///|
/// Process step function type
/// Takes the process and returns what it wants to do next
pub struct ProcessFn((Process) -> StepResult)

///|
pub fn ProcessFn::new(f : (Process) -> StepResult) -> ProcessFn {
  ProcessFn(f)
}

///|
/// Process Control Block (PCB)
pub struct Process {
  pid : Pid
  name : String
  mut state : ProcessState
  mut exit_code : Int?
  parent : Pid?
  children : Array[Pid]

  // I/O buffers
  stdin_buf : Array[Byte]
  stdout_buf : Array[Byte]
  stderr_buf : Array[Byte]

  // Execution
  step_fn : ProcessFn
  mut tick_count : Int // How many ticks executed
  mut sleep_ticks : Int // Ticks to sleep (when Sleeping)
  mut waiting_sem : Int? // Semaphore ID waiting on
  mut waiting_pid : Pid? // PID waiting for

  // Signals
  pending_signals : Array[Signal]
  signal_handlers : Map[Int, (Signal) -> StepResult]
}

///|
/// Global PID counter
let next_pid : Ref[Int] = { val: 1 }

///|
/// Create a new process
pub fn Process::new(
  name : String,
  step_fn : ProcessFn,
  parent : Pid?,
) -> Process {
  let pid = Pid(next_pid.val)
  next_pid.val += 1
  {
    pid,
    name,
    state: Ready,
    exit_code: None,
    parent,
    children: [],
    stdin_buf: [],
    stdout_buf: [],
    stderr_buf: [],
    step_fn,
    tick_count: 0,
    sleep_ticks: 0,
    waiting_sem: None,
    waiting_pid: None,
    pending_signals: [],
    signal_handlers: {},
  }
}

///|
/// Get PID
pub fn Process::get_pid(self : Process) -> Pid {
  self.pid
}

///|
/// Get name
pub fn Process::get_name(self : Process) -> String {
  self.name
}

///|
/// Get state
pub fn Process::get_state(self : Process) -> ProcessState {
  self.state
}

///|
/// Get exit code (only valid when Zombie)
pub fn Process::get_exit_code(self : Process) -> Int? {
  self.exit_code
}

///|
/// Get parent PID
pub fn Process::get_parent(self : Process) -> Pid? {
  self.parent
}

///|
/// Get children
pub fn Process::get_children(self : Process) -> Array[Pid] {
  self.children.copy()
}

///|
/// Add a child
pub fn Process::add_child(self : Process, child : Pid) -> Unit {
  self.children.push(child)
}

///|
/// Remove a child
pub fn Process::remove_child(self : Process, child : Pid) -> Bool {
  let Pid(target) = child
  for i in 0..<self.children.length() {
    let Pid(c) = self.children[i]
    if c == target {
      let _ = self.children.remove(i)
      return true
    }
  }
  false
}

///|
/// Execute one step
pub fn Process::step(self : Process) -> StepResult {
  self.state = Running
  self.tick_count += 1

  // Check for pending signals first
  if self.pending_signals.length() > 0 {
    let sig = self.pending_signals.remove(0)
    let sig_num = signal_to_int(sig)
    match self.signal_handlers.get(sig_num) {
      Some(handler) => return handler(sig)
      None =>
        // Default signal handling
        match sig {
          SIGKILL | SIGTERM => return Exit(128 + sig_num)
          SIGSTOP => {
            self.state = Blocked
            return Yield
          }
          SIGCONT => () // Continue execution
          _ => ()
        }
    }
  }

  // Execute process logic
  let ProcessFn(f) = self.step_fn
  f(self)
}

///|
/// Send a signal to this process
pub fn Process::send_signal(self : Process, sig : Signal) -> Unit {
  self.pending_signals.push(sig)
}

///|
/// Set signal handler
pub fn Process::set_signal_handler(
  self : Process,
  sig : Signal,
  handler : (Signal) -> StepResult,
) -> Unit {
  self.signal_handlers[signal_to_int(sig)] = handler
}

///|
/// Write to stdin buffer
pub fn Process::write_stdin(self : Process, data : Bytes) -> Unit {
  for b in data {
    self.stdin_buf.push(b)
  }
}

///|
/// Read from stdin buffer
pub fn Process::read_stdin(self : Process, max_len : Int) -> Bytes {
  let len = if self.stdin_buf.length() < max_len {
    self.stdin_buf.length()
  } else {
    max_len
  }
  let result = Bytes::makei(len, fn(i) { self.stdin_buf[i] })
  // Remove read bytes
  for _ in 0..<len {
    let _ = self.stdin_buf.remove(0)

  }
  result
}

///|
/// Write to stdout buffer
pub fn Process::write_stdout(self : Process, data : Bytes) -> Unit {
  for b in data {
    self.stdout_buf.push(b)
  }
}

///|
/// Read from stdout buffer (for parent/shell)
pub fn Process::read_stdout(self : Process) -> Bytes {
  let result = Bytes::makei(self.stdout_buf.length(), fn(i) {
    self.stdout_buf[i]
  })
  self.stdout_buf.clear()
  result
}

///|
/// Write to stderr buffer
pub fn Process::write_stderr(self : Process, data : Bytes) -> Unit {
  for b in data {
    self.stderr_buf.push(b)
  }
}

///|
/// Read from stderr buffer
pub fn Process::read_stderr(self : Process) -> Bytes {
  let result = Bytes::makei(self.stderr_buf.length(), fn(i) {
    self.stderr_buf[i]
  })
  self.stderr_buf.clear()
  result
}

///|
/// Helper to convert signal to int
fn signal_to_int(sig : Signal) -> Int {
  match sig {
    SIGTERM => 15
    SIGKILL => 9
    SIGINT => 2
    SIGSTOP => 19
    SIGCONT => 18
    SIGUSR1 => 10
    SIGUSR2 => 12
  }
}
