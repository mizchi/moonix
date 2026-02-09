///|
/// Tests for process management
test "basic process lifecycle" {
  let sched = @proc.Scheduler::new()

  // Spawn a process that runs 3 times then exits
  let mut count = 0
  let pid = sched.spawn(
    "counter",
    @proc.ProcessFn::new(fn(_proc) {
      count += 1
      if count >= 3 {
        @proc.StepResult::exit(0)
      } else {
        @proc.StepResult::yield_()
      }
    }),
    None,
  )

  // Run scheduler
  sched.run()

  // Process should be zombie
  match sched.get_process(pid) {
    Some(proc) => assert_eq(proc.get_state().to_string(), "Zombie")
    None => panic()
  }
  assert_eq(count, 3)
}

///|
test "semaphore synchronization" {
  let sched = @proc.Scheduler::new()
  let sem = @proc.Semaphore::new(0) // Start locked
  let sem_id = sem.get_id()
  sched.register_semaphore(sem)
  let result : Ref[String] = { val: "" }

  // Producer - releases semaphore after doing work
  let _producer = sched.spawn(
    "producer",
    @proc.ProcessFn::new(fn(_proc) {
      result.val = result.val + "P"
      @proc.StepResult::exit(0)
    }),
    None,
  )

  // Consumer - waits on semaphore
  let mut consumer_state = 0
  let _consumer = sched.spawn(
    "consumer",
    @proc.ProcessFn::new(fn(_proc) {
      if consumer_state == 0 {
        consumer_state = 1
        @proc.StepResult::wait_sem(sem_id)
      } else {
        result.val = result.val + "C"
        @proc.StepResult::exit(0)
      }
    }),
    None,
  )

  // Run one tick - producer runs
  let _ = sched.tick()
  // Producer finished, consumer blocked

  // Release semaphore to wake consumer
  sched.release_semaphore(sem_id)

  // Run remaining
  sched.run()
  assert_eq(result.val, "PC")
}

///|
test "multiple processes round-robin" {
  let sched = @proc.Scheduler::new()
  let order : Ref[String] = { val: "" }

  // Process A
  let mut a_count = 0
  let _pid_a = sched.spawn(
    "A",
    @proc.ProcessFn::new(fn(_proc) {
      order.val = order.val + "A"
      a_count += 1
      if a_count >= 2 {
        @proc.StepResult::exit(0)
      } else {
        @proc.StepResult::yield_()
      }
    }),
    None,
  )

  // Process B
  let mut b_count = 0
  let _pid_b = sched.spawn(
    "B",
    @proc.ProcessFn::new(fn(_proc) {
      order.val = order.val + "B"
      b_count += 1
      if b_count >= 2 {
        @proc.StepResult::exit(0)
      } else {
        @proc.StepResult::yield_()
      }
    }),
    None,
  )
  sched.run()

  // Should interleave: ABAB
  assert_eq(order.val, "ABAB")
}

///|
test "sleep and wake" {
  let sched = @proc.Scheduler::new()
  let order : Ref[String] = { val: "" }

  // Sleeper - sleeps for 2 ticks
  let mut sleeper_state = 0
  let _sleeper = sched.spawn(
    "sleeper",
    @proc.ProcessFn::new(fn(_proc) {
      if sleeper_state == 0 {
        sleeper_state = 1
        order.val = order.val + "S1"
        @proc.StepResult::sleep(2)
      } else {
        order.val = order.val + "S2"
        @proc.StepResult::exit(0)
      }
    }),
    None,
  )

  // Worker - runs while sleeper sleeps
  let mut worker_count = 0
  let _worker = sched.spawn(
    "worker",
    @proc.ProcessFn::new(fn(_proc) {
      order.val = order.val + "W"
      worker_count += 1
      if worker_count >= 3 {
        @proc.StepResult::exit(0)
      } else {
        @proc.StepResult::yield_()
      }
    }),
    None,
  )
  sched.run()

  // Sleeper runs, then worker runs 2 times, sleeper wakes, then finish
  assert_true(order.val.contains("S1"))
  assert_true(order.val.contains("S2"))
  assert_true(order.val.contains("W"))
}

///|
test "waitpid" {
  let sched = @proc.Scheduler::new()

  // Child process
  let mut child_done = false
  let child_pid = sched.spawn(
    "child",
    @proc.ProcessFn::new(fn(_proc) {
      child_done = true
      @proc.StepResult::exit(42)
    }),
    None,
  )

  // Parent waits for child
  let mut parent_state = 0
  let exit_code : Ref[Int] = { val: -1 }
  let _parent = sched.spawn(
    "parent",
    @proc.ProcessFn::new(fn(_proc) {
      if parent_state == 0 {
        parent_state = 1
        @proc.StepResult::wait_pid(child_pid)
      } else {
        match sched.waitpid(child_pid) {
          Some(code) => exit_code.val = code
          None => ()
        }
        @proc.StepResult::exit(0)
      }
    }),
    None,
  )
  sched.run()
  assert_true(child_done)
  assert_eq(exit_code.val, 42)
}

///|
test "signal handling" {
  let sched = @proc.Scheduler::new()
  let got_signal : Ref[Bool] = { val: false }

  // Process with signal handler
  let pid = sched.spawn(
    "handler",
    @proc.ProcessFn::new(fn(_proc) { @proc.StepResult::yield_() }),
    None,
  )

  // Set signal handler
  match sched.get_process(pid) {
    Some(proc) =>
      proc.set_signal_handler(@proc.Signal::sigusr1(), fn(_sig) {
        got_signal.val = true
        @proc.StepResult::exit(0)
      })
    None => ()
  }

  // Send signal
  sched.kill(pid, @proc.Signal::sigusr1()) catch {
    _ => ()
  }
  sched.run()
  assert_true(got_signal.val)
}

///|
test "mutex" {
  let mutex = @proc.Mutex::new()
  let pid1 = @proc.Pid::new(1)
  let pid2 = @proc.Pid::new(2)

  // First lock should succeed
  assert_true(mutex.try_lock(pid1))
  assert_true(mutex.is_locked())

  // Unlock pid1
  let _ = mutex.unlock(pid1) catch { _ => None }
  assert_false(mutex.is_locked())

  // Now pid2 can lock (no waiters, so mutex should be unlocked)
  assert_true(mutex.try_lock(pid2))
  assert_true(mutex.is_locked())

  // Try lock from pid1 should fail now
  assert_false(mutex.try_lock(pid1))
}
