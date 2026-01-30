///| Semaphore implementation for cooperative multitasking
///  Works without real threads by tracking waiting processes

/// Semaphore
pub struct Semaphore {
  id : Int
  mut count : Int
  waiters : Array[Pid]  // Processes waiting on this semaphore
}

/// Global semaphore ID counter
let next_sem_id : Ref[Int] = { val: 1 }

/// Create new semaphore with initial count
pub fn Semaphore::new(initial : Int) -> Semaphore {
  let id = next_sem_id.val
  next_sem_id.val += 1
  { id, count: initial, waiters: [] }
}

/// Get semaphore ID
pub fn Semaphore::get_id(self : Semaphore) -> Int {
  self.id
}

/// Get current count
pub fn Semaphore::get_count(self : Semaphore) -> Int {
  self.count
}

/// Try to acquire (decrement) - returns true if successful
/// If count > 0, decrements and returns true
/// If count == 0, adds pid to waiters and returns false
pub fn Semaphore::try_acquire(self : Semaphore, pid : Pid) -> Bool {
  if self.count > 0 {
    self.count -= 1
    true
  } else {
    // Add to waiters if not already there
    let Pid(p) = pid
    let mut found = false
    for waiter in self.waiters {
      let Pid(w) = waiter
      if w == p {
        found = true
        break
      }
    }
    if not(found) {
      self.waiters.push(pid)
    }
    false
  }
}

/// Release (increment) - wakes one waiter if any
/// Returns the PID of the woken process, if any
pub fn Semaphore::release(self : Semaphore) -> Pid? {
  if self.waiters.length() > 0 {
    // Wake first waiter
    let waiter = self.waiters.remove(0)
    Some(waiter)
  } else {
    self.count += 1
    None
  }
}

/// Check if any process is waiting
pub fn Semaphore::has_waiters(self : Semaphore) -> Bool {
  self.waiters.length() > 0
}

/// Get number of waiters
pub fn Semaphore::waiter_count(self : Semaphore) -> Int {
  self.waiters.length()
}

/// Remove a specific waiter (e.g., when process is killed)
pub fn Semaphore::remove_waiter(self : Semaphore, pid : Pid) -> Bool {
  let Pid(target) = pid
  for i = 0; i < self.waiters.length(); i = i + 1 {
    let Pid(w) = self.waiters[i]
    if w == target {
      let _ = self.waiters.remove(i)
      return true
    }
  }
  false
}

/// Mutex - binary semaphore
pub struct Mutex {
  sem : Semaphore
  mut owner : Pid?
}

pub fn Mutex::new() -> Mutex {
  { sem: Semaphore::new(1), owner: None }
}

/// Try to lock mutex
pub fn Mutex::try_lock(self : Mutex, pid : Pid) -> Bool {
  if self.sem.try_acquire(pid) {
    self.owner = Some(pid)
    true
  } else {
    false
  }
}

/// Unlock mutex
pub fn Mutex::unlock(self : Mutex, pid : Pid) -> Pid? raise ProcError {
  match self.owner {
    Some(owner_pid) => {
      let Pid(o) = owner_pid
      let Pid(p) = pid
      if o != p {
        raise ProcError::PermissionDenied("Not mutex owner")
      }
      self.owner = None
      self.sem.release()
    }
    None => raise ProcError::InvalidState("Mutex not locked")
  }
}

/// Check if locked
pub fn Mutex::is_locked(self : Mutex) -> Bool {
  self.sem.get_count() == 0
}

/// Get owner
pub fn Mutex::get_owner(self : Mutex) -> Pid? {
  self.owner
}

/// Condition variable for waiting on conditions
pub struct CondVar {
  id : Int
  waiters : Array[Pid]
}

let next_condvar_id : Ref[Int] = { val: 1 }

pub fn CondVar::new() -> CondVar {
  let id = next_condvar_id.val
  next_condvar_id.val += 1
  { id, waiters: [] }
}

/// Wait on condition - adds to waiters, returns false (must yield)
pub fn CondVar::wait(self : CondVar, pid : Pid) -> Bool {
  let Pid(p) = pid
  let mut found = false
  for waiter in self.waiters {
    let Pid(w) = waiter
    if w == p {
      found = true
      break
    }
  }
  if not(found) {
    self.waiters.push(pid)
  }
  false
}

/// Signal one waiter
pub fn CondVar::signal(self : CondVar) -> Pid? {
  if self.waiters.length() > 0 {
    Some(self.waiters.remove(0))
  } else {
    None
  }
}

/// Signal all waiters
pub fn CondVar::broadcast(self : CondVar) -> Array[Pid] {
  let woken = self.waiters.copy()
  self.waiters.clear()
  woken
}

/// Get ID
pub fn CondVar::get_id(self : CondVar) -> Int {
  self.id
}
