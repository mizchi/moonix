///| Cooperative scheduler for process management

/// Process table
pub struct Scheduler {
  processes : Map[Int, Process]
  mut current : Pid?
  ready_queue : Array[Pid]
  semaphores : Map[Int, Semaphore]
  mut tick : Int
}

pub fn Scheduler::new() -> Scheduler {
  {
    processes: {},
    current: None,
    ready_queue: [],
    semaphores: {},
    tick: 0,
  }
}

/// Spawn a new process
pub fn Scheduler::spawn(
  self : Scheduler,
  name : String,
  step_fn : ProcessFn,
  parent : Pid?
) -> Pid {
  let proc = Process::new(name, step_fn, parent)
  let pid = proc.get_pid()
  let Pid(p) = pid
  self.processes[p] = proc
  self.ready_queue.push(pid)

  // Add to parent's children
  match parent {
    Some(parent_pid) => {
      let Pid(pp) = parent_pid
      match self.processes.get(pp) {
        Some(parent_proc) => parent_proc.add_child(pid)
        None => ()
      }
    }
    None => ()
  }

  pid
}

/// Kill a process
pub fn Scheduler::kill(
  self : Scheduler,
  pid : Pid,
  sig : Signal
) -> Unit raise ProcError {
  let Pid(p) = pid
  match self.processes.get(p) {
    Some(proc) => {
      match sig {
        SIGKILL => {
          // Force kill - immediately terminate
          proc.state = Zombie
          proc.exit_code = Some(137)  // 128 + 9
          self.remove_from_ready(pid)
          self.cleanup_waiters(pid)
        }
        _ => proc.send_signal(sig)
      }
    }
    None => raise ProcError::NotFound("Process \{p} not found")
  }
}

/// Wait for a process to finish
pub fn Scheduler::waitpid(self : Scheduler, pid : Pid) -> Int? {
  let Pid(p) = pid
  match self.processes.get(p) {
    Some(proc) =>
      match proc.get_state() {
        Zombie => proc.get_exit_code()
        _ => None  // Not finished yet
      }
    None => Some(-1)  // Process doesn't exist
  }
}

/// Reap a zombie process
pub fn Scheduler::reap(self : Scheduler, pid : Pid) -> Int raise ProcError {
  let Pid(p) = pid
  match self.processes.get(p) {
    Some(proc) =>
      match proc.get_state() {
        Zombie => {
          let exit_code = proc.get_exit_code().unwrap_or(0)
          // Remove from parent's children
          match proc.get_parent() {
            Some(parent_pid) => {
              let Pid(pp) = parent_pid
              match self.processes.get(pp) {
                Some(parent_proc) => {
                  let _ = parent_proc.remove_child(pid)
                }
                None => ()
              }
            }
            None => ()
          }
          // Remove process
          self.processes.remove(p)
          exit_code
        }
        _ => raise ProcError::InvalidState("Process not a zombie")
      }
    None => raise ProcError::NotFound("Process \{p} not found")
  }
}

/// Register a semaphore
pub fn Scheduler::register_semaphore(self : Scheduler, sem : Semaphore) -> Unit {
  self.semaphores[sem.get_id()] = sem
}

/// Get a semaphore
pub fn Scheduler::get_semaphore(self : Scheduler, id : Int) -> Semaphore? {
  self.semaphores.get(id)
}

/// Run one scheduling tick - execute one ready process
pub fn Scheduler::tick(self : Scheduler) -> Bool {
  self.tick += 1

  // Update sleeping processes
  for _, proc in self.processes {
    match proc.get_state() {
      Sleeping => {
        proc.sleep_ticks -= 1
        if proc.sleep_ticks <= 0 {
          proc.state = Ready
          self.ready_queue.push(proc.get_pid())
        }
      }
      _ => ()
    }
  }

  // Get next ready process
  if self.ready_queue.is_empty() {
    return false  // No runnable processes
  }

  let pid = self.ready_queue.remove(0)
  let Pid(p) = pid

  match self.processes.get(p) {
    Some(proc) => {
      match proc.get_state() {
        Ready | Running => {
          self.current = Some(pid)
          let result = proc.step()
          self.handle_step_result(pid, proc, result)
          self.current = None
          true
        }
        _ => {
          // Process not ready, try next
          self.tick()
        }
      }
    }
    None => self.tick()  // Process disappeared, try next
  }
}

