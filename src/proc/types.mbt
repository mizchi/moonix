///| Process management types for cooperative multitasking

///|
/// Process ID
pub struct Pid(Int) derive(Eq, Hash, Show)

///|
pub fn Pid::new(id : Int) -> Pid {
  Pid(id)
}

///|
/// Process state
pub enum ProcessState {
  Ready // Can run
  Running // Currently executing
  Sleeping // Waiting for time
  Blocked // Waiting on semaphore/resource
  Zombie // Terminated, waiting to be reaped
}

///|
pub impl Show for ProcessState with output(self, logger) {
  match self {
    Ready => logger.write_string("Ready")
    Running => logger.write_string("Running")
    Sleeping => logger.write_string("Sleeping")
    Blocked => logger.write_string("Blocked")
    Zombie => logger.write_string("Zombie")
  }
}

///|
/// Signal types
pub enum Signal {
  SIGTERM // Terminate
  SIGKILL // Force kill
  SIGINT // Interrupt (Ctrl+C)
  SIGSTOP // Stop/pause
  SIGCONT // Continue
  SIGUSR1 // User defined 1
  SIGUSR2 // User defined 2
}

///|
pub impl Show for Signal with output(self, logger) {
  match self {
    SIGTERM => logger.write_string("SIGTERM")
    SIGKILL => logger.write_string("SIGKILL")
    SIGINT => logger.write_string("SIGINT")
    SIGSTOP => logger.write_string("SIGSTOP")
    SIGCONT => logger.write_string("SIGCONT")
    SIGUSR1 => logger.write_string("SIGUSR1")
    SIGUSR2 => logger.write_string("SIGUSR2")
  }
}

// Signal constructors

///|
pub fn Signal::sigterm() -> Signal {
  SIGTERM
}

///|
pub fn Signal::sigkill() -> Signal {
  SIGKILL
}

///|
pub fn Signal::sigint() -> Signal {
  SIGINT
}

///|
pub fn Signal::sigstop() -> Signal {
  SIGSTOP
}

///|
pub fn Signal::sigcont() -> Signal {
  SIGCONT
}

///|
pub fn Signal::sigusr1() -> Signal {
  SIGUSR1
}

///|
pub fn Signal::sigusr2() -> Signal {
  SIGUSR2
}

///|
/// Step result - what process wants after executing one step
pub enum StepResult {
  Continue // Process wants to continue running
  Yield // Voluntarily yield to other processes
  Sleep(Int) // Sleep for N scheduler ticks
  WaitSem(Int) // Wait on semaphore ID
  WaitPid(Pid) // Wait for another process
  Exit(Int) // Process finished with exit code
}

// StepResult constructors

///|
pub fn StepResult::continue_() -> StepResult {
  Continue
}

///|
pub fn StepResult::yield_() -> StepResult {
  Yield
}

///|
pub fn StepResult::sleep(ticks : Int) -> StepResult {
  Sleep(ticks)
}

///|
pub fn StepResult::wait_sem(sem_id : Int) -> StepResult {
  WaitSem(sem_id)
}

///|
pub fn StepResult::wait_pid(pid : Pid) -> StepResult {
  WaitPid(pid)
}

///|
pub fn StepResult::exit(code : Int) -> StepResult {
  Exit(code)
}

///|
/// Process errors
pub suberror ProcError {
  NotFound(String)
  AlreadyExists(String)
  InvalidState(String)
  PermissionDenied(String)
  ResourceBusy(String)
}

///|
pub impl Show for ProcError with output(self, logger) {
  match self {
    NotFound(msg) => logger.write_string("NotFound(\{msg})")
    AlreadyExists(msg) => logger.write_string("AlreadyExists(\{msg})")
    InvalidState(msg) => logger.write_string("InvalidState(\{msg})")
    PermissionDenied(msg) => logger.write_string("PermissionDenied(\{msg})")
    ResourceBusy(msg) => logger.write_string("ResourceBusy(\{msg})")
  }
}

///|
/// File descriptor for process I/O
pub struct Fd(Int) derive(Eq, Hash, Show)

///|
pub fn Fd::stdin() -> Fd {
  Fd(0)
}

///|
pub fn Fd::stdout() -> Fd {
  Fd(1)
}

///|
pub fn Fd::stderr() -> Fd {
  Fd(2)
}
