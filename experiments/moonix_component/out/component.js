export function instantiate(getCoreModule, imports, instantiateCore = WebAssembly.instantiate) {
  
  let dv = new DataView(new ArrayBuffer());
  const dataView = mem => dv.buffer === mem.buffer ? dv : dv = new DataView(mem.buffer);
  
  const toUint64 = val => BigInt.asUintN(64, BigInt(val));
  
  const utf8Decoder = new TextDecoder();
  
  const utf8Encoder = new TextEncoder();
  let utf8EncodedLen = 0;
  function utf8Encode(s, realloc, memory) {
    if (typeof s !== 'string') throw new TypeError('expected a string');
    if (s.length === 0) {
      utf8EncodedLen = 0;
      return 1;
    }
    let buf = utf8Encoder.encode(s);
    let ptr = realloc(0, 0, 1, buf.length);
    new Uint8Array(memory.buffer).set(buf, ptr);
    utf8EncodedLen = buf.length;
    return ptr;
  }
  
  const T_FLAG = 1 << 30;
  
  function rscTableCreateOwn (table, rep) {
    const free = table[0] & ~T_FLAG;
    if (free === 0) {
      table.push(0);
      table.push(rep | T_FLAG);
      return (table.length >> 1) - 1;
    }
    table[0] = table[free << 1];
    table[free << 1] = 0;
    table[(free << 1) + 1] = rep | T_FLAG;
    return free;
  }
  
  function rscTableRemove (table, handle) {
    const scope = table[handle << 1];
    const val = table[(handle << 1) + 1];
    const own = (val & T_FLAG) !== 0;
    const rep = val & ~T_FLAG;
    if (val === 0 || (scope & T_FLAG) !== 0) throw new TypeError('Invalid handle');
    table[handle << 1] = table[0] | T_FLAG;
    table[0] = handle | T_FLAG;
    return { rep, scope, own };
  }
  
  let curResourceBorrows = [];
  
  let NEXT_TASK_ID = 0n;
  function startCurrentTask(componentIdx, isAsync, entryFnName) {
    _debugLog('[startCurrentTask()] args', { componentIdx, isAsync });
    if (componentIdx === undefined || componentIdx === null) {
      throw new Error('missing/invalid component instance index while starting task');
    }
    const tasks = ASYNC_TASKS_BY_COMPONENT_IDX.get(componentIdx);
    
    const nextId = ++NEXT_TASK_ID;
    const newTask = new AsyncTask({ id: nextId, componentIdx, isAsync, entryFnName });
    const newTaskMeta = { id: nextId, componentIdx, task: newTask };
    
    ASYNC_CURRENT_TASK_IDS.push(nextId);
    ASYNC_CURRENT_COMPONENT_IDXS.push(componentIdx);
    
    if (!tasks) {
      ASYNC_TASKS_BY_COMPONENT_IDX.set(componentIdx, [newTaskMeta]);
      return nextId;
    } else {
      tasks.push(newTaskMeta);
    }
    
    return nextId;
  }
  
  function endCurrentTask(componentIdx, taskId) {
    _debugLog('[endCurrentTask()] args', { componentIdx });
    componentIdx ??= ASYNC_CURRENT_COMPONENT_IDXS.at(-1);
    taskId ??= ASYNC_CURRENT_TASK_IDS.at(-1);
    if (componentIdx === undefined || componentIdx === null) {
      throw new Error('missing/invalid component instance index while ending current task');
    }
    const tasks = ASYNC_TASKS_BY_COMPONENT_IDX.get(componentIdx);
    if (!tasks || !Array.isArray(tasks)) {
      throw new Error('missing/invalid tasks for component instance while ending task');
    }
    if (tasks.length == 0) {
      throw new Error('no current task(s) for component instance while ending task');
    }
    
    if (taskId) {
      const last = tasks[tasks.length - 1];
      if (last.id !== taskId) {
        throw new Error('current task does not match expected task ID');
      }
    }
    
    ASYNC_CURRENT_TASK_IDS.pop();
    ASYNC_CURRENT_COMPONENT_IDXS.pop();
    
    return tasks.pop();
  }
  const ASYNC_TASKS_BY_COMPONENT_IDX = new Map();
  const ASYNC_CURRENT_TASK_IDS = [];
  const ASYNC_CURRENT_COMPONENT_IDXS = [];
  
  class AsyncTask {
    static State = {
      INITIAL: 'initial',
      CANCELLED: 'cancelled',
      CANCEL_PENDING: 'cancel-pending',
      CANCEL_DELIVERED: 'cancel-delivered',
      RESOLVED: 'resolved',
    }
    
    static BlockResult = {
      CANCELLED: 'block.cancelled',
      NOT_CANCELLED: 'block.not-cancelled',
    }
    
    #id;
    #componentIdx;
    #state;
    #isAsync;
    #onResolve = null;
    #entryFnName = null;
    #subtasks = [];
    #completionPromise = null;
    
    cancelled = false;
    requested = false;
    alwaysTaskReturn = false;
    
    returnCalls =  0;
    storage = [0, 0];
    borrowedHandles = {};
    
    awaitableResume = null;
    awaitableCancel = null;
    
    
    constructor(opts) {
      if (opts?.id === undefined) { throw new TypeError('missing task ID during task creation'); }
      this.#id = opts.id;
      if (opts?.componentIdx === undefined) {
        throw new TypeError('missing component id during task creation');
      }
      this.#componentIdx = opts.componentIdx;
      this.#state = AsyncTask.State.INITIAL;
      this.#isAsync = opts?.isAsync ?? false;
      this.#entryFnName = opts.entryFnName;
      
      const {
        promise: completionPromise,
        resolve: resolveCompletionPromise,
        reject: rejectCompletionPromise,
      } = Promise.withResolvers();
      this.#completionPromise = completionPromise;
      
      this.#onResolve = (results) => {
        // TODO: handle external facing cancellation (should likely be a rejection)
        resolveCompletionPromise(results);
      }
    }
    
    taskState() { return this.#state.slice(); }
    id() { return this.#id; }
    componentIdx() { return this.#componentIdx; }
    isAsync() { return this.#isAsync; }
    entryFnName() { return this.#entryFnName; }
    completionPromise() { return this.#completionPromise; }
    
    mayEnter(task) {
      const cstate = getOrCreateAsyncState(this.#componentIdx);
      if (!cstate.backpressure) {
        _debugLog('[AsyncTask#mayEnter()] disallowed due to backpressure', { taskID: this.#id });
        return false;
      }
      if (!cstate.callingSyncImport()) {
        _debugLog('[AsyncTask#mayEnter()] disallowed due to sync import call', { taskID: this.#id });
        return false;
      }
      const callingSyncExportWithSyncPending = cstate.callingSyncExport && !task.isAsync;
      if (!callingSyncExportWithSyncPending) {
        _debugLog('[AsyncTask#mayEnter()] disallowed due to sync export w/ sync pending', { taskID: this.#id });
        return false;
      }
      return true;
    }
    
    async enter() {
      _debugLog('[AsyncTask#enter()] args', { taskID: this.#id });
      
      // TODO: assert scheduler locked
      // TODO: trap if on the stack
      
      const cstate = getOrCreateAsyncState(this.#componentIdx);
      
      let mayNotEnter = !this.mayEnter(this);
      const componentHasPendingTasks = cstate.pendingTasks > 0;
      if (mayNotEnter || componentHasPendingTasks) {
        throw new Error('in enter()'); // TODO: remove
        cstate.pendingTasks.set(this.#id, new Awaitable(new Promise()));
        
        const blockResult = await this.onBlock(awaitable);
        if (blockResult) {
          // TODO: find this pending task in the component
          const pendingTask = cstate.pendingTasks.get(this.#id);
          if (!pendingTask) {
            throw new Error('pending task [' + this.#id + '] not found for component instance');
          }
          cstate.pendingTasks.remove(this.#id);
          this.#onResolve(new Error('failed enter'));
          return false;
        }
        
        mayNotEnter = !this.mayEnter(this);
        if (!mayNotEnter || !cstate.startPendingTask) {
          throw new Error('invalid component entrance/pending task resolution');
        }
        cstate.startPendingTask = false;
      }
      
      if (!this.isAsync) { cstate.callingSyncExport = true; }
      
      return true;
    }
    
    async waitForEvent(opts) {
      const { waitableSetRep, isAsync } = opts;
      _debugLog('[AsyncTask#waitForEvent()] args', { taskID: this.#id, waitableSetRep, isAsync });
      
      if (this.#isAsync !== isAsync) {
        throw new Error('async waitForEvent called on non-async task');
      }
      
      if (this.status === AsyncTask.State.CANCEL_PENDING) {
        this.#state = AsyncTask.State.CANCEL_DELIVERED;
        return {
          code: ASYNC_EVENT_CODE.TASK_CANCELLED,
        };
      }
      
      const state = getOrCreateAsyncState(this.#componentIdx);
      const waitableSet = state.waitableSets.get(waitableSetRep);
      if (!waitableSet) { throw new Error('missing/invalid waitable set'); }
      
      waitableSet.numWaiting += 1;
      let event = null;
      
      while (event == null) {
        const awaitable = new Awaitable(waitableSet.getPendingEvent());
        const waited = await this.blockOn({ awaitable, isAsync, isCancellable: true });
        if (waited) {
          if (this.#state !== AsyncTask.State.INITIAL) {
            throw new Error('task should be in initial state found [' + this.#state + ']');
          }
          this.#state = AsyncTask.State.CANCELLED;
          return {
            code: ASYNC_EVENT_CODE.TASK_CANCELLED,
          };
        }
        
        event = waitableSet.poll();
      }
      
      waitableSet.numWaiting -= 1;
      return event;
    }
    
    waitForEventSync(opts) {
      throw new Error('AsyncTask#yieldSync() not implemented')
    }
    
    async pollForEvent(opts) {
      const { waitableSetRep, isAsync } = opts;
      _debugLog('[AsyncTask#pollForEvent()] args', { taskID: this.#id, waitableSetRep, isAsync });
      
      if (this.#isAsync !== isAsync) {
        throw new Error('async pollForEvent called on non-async task');
      }
      
      throw new Error('AsyncTask#pollForEvent() not implemented');
    }
    
    pollForEventSync(opts) {
      throw new Error('AsyncTask#yieldSync() not implemented')
    }
    
    async blockOn(opts) {
      const { awaitable, isCancellable, forCallback } = opts;
      _debugLog('[AsyncTask#blockOn()] args', { taskID: this.#id, awaitable, isCancellable, forCallback });
      
      if (awaitable.resolved() && !ASYNC_DETERMINISM && _coinFlip()) {
        return AsyncTask.BlockResult.NOT_CANCELLED;
      }
      
      const cstate = getOrCreateAsyncState(this.#componentIdx);
      if (forCallback) { cstate.exclusiveRelease(); }
      
      let cancelled = await this.onBlock(awaitable);
      if (cancelled === AsyncTask.BlockResult.CANCELLED && !isCancellable) {
        const secondCancel = await this.onBlock(awaitable);
        if (secondCancel !== AsyncTask.BlockResult.NOT_CANCELLED) {
          throw new Error('uncancellable task was canceled despite second onBlock()');
        }
      }
      
      if (forCallback) {
        const acquired = new Awaitable(cstate.exclusiveLock());
        cancelled = await this.onBlock(acquired);
        if (cancelled === AsyncTask.BlockResult.CANCELLED) {
          const secondCancel = await this.onBlock(acquired);
          if (secondCancel !== AsyncTask.BlockResult.NOT_CANCELLED) {
            throw new Error('uncancellable callback task was canceled despite second onBlock()');
          }
        }
      }
      
      if (cancelled === AsyncTask.BlockResult.CANCELLED) {
        if (this.#state !== AsyncTask.State.INITIAL) {
          throw new Error('cancelled task is not at initial state');
        }
        if (isCancellable) {
          this.#state = AsyncTask.State.CANCELLED;
          return AsyncTask.BlockResult.CANCELLED;
        } else {
          this.#state = AsyncTask.State.CANCEL_PENDING;
          return AsyncTask.BlockResult.NOT_CANCELLED;
        }
      }
      
      return AsyncTask.BlockResult.NOT_CANCELLED;
    }
    
    async onBlock(awaitable) {
      _debugLog('[AsyncTask#onBlock()] args', { taskID: this.#id, awaitable });
      if (!(awaitable instanceof Awaitable)) {
        throw new Error('invalid awaitable during onBlock');
      }
      
      // Build a promise that this task can await on which resolves when it is awoken
      const { promise, resolve, reject } = Promise.withResolvers();
      this.awaitableResume = () => {
        _debugLog('[AsyncTask] resuming after onBlock', { taskID: this.#id });
        resolve();
      };
      this.awaitableCancel = (err) => {
        _debugLog('[AsyncTask] rejecting after onBlock', { taskID: this.#id, err });
        reject(err);
      };
      
      // Park this task/execution to be handled later
      const state = getOrCreateAsyncState(this.#componentIdx);
      state.parkTaskOnAwaitable({ awaitable, task: this });
      
      try {
        await promise;
        return AsyncTask.BlockResult.NOT_CANCELLED;
      } catch (err) {
        // rejection means task cancellation
        return AsyncTask.BlockResult.CANCELLED;
      }
    }
    
    async asyncOnBlock(awaitable) {
      _debugLog('[AsyncTask#asyncOnBlock()] args', { taskID: this.#id, awaitable });
      if (!(awaitable instanceof Awaitable)) {
        throw new Error('invalid awaitable during onBlock');
      }
      // TODO: watch for waitable AND cancellation
      // TODO: if it WAS cancelled:
      // - return true
      // - only once per subtask
      // - do not wait on the scheduler
      // - control flow should go to the subtask (only once)
      // - Once subtask blocks/resolves, reqlinquishControl() will tehn resolve request_cancel_end (without scheduler lock release)
      // - control flow goes back to request_cancel
      //
      // Subtask cancellation should work similarly to an async import call -- runs sync up until
      // the subtask blocks or resolves
      //
      throw new Error('AsyncTask#asyncOnBlock() not yet implemented');
    }
    
    async yield(opts) {
      const { isCancellable, forCallback } = opts;
      _debugLog('[AsyncTask#yield()] args', { taskID: this.#id, isCancellable, forCallback });
      
      if (isCancellable && this.status === AsyncTask.State.CANCEL_PENDING) {
        this.#state = AsyncTask.State.CANCELLED;
        return {
          code: ASYNC_EVENT_CODE.TASK_CANCELLED,
          payload: [0, 0],
        };
      }
      
      // TODO: Awaitables need to *always* trigger the parking mechanism when they're done...?
      // TODO: Component async state should remember which awaitables are done and work to clear tasks waiting
      
      const blockResult = await this.blockOn({
        awaitable: new Awaitable(new Promise(resolve => setTimeout(resolve, 0))),
        isCancellable,
        forCallback,
      });
      
      if (blockResult === AsyncTask.BlockResult.CANCELLED) {
        if (this.#state !== AsyncTask.State.INITIAL) {
          throw new Error('task should be in initial state found [' + this.#state + ']');
        }
        this.#state = AsyncTask.State.CANCELLED;
        return {
          code: ASYNC_EVENT_CODE.TASK_CANCELLED,
          payload: [0, 0],
        };
      }
      
      return {
        code: ASYNC_EVENT_CODE.NONE,
        payload: [0, 0],
      };
    }
    
    yieldSync(opts) {
      throw new Error('AsyncTask#yieldSync() not implemented')
    }
    
    cancel() {
      _debugLog('[AsyncTask#cancel()] args', { });
      if (!this.taskState() !== AsyncTask.State.CANCEL_DELIVERED) {
        throw new Error('invalid task state for cancellation');
      }
      if (this.borrowedHandles.length > 0) { throw new Error('task still has borrow handles'); }
      
      this.#onResolve(new Error('cancelled'));
      this.#state = AsyncTask.State.RESOLVED;
    }
    
    resolve(results) {
      _debugLog('[AsyncTask#resolve()] args', { results });
      if (this.#state === AsyncTask.State.RESOLVED) {
        throw new Error('task is already resolved');
      }
      if (this.borrowedHandles.length > 0) { throw new Error('task still has borrow handles'); }
      this.#onResolve(results.length === 1 ? results[0] : results);
      this.#state = AsyncTask.State.RESOLVED;
    }
    
    exit() {
      _debugLog('[AsyncTask#exit()] args', { });
      
      // TODO: ensure there is only one task at a time (scheduler.lock() functionality)
      if (this.#state !== AsyncTask.State.RESOLVED) {
        throw new Error('task exited without resolution');
      }
      if (this.borrowedHandles > 0) {
        throw new Error('task exited without clearing borrowed handles');
      }
      
      const state = getOrCreateAsyncState(this.#componentIdx);
      if (!state) { throw new Error('missing async state for component [' + this.#componentIdx + ']'); }
      if (!this.#isAsync && !state.inSyncExportCall) {
        throw new Error('sync task must be run from components known to be in a sync export call');
      }
      state.inSyncExportCall = false;
      
      this.startPendingTask();
    }
    
    startPendingTask(args) {
      _debugLog('[AsyncTask#startPendingTask()] args', args);
      throw new Error('AsyncTask#startPendingTask() not implemented');
    }
    
    createSubtask(args) {
      _debugLog('[AsyncTask#createSubtask()] args', args);
      const newSubtask = new AsyncSubtask({
        componentIdx: this.componentIdx(),
        taskID: this.id(),
        memoryIdx: args?.memoryIdx,
      });
      this.#subtasks.push(newSubtask);
      return newSubtask;
    }
    
    currentSubtask() {
      _debugLog('[AsyncTask#currentSubtask()]');
      if (this.#subtasks.length === 0) { throw new Error('no current subtask'); }
      return this.#subtasks.at(-1);
    }
    
    endCurrentSubtask() {
      _debugLog('[AsyncTask#endCurrentSubtask()]');
      if (this.#subtasks.length === 0) { throw new Error('cannot end current subtask: no current subtask'); }
      const subtask = this.#subtasks.pop();
      subtask.drop();
      return subtask;
    }
  }
  
  function unpackCallbackResult(result) {
    _debugLog('[unpackCallbackResult()] args', { result });
    if (!(_typeCheckValidI32(result))) { throw new Error('invalid callback return value [' + result + '], not a valid i32'); }
    const eventCode = result & 0xF;
    if (eventCode < 0 || eventCode > 3) {
      throw new Error('invalid async return value [' + eventCode + '], outside callback code range');
    }
    if (result < 0 || result >= 2**32) { throw new Error('invalid callback result'); }
    // TODO: table max length check?
    const waitableSetIdx = result >> 4;
    return [eventCode, waitableSetIdx];
  }
  const ASYNC_STATE = new Map();
  
  function getOrCreateAsyncState(componentIdx, init) {
    if (!ASYNC_STATE.has(componentIdx)) {
      ASYNC_STATE.set(componentIdx, new ComponentAsyncState());
    }
    return ASYNC_STATE.get(componentIdx);
  }
  
  class ComponentAsyncState {
    #callingAsyncImport = false;
    #syncImportWait = Promise.withResolvers();
    #lock = null;
    
    mayLeave = true;
    waitableSets = new RepTable();
    waitables = new RepTable();
    
    #parkedTasks = new Map();
    
    callingSyncImport(val) {
      if (val === undefined) { return this.#callingAsyncImport; }
      if (typeof val !== 'boolean') { throw new TypeError('invalid setting for async import'); }
      const prev = this.#callingAsyncImport;
      this.#callingAsyncImport = val;
      if (prev === true && this.#callingAsyncImport === false) {
        this.#notifySyncImportEnd();
      }
    }
    
    #notifySyncImportEnd() {
      const existing = this.#syncImportWait;
      this.#syncImportWait = Promise.withResolvers();
      existing.resolve();
    }
    
    async waitForSyncImportCallEnd() {
      await this.#syncImportWait.promise;
    }
    
    parkTaskOnAwaitable(args) {
      if (!args.awaitable) { throw new TypeError('missing awaitable when trying to park'); }
      if (!args.task) { throw new TypeError('missing task when trying to park'); }
      const { awaitable, task } = args;
      
      let taskList = this.#parkedTasks.get(awaitable.id());
      if (!taskList) {
        taskList = [];
        this.#parkedTasks.set(awaitable.id(), taskList);
      }
      taskList.push(task);
      
      this.wakeNextTaskForAwaitable(awaitable);
    }
    
    wakeNextTaskForAwaitable(awaitable) {
      if (!awaitable) { throw new TypeError('missing awaitable when waking next task'); }
      const awaitableID = awaitable.id();
      
      const taskList = this.#parkedTasks.get(awaitableID);
      if (!taskList || taskList.length === 0) {
        _debugLog('[ComponentAsyncState] no tasks waiting for awaitable', { awaitableID: awaitable.id() });
        return;
      }
      
      let task = taskList.shift(); // todo(perf)
      if (!task) { throw new Error('no task in parked list despite previous check'); }
      
      if (!task.awaitableResume) {
        throw new Error('task ready due to awaitable is missing resume', { taskID: task.id(), awaitableID });
      }
      task.awaitableResume();
    }
    
    async exclusiveLock() {  // TODO: use atomics
    if (this.#lock === null) {
      this.#lock = { ticket: 0n };
    }
    
    // Take a ticket for the next valid usage
    const ticket = ++this.#lock.ticket;
    
    _debugLog('[ComponentAsyncState#exclusiveLock()] locking', {
      currentTicket: ticket - 1n,
      ticket
    });
    
    // If there is an active promise, then wait for it
    let finishedTicket;
    while (this.#lock.promise) {
      finishedTicket = await this.#lock.promise;
      if (finishedTicket === ticket - 1n) { break; }
    }
    
    const { promise, resolve } = Promise.withResolvers();
    this.#lock = {
      ticket,
      promise,
      resolve,
    };
    
    return this.#lock.promise;
  }
  
  exclusiveRelease() {
    _debugLog('[ComponentAsyncState#exclusiveRelease()] releasing', {
      currentTicket: this.#lock === null ? 'none' : this.#lock.ticket,
    });
    
    if (this.#lock === null) { return; }
    
    const existingLock = this.#lock;
    this.#lock = null;
    existingLock.resolve(existingLock.ticket);
  }
  
  isExclusivelyLocked() { return this.#lock !== null; }
  
}

function prepareCall(memoryIdx) {
  _debugLog('[prepareCall()] args', { memoryIdx });
  
  const taskMeta = getCurrentTask(ASYNC_CURRENT_COMPONENT_IDXS.at(-1), ASYNC_CURRENT_TASK_IDS.at(-1));
  if (!taskMeta) { throw new Error('invalid/missing current async task meta during prepare call'); }
  
  const task = taskMeta.task;
  if (!task) { throw new Error('unexpectedly missing task in task meta during prepare call'); }
  
  const state = getOrCreateAsyncState(task.componentIdx());
  if (!state) {
    throw new Error('invalid/missing async state for component instance [' + componentInstanceID + ']');
  }
  
  const subtask = task.createSubtask({
    memoryIdx,
  });
  
}

function asyncStartCall(callbackIdx, postReturnIdx) {
  _debugLog('[asyncStartCall()] args', { callbackIdx, postReturnIdx });
  
  const taskMeta = getCurrentTask(ASYNC_CURRENT_COMPONENT_IDXS.at(-1), ASYNC_CURRENT_TASK_IDS.at(-1));
  if (!taskMeta) { throw new Error('invalid/missing current async task meta during prepare call'); }
  
  const task = taskMeta.task;
  if (!task) { throw new Error('unexpectedly missing task in task meta during prepare call'); }
  
  const subtask = task.currentSubtask();
  if (!subtask) { throw new Error('invalid/missing subtask during async start call'); }
  
  return Number(subtask.waitableRep()) << 4 | subtask.getStateNumber();
}

function syncStartCall(callbackIdx) {
  _debugLog('[syncStartCall()] args', { callbackIdx });
}

if (!Promise.withResolvers) {
  Promise.withResolvers = () => {
    let resolve;
    let reject;
    const promise = new Promise((res, rej) => {
      resolve = res;
      reject = rej;
    });
    return { promise, resolve, reject };
  };
}

const _debugLog = (...args) => {
  if (!globalThis?.process?.env?.JCO_DEBUG) { return; }
  console.debug(...args);
}
const ASYNC_DETERMINISM = 'random';
const _coinFlip = () => { return Math.random() > 0.5; };
const I32_MAX = 2_147_483_647;
const I32_MIN = -2_147_483_648;
const _typeCheckValidI32 = (n) => typeof n === 'number' && n >= I32_MIN && n <= I32_MAX;

const isNode = typeof process !== 'undefined' && process.versions && process.versions.node;
let _fs;
async function fetchCompile (url) {
  if (isNode) {
    _fs = _fs || await import('node:fs/promises');
    return WebAssembly.compile(await _fs.readFile(url));
  }
  return fetch(url).then(WebAssembly.compileStreaming);
}

const symbolRscHandle = Symbol('handle');

const symbolRscRep = Symbol.for('cabiRep');

const symbolDispose = Symbol.dispose || Symbol.for('dispose');

const handleTables = [];

class ComponentError extends Error {
  constructor (value) {
    const enumerable = typeof value !== 'string';
    super(enumerable ? `${String(value)} (see error.payload)` : value);
    Object.defineProperty(this, 'payload', { value, enumerable });
  }
}

function getErrorPayload(e) {
  if (e && hasOwnProperty.call(e, 'payload')) return e.payload;
  if (e instanceof Error) throw e;
  return e;
}

class RepTable {
  #data = [0, null];
  
  insert(val) {
    _debugLog('[RepTable#insert()] args', { val });
    const freeIdx = this.#data[0];
    if (freeIdx === 0) {
      this.#data.push(val);
      this.#data.push(null);
      return (this.#data.length >> 1) - 1;
    }
    this.#data[0] = this.#data[freeIdx << 1];
    const placementIdx = freeIdx << 1;
    this.#data[placementIdx] = val;
    this.#data[placementIdx + 1] = null;
    return freeIdx;
  }
  
  get(rep) {
    _debugLog('[RepTable#get()] args', { rep });
    const baseIdx = rep << 1;
    const val = this.#data[baseIdx];
    return val;
  }
  
  contains(rep) {
    _debugLog('[RepTable#contains()] args', { rep });
    const baseIdx = rep << 1;
    return !!this.#data[baseIdx];
  }
  
  remove(rep) {
    _debugLog('[RepTable#remove()] args', { rep });
    if (this.#data.length === 2) { throw new Error('invalid'); }
    
    const baseIdx = rep << 1;
    const val = this.#data[baseIdx];
    if (val === 0) { throw new Error('invalid resource rep (cannot be 0)'); }
    
    this.#data[baseIdx] = this.#data[0];
    this.#data[0] = rep;
    
    return val;
  }
  
  clear() {
    _debugLog('[RepTable#clear()] args', { rep });
    this.#data = [0, null];
  }
}

const hasOwnProperty = Object.prototype.hasOwnProperty;


if (!getCoreModule) getCoreModule = (name) => fetchCompile(new URL(`./${name}`, import.meta.url));
const module0 = getCoreModule('component.core.wasm');
const module1 = getCoreModule('component.core2.wasm');
const module2 = getCoreModule('component.core3.wasm');

const { stdout } = imports['../../deno_host/virtual_cli.ts'];
const { preopens, types } = imports['../../deno_host/virtual_fs.ts'];
const { error, streams } = imports['../../deno_host/virtual_io.ts'];
const { getStdout } = stdout;
const { getDirectories } = preopens;
const { Descriptor } = types;
const { Error: Error$1 } = error;
const { OutputStream } = streams;
let gen = (function* _initGenerator () {
  let exports0;
  const handleTable1 = [T_FLAG, 0];
  const captureTable1= new Map();
  let captureCnt1 = 0;
  handleTables[1] = handleTable1;
  
  function trampoline0() {
    _debugLog('[iface="wasi:cli/stdout@0.2.9", function="get-stdout"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-stdout');
    const ret = getStdout();
    _debugLog('[iface="wasi:cli/stdout@0.2.9", function="get-stdout"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    if (!(ret instanceof OutputStream)) {
      throw new TypeError('Resource error: Not a valid "OutputStream" resource.');
    }
    var handle0 = ret[symbolRscHandle];
    if (!handle0) {
      const rep = ret[symbolRscRep] || ++captureCnt1;
      captureTable1.set(rep, ret);
      handle0 = rscTableCreateOwn(handleTable1, rep);
    }
    _debugLog('[iface="wasi:cli/stdout@0.2.9", function="get-stdout"][Instruction::Return]', {
      funcName: 'get-stdout',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return handle0;
  }
  
  let exports1;
  let memory0;
  let realloc0;
  const handleTable2 = [T_FLAG, 0];
  const captureTable2= new Map();
  let captureCnt2 = 0;
  handleTables[2] = handleTable2;
  
  function trampoline1(arg0) {
    _debugLog('[iface="wasi:filesystem/preopens@0.2.9", function="get-directories"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-directories');
    const ret = getDirectories();
    _debugLog('[iface="wasi:filesystem/preopens@0.2.9", function="get-directories"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var vec3 = ret;
    var len3 = vec3.length;
    var result3 = realloc0(0, 0, 4, len3 * 12);
    for (let i = 0; i < vec3.length; i++) {
      const e = vec3[i];
      const base = result3 + i * 12;var [tuple0_0, tuple0_1] = e;
      if (!(tuple0_0 instanceof Descriptor)) {
        throw new TypeError('Resource error: Not a valid "Descriptor" resource.');
      }
      var handle1 = tuple0_0[symbolRscHandle];
      if (!handle1) {
        const rep = tuple0_0[symbolRscRep] || ++captureCnt2;
        captureTable2.set(rep, tuple0_0);
        handle1 = rscTableCreateOwn(handleTable2, rep);
      }
      dataView(memory0).setInt32(base + 0, handle1, true);
      var ptr2 = utf8Encode(tuple0_1, realloc0, memory0);
      var len2 = utf8EncodedLen;
      dataView(memory0).setUint32(base + 8, len2, true);
      dataView(memory0).setUint32(base + 4, ptr2, true);
    }
    dataView(memory0).setUint32(arg0 + 4, len3, true);
    dataView(memory0).setUint32(arg0 + 0, result3, true);
    _debugLog('[iface="wasi:filesystem/preopens@0.2.9", function="get-directories"][Instruction::Return]', {
      funcName: 'get-directories',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline2(arg0, arg1, arg2, arg3, arg4) {
    var handle1 = arg0;
    var rep2 = handleTable2[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable2.get(rep2);
    if (!rsc0) {
      rsc0 = Object.create(Descriptor.prototype);
      Object.defineProperty(rsc0, symbolRscHandle, { writable: true, value: handle1});
      Object.defineProperty(rsc0, symbolRscRep, { writable: true, value: rep2});
    }
    curResourceBorrows.push(rsc0);
    var ptr3 = arg1;
    var len3 = arg2;
    var result3 = new Uint8Array(memory0.buffer.slice(ptr3, ptr3 + len3 * 1));
    _debugLog('[iface="wasi:filesystem/types@0.2.9", function="[method]descriptor.write"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, '[method]descriptor.write');
    let ret;
    try {
      ret = { tag: 'ok', val: rsc0.write(result3, BigInt.asUintN(64, arg3))};
    } catch (e) {
      ret = { tag: 'err', val: getErrorPayload(e) };
    }
    _debugLog('[iface="wasi:filesystem/types@0.2.9", function="[method]descriptor.write"] [Instruction::CallInterface] (sync, @ post-call)');
    for (const rsc of curResourceBorrows) {
      rsc[symbolRscHandle] = undefined;
    }
    curResourceBorrows = [];
    endCurrentTask(0);
    var variant5 = ret;
    switch (variant5.tag) {
      case 'ok': {
        const e = variant5.val;
        dataView(memory0).setInt8(arg4 + 0, 0, true);
        dataView(memory0).setBigInt64(arg4 + 8, toUint64(e), true);
        break;
      }
      case 'err': {
        const e = variant5.val;
        dataView(memory0).setInt8(arg4 + 0, 1, true);
        var val4 = e;
        let enum4;
        switch (val4) {
          case 'access': {
            enum4 = 0;
            break;
          }
          case 'would-block': {
            enum4 = 1;
            break;
          }
          case 'already': {
            enum4 = 2;
            break;
          }
          case 'bad-descriptor': {
            enum4 = 3;
            break;
          }
          case 'busy': {
            enum4 = 4;
            break;
          }
          case 'deadlock': {
            enum4 = 5;
            break;
          }
          case 'quota': {
            enum4 = 6;
            break;
          }
          case 'exist': {
            enum4 = 7;
            break;
          }
          case 'file-too-large': {
            enum4 = 8;
            break;
          }
          case 'illegal-byte-sequence': {
            enum4 = 9;
            break;
          }
          case 'in-progress': {
            enum4 = 10;
            break;
          }
          case 'interrupted': {
            enum4 = 11;
            break;
          }
          case 'invalid': {
            enum4 = 12;
            break;
          }
          case 'io': {
            enum4 = 13;
            break;
          }
          case 'is-directory': {
            enum4 = 14;
            break;
          }
          case 'loop': {
            enum4 = 15;
            break;
          }
          case 'too-many-links': {
            enum4 = 16;
            break;
          }
          case 'message-size': {
            enum4 = 17;
            break;
          }
          case 'name-too-long': {
            enum4 = 18;
            break;
          }
          case 'no-device': {
            enum4 = 19;
            break;
          }
          case 'no-entry': {
            enum4 = 20;
            break;
          }
          case 'no-lock': {
            enum4 = 21;
            break;
          }
          case 'insufficient-memory': {
            enum4 = 22;
            break;
          }
          case 'insufficient-space': {
            enum4 = 23;
            break;
          }
          case 'not-directory': {
            enum4 = 24;
            break;
          }
          case 'not-empty': {
            enum4 = 25;
            break;
          }
          case 'not-recoverable': {
            enum4 = 26;
            break;
          }
          case 'unsupported': {
            enum4 = 27;
            break;
          }
          case 'no-tty': {
            enum4 = 28;
            break;
          }
          case 'no-such-device': {
            enum4 = 29;
            break;
          }
          case 'overflow': {
            enum4 = 30;
            break;
          }
          case 'not-permitted': {
            enum4 = 31;
            break;
          }
          case 'pipe': {
            enum4 = 32;
            break;
          }
          case 'read-only': {
            enum4 = 33;
            break;
          }
          case 'invalid-seek': {
            enum4 = 34;
            break;
          }
          case 'text-file-busy': {
            enum4 = 35;
            break;
          }
          case 'cross-device': {
            enum4 = 36;
            break;
          }
          default: {
            if ((e) instanceof Error) {
              console.error(e);
            }
            
            throw new TypeError(`"${val4}" is not one of the cases of error-code`);
          }
        }
        dataView(memory0).setInt8(arg4 + 8, enum4, true);
        break;
      }
      default: {
        throw new TypeError('invalid variant specified for result');
      }
    }
    _debugLog('[iface="wasi:filesystem/types@0.2.9", function="[method]descriptor.write"][Instruction::Return]', {
      funcName: '[method]descriptor.write',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline3(arg0, arg1, arg2, arg3) {
    var handle1 = arg0;
    var rep2 = handleTable2[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable2.get(rep2);
    if (!rsc0) {
      rsc0 = Object.create(Descriptor.prototype);
      Object.defineProperty(rsc0, symbolRscHandle, { writable: true, value: handle1});
      Object.defineProperty(rsc0, symbolRscRep, { writable: true, value: rep2});
    }
    curResourceBorrows.push(rsc0);
    _debugLog('[iface="wasi:filesystem/types@0.2.9", function="[method]descriptor.read"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, '[method]descriptor.read');
    let ret;
    try {
      ret = { tag: 'ok', val: rsc0.read(BigInt.asUintN(64, arg1), BigInt.asUintN(64, arg2))};
    } catch (e) {
      ret = { tag: 'err', val: getErrorPayload(e) };
    }
    _debugLog('[iface="wasi:filesystem/types@0.2.9", function="[method]descriptor.read"] [Instruction::CallInterface] (sync, @ post-call)');
    for (const rsc of curResourceBorrows) {
      rsc[symbolRscHandle] = undefined;
    }
    curResourceBorrows = [];
    endCurrentTask(0);
    var variant6 = ret;
    switch (variant6.tag) {
      case 'ok': {
        const e = variant6.val;
        dataView(memory0).setInt8(arg3 + 0, 0, true);
        var [tuple3_0, tuple3_1] = e;
        var val4 = tuple3_0;
        var len4 = val4.byteLength;
        var ptr4 = realloc0(0, 0, 1, len4 * 1);
        var src4 = new Uint8Array(val4.buffer || val4, val4.byteOffset, len4 * 1);
        (new Uint8Array(memory0.buffer, ptr4, len4 * 1)).set(src4);
        dataView(memory0).setUint32(arg3 + 8, len4, true);
        dataView(memory0).setUint32(arg3 + 4, ptr4, true);
        dataView(memory0).setInt8(arg3 + 12, tuple3_1 ? 1 : 0, true);
        break;
      }
      case 'err': {
        const e = variant6.val;
        dataView(memory0).setInt8(arg3 + 0, 1, true);
        var val5 = e;
        let enum5;
        switch (val5) {
          case 'access': {
            enum5 = 0;
            break;
          }
          case 'would-block': {
            enum5 = 1;
            break;
          }
          case 'already': {
            enum5 = 2;
            break;
          }
          case 'bad-descriptor': {
            enum5 = 3;
            break;
          }
          case 'busy': {
            enum5 = 4;
            break;
          }
          case 'deadlock': {
            enum5 = 5;
            break;
          }
          case 'quota': {
            enum5 = 6;
            break;
          }
          case 'exist': {
            enum5 = 7;
            break;
          }
          case 'file-too-large': {
            enum5 = 8;
            break;
          }
          case 'illegal-byte-sequence': {
            enum5 = 9;
            break;
          }
          case 'in-progress': {
            enum5 = 10;
            break;
          }
          case 'interrupted': {
            enum5 = 11;
            break;
          }
          case 'invalid': {
            enum5 = 12;
            break;
          }
          case 'io': {
            enum5 = 13;
            break;
          }
          case 'is-directory': {
            enum5 = 14;
            break;
          }
          case 'loop': {
            enum5 = 15;
            break;
          }
          case 'too-many-links': {
            enum5 = 16;
            break;
          }
          case 'message-size': {
            enum5 = 17;
            break;
          }
          case 'name-too-long': {
            enum5 = 18;
            break;
          }
          case 'no-device': {
            enum5 = 19;
            break;
          }
          case 'no-entry': {
            enum5 = 20;
            break;
          }
          case 'no-lock': {
            enum5 = 21;
            break;
          }
          case 'insufficient-memory': {
            enum5 = 22;
            break;
          }
          case 'insufficient-space': {
            enum5 = 23;
            break;
          }
          case 'not-directory': {
            enum5 = 24;
            break;
          }
          case 'not-empty': {
            enum5 = 25;
            break;
          }
          case 'not-recoverable': {
            enum5 = 26;
            break;
          }
          case 'unsupported': {
            enum5 = 27;
            break;
          }
          case 'no-tty': {
            enum5 = 28;
            break;
          }
          case 'no-such-device': {
            enum5 = 29;
            break;
          }
          case 'overflow': {
            enum5 = 30;
            break;
          }
          case 'not-permitted': {
            enum5 = 31;
            break;
          }
          case 'pipe': {
            enum5 = 32;
            break;
          }
          case 'read-only': {
            enum5 = 33;
            break;
          }
          case 'invalid-seek': {
            enum5 = 34;
            break;
          }
          case 'text-file-busy': {
            enum5 = 35;
            break;
          }
          case 'cross-device': {
            enum5 = 36;
            break;
          }
          default: {
            if ((e) instanceof Error) {
              console.error(e);
            }
            
            throw new TypeError(`"${val5}" is not one of the cases of error-code`);
          }
        }
        dataView(memory0).setInt8(arg3 + 4, enum5, true);
        break;
      }
      default: {
        throw new TypeError('invalid variant specified for result');
      }
    }
    _debugLog('[iface="wasi:filesystem/types@0.2.9", function="[method]descriptor.read"][Instruction::Return]', {
      funcName: '[method]descriptor.read',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline4(arg0, arg1, arg2, arg3, arg4, arg5, arg6) {
    var handle1 = arg0;
    var rep2 = handleTable2[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable2.get(rep2);
    if (!rsc0) {
      rsc0 = Object.create(Descriptor.prototype);
      Object.defineProperty(rsc0, symbolRscHandle, { writable: true, value: handle1});
      Object.defineProperty(rsc0, symbolRscRep, { writable: true, value: rep2});
    }
    curResourceBorrows.push(rsc0);
    if ((arg1 & 4294967294) !== 0) {
      throw new TypeError('flags have extraneous bits set');
    }
    var flags3 = {
      symlinkFollow: Boolean(arg1 & 1),
    };
    var ptr4 = arg2;
    var len4 = arg3;
    var result4 = utf8Decoder.decode(new Uint8Array(memory0.buffer, ptr4, len4));
    if ((arg4 & 4294967280) !== 0) {
      throw new TypeError('flags have extraneous bits set');
    }
    var flags5 = {
      create: Boolean(arg4 & 1),
      directory: Boolean(arg4 & 2),
      exclusive: Boolean(arg4 & 4),
      truncate: Boolean(arg4 & 8),
    };
    if ((arg5 & 4294967232) !== 0) {
      throw new TypeError('flags have extraneous bits set');
    }
    var flags6 = {
      read: Boolean(arg5 & 1),
      write: Boolean(arg5 & 2),
      fileIntegritySync: Boolean(arg5 & 4),
      dataIntegritySync: Boolean(arg5 & 8),
      requestedWriteSync: Boolean(arg5 & 16),
      mutateDirectory: Boolean(arg5 & 32),
    };
    _debugLog('[iface="wasi:filesystem/types@0.2.9", function="[method]descriptor.open-at"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, '[method]descriptor.open-at');
    let ret;
    try {
      ret = { tag: 'ok', val: rsc0.openAt(flags3, result4, flags5, flags6)};
    } catch (e) {
      ret = { tag: 'err', val: getErrorPayload(e) };
    }
    _debugLog('[iface="wasi:filesystem/types@0.2.9", function="[method]descriptor.open-at"] [Instruction::CallInterface] (sync, @ post-call)');
    for (const rsc of curResourceBorrows) {
      rsc[symbolRscHandle] = undefined;
    }
    curResourceBorrows = [];
    endCurrentTask(0);
    var variant9 = ret;
    switch (variant9.tag) {
      case 'ok': {
        const e = variant9.val;
        dataView(memory0).setInt8(arg6 + 0, 0, true);
        if (!(e instanceof Descriptor)) {
          throw new TypeError('Resource error: Not a valid "Descriptor" resource.');
        }
        var handle7 = e[symbolRscHandle];
        if (!handle7) {
          const rep = e[symbolRscRep] || ++captureCnt2;
          captureTable2.set(rep, e);
          handle7 = rscTableCreateOwn(handleTable2, rep);
        }
        dataView(memory0).setInt32(arg6 + 4, handle7, true);
        break;
      }
      case 'err': {
        const e = variant9.val;
        dataView(memory0).setInt8(arg6 + 0, 1, true);
        var val8 = e;
        let enum8;
        switch (val8) {
          case 'access': {
            enum8 = 0;
            break;
          }
          case 'would-block': {
            enum8 = 1;
            break;
          }
          case 'already': {
            enum8 = 2;
            break;
          }
          case 'bad-descriptor': {
            enum8 = 3;
            break;
          }
          case 'busy': {
            enum8 = 4;
            break;
          }
          case 'deadlock': {
            enum8 = 5;
            break;
          }
          case 'quota': {
            enum8 = 6;
            break;
          }
          case 'exist': {
            enum8 = 7;
            break;
          }
          case 'file-too-large': {
            enum8 = 8;
            break;
          }
          case 'illegal-byte-sequence': {
            enum8 = 9;
            break;
          }
          case 'in-progress': {
            enum8 = 10;
            break;
          }
          case 'interrupted': {
            enum8 = 11;
            break;
          }
          case 'invalid': {
            enum8 = 12;
            break;
          }
          case 'io': {
            enum8 = 13;
            break;
          }
          case 'is-directory': {
            enum8 = 14;
            break;
          }
          case 'loop': {
            enum8 = 15;
            break;
          }
          case 'too-many-links': {
            enum8 = 16;
            break;
          }
          case 'message-size': {
            enum8 = 17;
            break;
          }
          case 'name-too-long': {
            enum8 = 18;
            break;
          }
          case 'no-device': {
            enum8 = 19;
            break;
          }
          case 'no-entry': {
            enum8 = 20;
            break;
          }
          case 'no-lock': {
            enum8 = 21;
            break;
          }
          case 'insufficient-memory': {
            enum8 = 22;
            break;
          }
          case 'insufficient-space': {
            enum8 = 23;
            break;
          }
          case 'not-directory': {
            enum8 = 24;
            break;
          }
          case 'not-empty': {
            enum8 = 25;
            break;
          }
          case 'not-recoverable': {
            enum8 = 26;
            break;
          }
          case 'unsupported': {
            enum8 = 27;
            break;
          }
          case 'no-tty': {
            enum8 = 28;
            break;
          }
          case 'no-such-device': {
            enum8 = 29;
            break;
          }
          case 'overflow': {
            enum8 = 30;
            break;
          }
          case 'not-permitted': {
            enum8 = 31;
            break;
          }
          case 'pipe': {
            enum8 = 32;
            break;
          }
          case 'read-only': {
            enum8 = 33;
            break;
          }
          case 'invalid-seek': {
            enum8 = 34;
            break;
          }
          case 'text-file-busy': {
            enum8 = 35;
            break;
          }
          case 'cross-device': {
            enum8 = 36;
            break;
          }
          default: {
            if ((e) instanceof Error) {
              console.error(e);
            }
            
            throw new TypeError(`"${val8}" is not one of the cases of error-code`);
          }
        }
        dataView(memory0).setInt8(arg6 + 4, enum8, true);
        break;
      }
      default: {
        throw new TypeError('invalid variant specified for result');
      }
    }
    _debugLog('[iface="wasi:filesystem/types@0.2.9", function="[method]descriptor.open-at"][Instruction::Return]', {
      funcName: '[method]descriptor.open-at',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  const handleTable0 = [T_FLAG, 0];
  const captureTable0= new Map();
  let captureCnt0 = 0;
  handleTables[0] = handleTable0;
  
  function trampoline5(arg0, arg1, arg2, arg3) {
    var handle1 = arg0;
    var rep2 = handleTable1[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable1.get(rep2);
    if (!rsc0) {
      rsc0 = Object.create(OutputStream.prototype);
      Object.defineProperty(rsc0, symbolRscHandle, { writable: true, value: handle1});
      Object.defineProperty(rsc0, symbolRscRep, { writable: true, value: rep2});
    }
    curResourceBorrows.push(rsc0);
    var ptr3 = arg1;
    var len3 = arg2;
    var result3 = new Uint8Array(memory0.buffer.slice(ptr3, ptr3 + len3 * 1));
    _debugLog('[iface="wasi:io/streams@0.2.9", function="[method]output-stream.blocking-write-and-flush"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, '[method]output-stream.blocking-write-and-flush');
    let ret;
    try {
      ret = { tag: 'ok', val: rsc0.blockingWriteAndFlush(result3)};
    } catch (e) {
      ret = { tag: 'err', val: getErrorPayload(e) };
    }
    _debugLog('[iface="wasi:io/streams@0.2.9", function="[method]output-stream.blocking-write-and-flush"] [Instruction::CallInterface] (sync, @ post-call)');
    for (const rsc of curResourceBorrows) {
      rsc[symbolRscHandle] = undefined;
    }
    curResourceBorrows = [];
    endCurrentTask(0);
    var variant6 = ret;
    switch (variant6.tag) {
      case 'ok': {
        const e = variant6.val;
        dataView(memory0).setInt8(arg3 + 0, 0, true);
        break;
      }
      case 'err': {
        const e = variant6.val;
        dataView(memory0).setInt8(arg3 + 0, 1, true);
        var variant5 = e;
        switch (variant5.tag) {
          case 'last-operation-failed': {
            const e = variant5.val;
            dataView(memory0).setInt8(arg3 + 4, 0, true);
            if (!(e instanceof Error$1)) {
              throw new TypeError('Resource error: Not a valid "Error" resource.');
            }
            var handle4 = e[symbolRscHandle];
            if (!handle4) {
              const rep = e[symbolRscRep] || ++captureCnt0;
              captureTable0.set(rep, e);
              handle4 = rscTableCreateOwn(handleTable0, rep);
            }
            dataView(memory0).setInt32(arg3 + 8, handle4, true);
            break;
          }
          case 'closed': {
            dataView(memory0).setInt8(arg3 + 4, 1, true);
            break;
          }
          default: {
            throw new TypeError(`invalid variant tag value \`${JSON.stringify(variant5.tag)}\` (received \`${variant5}\`) specified for \`StreamError\``);
          }
        }
        break;
      }
      default: {
        throw new TypeError('invalid variant specified for result');
      }
    }
    _debugLog('[iface="wasi:io/streams@0.2.9", function="[method]output-stream.blocking-write-and-flush"][Instruction::Return]', {
      funcName: '[method]output-stream.blocking-write-and-flush',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  let exports2;
  Promise.all([module0, module1, module2]).catch(() => {});
  ({ exports: exports0 } = yield instantiateCore(yield module1));
  ({ exports: exports1 } = yield instantiateCore(yield module0, {
    'wasi:cli/stdout@0.2.9': {
      'get-stdout': trampoline0,
    },
    'wasi:filesystem/preopens@0.2.9': {
      'get-directories': exports0['0'],
    },
    'wasi:filesystem/types@0.2.9': {
      '[method]descriptor.open-at': exports0['3'],
      '[method]descriptor.read': exports0['2'],
      '[method]descriptor.write': exports0['1'],
    },
    'wasi:io/streams@0.2.9': {
      '[method]output-stream.blocking-write-and-flush': exports0['4'],
    },
  }));
  memory0 = exports1.memory;
  realloc0 = exports1.cabi_realloc;
  ({ exports: exports2 } = yield instantiateCore(yield module2, {
    '': {
      $imports: exports0.$imports,
      '0': trampoline1,
      '1': trampoline2,
      '2': trampoline3,
      '3': trampoline4,
      '4': trampoline5,
    },
  }));
  let run029Run;
  
  function run() {
    _debugLog('[iface="wasi:cli/run@0.2.9", function="run"][Instruction::CallWasm] enter', {
      funcName: 'run',
      paramCount: 0,
      async: false,
      postReturn: false,
    });
    const _wasm_call_currentTaskID = startCurrentTask(0, false, 'run029Run');
    const ret = run029Run();
    endCurrentTask(0);
    let variant0;
    switch (ret) {
      case 0: {
        variant0= {
          tag: 'ok',
          val: undefined
        };
        break;
      }
      case 1: {
        variant0= {
          tag: 'err',
          val: undefined
        };
        break;
      }
      default: {
        throw new TypeError('invalid variant discriminant for expected');
      }
    }
    _debugLog('[iface="wasi:cli/run@0.2.9", function="run"][Instruction::Return]', {
      funcName: 'run',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    const retCopy = variant0;
    
    if (typeof retCopy === 'object' && retCopy.tag === 'err') {
      throw new ComponentError(retCopy.val);
    }
    return retCopy.val;
    
  }
  run029Run = exports1['wasi:cli/run@0.2.9#run'];
  const run029 = {
    run: run,
    
  };
  
  return { run: run029, 'wasi:cli/run@0.2.9': run029,  };
})();
let promise, resolve, reject;
function runNext (value) {
  try {
    let done;
    do {
      ({ value, done } = gen.next(value));
    } while (!(value instanceof Promise) && !done);
    if (done) {
      if (resolve) return resolve(value);
      else return value;
    }
    if (!promise) promise = new Promise((_resolve, _reject) => (resolve = _resolve, reject = _reject));
    value.then(nextVal => done ? resolve() : runNext(nextVal), reject);
  }
  catch (e) {
    if (reject) reject(e);
    else throw e;
  }
}
const maybeSyncReturn = runNext(null);
return promise || maybeSyncReturn;
}