/// Handle the result of a process step
fn Scheduler::handle_step_result(
  self : Scheduler,
  pid : Pid,
  proc : Process,
  result : StepResult
) -> Unit {
  match result {
    Continue => {
      // Process wants to keep running - put back in ready queue
      proc.state = Ready
      self.ready_queue.push(pid)
    }
    Yield => {
      // Voluntarily yield - put at end of ready queue
      proc.state = Ready
      self.ready_queue.push(pid)
    }
    Sleep(ticks) => {
      proc.state = Sleeping
      proc.sleep_ticks = ticks
    }
    WaitSem(sem_id) => {
      // Block on semaphore
      match self.semaphores.get(sem_id) {
        Some(sem) => {
          if sem.try_acquire(pid) {
            // Got the semaphore, continue
            proc.state = Ready
            self.ready_queue.push(pid)
          } else {
            // Blocked
            proc.state = Blocked
            proc.waiting_sem = Some(sem_id)
          }
        }
        None => {
          // Invalid semaphore, just continue
          proc.state = Ready
          self.ready_queue.push(pid)
        }
      }
    }
    WaitPid(wait_pid) => {
      // Wait for another process
      let Pid(wp) = wait_pid
      match self.processes.get(wp) {
        Some(target) =>
          match target.get_state() {
            Zombie => {
              // Already finished
              proc.state = Ready
              self.ready_queue.push(pid)
            }
            _ => {
              proc.state = Blocked
              proc.waiting_pid = Some(wait_pid)
            }
          }
        None => {
          // Process doesn't exist, unblock
          proc.state = Ready
          self.ready_queue.push(pid)
        }
      }
    }
    Exit(code) => {
      proc.state = Zombie
      proc.exit_code = Some(code)
      // Wake processes waiting for this one
      self.wake_waiters_for(pid)
    }
  }
}

/// Wake processes waiting for a specific PID
fn Scheduler::wake_waiters_for(self : Scheduler, finished_pid : Pid) -> Unit {
  let Pid(fp) = finished_pid
  for _, proc in self.processes {
    match proc.waiting_pid {
      Some(wait_pid) => {
        let Pid(wp) = wait_pid
        if wp == fp {
          proc.waiting_pid = None
          proc.state = Ready
          self.ready_queue.push(proc.get_pid())
        }
      }
      None => ()
    }
  }
}

/// Release a semaphore and wake blocked processes
pub fn Scheduler::release_semaphore(self : Scheduler, sem_id : Int) -> Unit {
  match self.semaphores.get(sem_id) {
    Some(sem) => {
      match sem.release() {
        Some(woken_pid) => {
          let Pid(wp) = woken_pid
          match self.processes.get(wp) {
            Some(proc) => {
              proc.waiting_sem = None
              proc.state = Ready
              self.ready_queue.push(woken_pid)
            }
            None => ()
          }
        }
        None => ()
      }
    }
    None => ()
  }
}

/// Remove PID from ready queue
fn Scheduler::remove_from_ready(self : Scheduler, pid : Pid) -> Unit {
  let Pid(target) = pid
  for i in 0..<self.ready_queue.length() {
    let Pid(p) = self.ready_queue[i]
    if p == target {
      let _ = self.ready_queue.remove(i)
      return
    }
  }
}

/// Cleanup waiters when a process is killed
fn Scheduler::cleanup_waiters(self : Scheduler, pid : Pid) -> Unit {
  // Remove from semaphore waiters
  for _, sem in self.semaphores {
    let _ = sem.remove_waiter(pid)
  }
  // Wake processes waiting for this one
  self.wake_waiters_for(pid)
}

/// Run until no processes are ready
pub fn Scheduler::run(self : Scheduler) -> Unit {
  while self.tick() {
    // Keep running
  }
}

/// Run for at most N ticks
pub fn Scheduler::run_n(self : Scheduler, max_ticks : Int) -> Int {
  let mut count = 0
  while count < max_ticks && self.tick() {
    count += 1
  }
  count
}

/// Get current tick count
pub fn Scheduler::get_tick(self : Scheduler) -> Int {
  self.tick
}

/// Get number of processes
pub fn Scheduler::process_count(self : Scheduler) -> Int {
  self.processes.length()
}

/// Get ready queue length
pub fn Scheduler::ready_count(self : Scheduler) -> Int {
  self.ready_queue.length()
}

/// Get a process by PID
pub fn Scheduler::get_process(self : Scheduler, pid : Pid) -> Process? {
  let Pid(p) = pid
  self.processes.get(p)
}

/// List all PIDs
pub fn Scheduler::list_pids(self : Scheduler) -> Array[Pid] {
  let pids : Array[Pid] = []
  for p, _ in self.processes {
    pids.push(Pid(p))
  }
  pids
}

/// Get currently running process
pub fn Scheduler::current_pid(self : Scheduler) -> Pid? {
  self.current
}
