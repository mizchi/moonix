export function instantiate(getCoreModule, imports, instantiateCore = WebAssembly.instantiate) {
  
  let dv = new DataView(new ArrayBuffer());
  const dataView = mem => dv.buffer === mem.buffer ? dv : dv = new DataView(mem.buffer);
  
  const toUint64 = val => BigInt.asUintN(64, BigInt(val));
  
  function toUint32(val) {
    return val >>> 0;
  }
  
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

const { environment, stderr, stdin, stdout } = imports['../../deno_host/virtual_cli.ts'];
const { monotonicClock, wallClock } = imports['../../deno_host/virtual_clock.ts'];
const { preopens, types } = imports['../../deno_host/virtual_fs.ts'];
const { error, streams } = imports['../../deno_host/virtual_io.ts'];
const { poll: poll$1 } = imports['../../deno_host/virtual_poll.ts'];
const { insecure, insecureSeed: insecureSeed$1, random } = imports['../../deno_host/virtual_random.ts'];
const { tcp, tcpCreateSocket, udp, udpCreateSocket } = imports['../../deno_host/virtual_sockets.ts'];
const { getArguments,
  getEnvironment } = environment;
const { getStderr } = stderr;
const { getStdin } = stdin;
const { getStdout } = stdout;
const { now,
  resolution,
  subscribeDuration } = monotonicClock;
const { now: now$1,
  resolution: resolution$1 } = wallClock;
const { getDirectories } = preopens;
const { Descriptor } = types;
const { Error: Error$1 } = error;
const { InputStream,
  OutputStream } = streams;
const { Pollable,
  poll } = poll$1;
const { getInsecureRandomBytes,
  getInsecureRandomU64 } = insecure;
const { insecureSeed } = insecureSeed$1;
const { getRandomBytes,
  getRandomU64 } = random;
const { TcpSocket } = tcp;
const { createTcpSocket } = tcpCreateSocket;
const { UdpSocket } = udp;
const { createUdpSocket } = udpCreateSocket;
let gen = (function* _initGenerator () {
  let exports0;
  
  function trampoline0() {
    _debugLog('[iface="wasi:random/random@0.2.9", function="get-random-u64"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-random-u64');
    const ret = getRandomU64();
    _debugLog('[iface="wasi:random/random@0.2.9", function="get-random-u64"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    _debugLog('[iface="wasi:random/random@0.2.9", function="get-random-u64"][Instruction::Return]', {
      funcName: 'get-random-u64',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return toUint64(ret);
  }
  
  
  function trampoline1() {
    _debugLog('[iface="wasi:clocks/monotonic-clock@0.2.9", function="resolution"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'resolution');
    const ret = resolution();
    _debugLog('[iface="wasi:clocks/monotonic-clock@0.2.9", function="resolution"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    _debugLog('[iface="wasi:clocks/monotonic-clock@0.2.9", function="resolution"][Instruction::Return]', {
      funcName: 'resolution',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return toUint64(ret);
  }
  
  const handleTable3 = [T_FLAG, 0];
  const captureTable3= new Map();
  let captureCnt3 = 0;
  handleTables[3] = handleTable3;
  
  function trampoline2() {
    _debugLog('[iface="wasi:cli/stderr@0.2.9", function="get-stderr"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-stderr');
    const ret = getStderr();
    _debugLog('[iface="wasi:cli/stderr@0.2.9", function="get-stderr"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    if (!(ret instanceof OutputStream)) {
      throw new TypeError('Resource error: Not a valid "OutputStream" resource.');
    }
    var handle0 = ret[symbolRscHandle];
    if (!handle0) {
      const rep = ret[symbolRscRep] || ++captureCnt3;
      captureTable3.set(rep, ret);
      handle0 = rscTableCreateOwn(handleTable3, rep);
    }
    _debugLog('[iface="wasi:cli/stderr@0.2.9", function="get-stderr"][Instruction::Return]', {
      funcName: 'get-stderr',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return handle0;
  }
  
  const handleTable1 = [T_FLAG, 0];
  const captureTable1= new Map();
  let captureCnt1 = 0;
  handleTables[1] = handleTable1;
  
  function trampoline3(arg0) {
    _debugLog('[iface="wasi:clocks/monotonic-clock@0.2.9", function="subscribe-duration"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'subscribe-duration');
    const ret = subscribeDuration(BigInt.asUintN(64, arg0));
    _debugLog('[iface="wasi:clocks/monotonic-clock@0.2.9", function="subscribe-duration"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    if (!(ret instanceof Pollable)) {
      throw new TypeError('Resource error: Not a valid "Pollable" resource.');
    }
    var handle0 = ret[symbolRscHandle];
    if (!handle0) {
      const rep = ret[symbolRscRep] || ++captureCnt1;
      captureTable1.set(rep, ret);
      handle0 = rscTableCreateOwn(handleTable1, rep);
    }
    _debugLog('[iface="wasi:clocks/monotonic-clock@0.2.9", function="subscribe-duration"][Instruction::Return]', {
      funcName: 'subscribe-duration',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return handle0;
  }
  
  
  function trampoline4() {
    _debugLog('[iface="wasi:random/insecure@0.2.9", function="get-insecure-random-u64"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-insecure-random-u64');
    const ret = getInsecureRandomU64();
    _debugLog('[iface="wasi:random/insecure@0.2.9", function="get-insecure-random-u64"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    _debugLog('[iface="wasi:random/insecure@0.2.9", function="get-insecure-random-u64"][Instruction::Return]', {
      funcName: 'get-insecure-random-u64',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return toUint64(ret);
  }
  
  const handleTable2 = [T_FLAG, 0];
  const captureTable2= new Map();
  let captureCnt2 = 0;
  handleTables[2] = handleTable2;
  
  function trampoline5() {
    _debugLog('[iface="wasi:cli/stdin@0.2.9", function="get-stdin"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-stdin');
    const ret = getStdin();
    _debugLog('[iface="wasi:cli/stdin@0.2.9", function="get-stdin"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    if (!(ret instanceof InputStream)) {
      throw new TypeError('Resource error: Not a valid "InputStream" resource.');
    }
    var handle0 = ret[symbolRscHandle];
    if (!handle0) {
      const rep = ret[symbolRscRep] || ++captureCnt2;
      captureTable2.set(rep, ret);
      handle0 = rscTableCreateOwn(handleTable2, rep);
    }
    _debugLog('[iface="wasi:cli/stdin@0.2.9", function="get-stdin"][Instruction::Return]', {
      funcName: 'get-stdin',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return handle0;
  }
  
  
  function trampoline6() {
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
      const rep = ret[symbolRscRep] || ++captureCnt3;
      captureTable3.set(rep, ret);
      handle0 = rscTableCreateOwn(handleTable3, rep);
    }
    _debugLog('[iface="wasi:cli/stdout@0.2.9", function="get-stdout"][Instruction::Return]', {
      funcName: 'get-stdout',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return handle0;
  }
  
  
  function trampoline7() {
    _debugLog('[iface="wasi:clocks/monotonic-clock@0.2.9", function="now"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'now');
    const ret = now();
    _debugLog('[iface="wasi:clocks/monotonic-clock@0.2.9", function="now"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    _debugLog('[iface="wasi:clocks/monotonic-clock@0.2.9", function="now"][Instruction::Return]', {
      funcName: 'now',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return toUint64(ret);
  }
  
  
  function trampoline8(arg0) {
    var handle1 = arg0;
    var rep2 = handleTable1[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable1.get(rep2);
    if (!rsc0) {
      rsc0 = Object.create(Pollable.prototype);
      Object.defineProperty(rsc0, symbolRscHandle, { writable: true, value: handle1});
      Object.defineProperty(rsc0, symbolRscRep, { writable: true, value: rep2});
    }
    curResourceBorrows.push(rsc0);
    _debugLog('[iface="wasi:io/poll@0.2.9", function="[method]pollable.ready"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, '[method]pollable.ready');
    const ret = rsc0.ready();
    _debugLog('[iface="wasi:io/poll@0.2.9", function="[method]pollable.ready"] [Instruction::CallInterface] (sync, @ post-call)');
    for (const rsc of curResourceBorrows) {
      rsc[symbolRscHandle] = undefined;
    }
    curResourceBorrows = [];
    endCurrentTask(0);
    _debugLog('[iface="wasi:io/poll@0.2.9", function="[method]pollable.ready"][Instruction::Return]', {
      funcName: '[method]pollable.ready',
      paramCount: 1,
      async: false,
      postReturn: false
    });
    return ret ? 1 : 0;
  }
  
  let exports1;
  let memory0;
  let realloc0;
  const handleTable4 = [T_FLAG, 0];
  const captureTable4= new Map();
  let captureCnt4 = 0;
  handleTables[4] = handleTable4;
  
  function trampoline9(arg0) {
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
        const rep = tuple0_0[symbolRscRep] || ++captureCnt4;
        captureTable4.set(rep, tuple0_0);
        handle1 = rscTableCreateOwn(handleTable4, rep);
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
  
  
  function trampoline10(arg0) {
    _debugLog('[iface="wasi:cli/environment@0.2.9", function="get-environment"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-environment');
    const ret = getEnvironment();
    _debugLog('[iface="wasi:cli/environment@0.2.9", function="get-environment"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var vec3 = ret;
    var len3 = vec3.length;
    var result3 = realloc0(0, 0, 4, len3 * 16);
    for (let i = 0; i < vec3.length; i++) {
      const e = vec3[i];
      const base = result3 + i * 16;var [tuple0_0, tuple0_1] = e;
      var ptr1 = utf8Encode(tuple0_0, realloc0, memory0);
      var len1 = utf8EncodedLen;
      dataView(memory0).setUint32(base + 4, len1, true);
      dataView(memory0).setUint32(base + 0, ptr1, true);
      var ptr2 = utf8Encode(tuple0_1, realloc0, memory0);
      var len2 = utf8EncodedLen;
      dataView(memory0).setUint32(base + 12, len2, true);
      dataView(memory0).setUint32(base + 8, ptr2, true);
    }
    dataView(memory0).setUint32(arg0 + 4, len3, true);
    dataView(memory0).setUint32(arg0 + 0, result3, true);
    _debugLog('[iface="wasi:cli/environment@0.2.9", function="get-environment"][Instruction::Return]', {
      funcName: 'get-environment',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline11(arg0) {
    _debugLog('[iface="wasi:cli/environment@0.2.9", function="get-arguments"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-arguments');
    const ret = getArguments();
    _debugLog('[iface="wasi:cli/environment@0.2.9", function="get-arguments"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var vec1 = ret;
    var len1 = vec1.length;
    var result1 = realloc0(0, 0, 4, len1 * 8);
    for (let i = 0; i < vec1.length; i++) {
      const e = vec1[i];
      const base = result1 + i * 8;var ptr0 = utf8Encode(e, realloc0, memory0);
      var len0 = utf8EncodedLen;
      dataView(memory0).setUint32(base + 4, len0, true);
      dataView(memory0).setUint32(base + 0, ptr0, true);
    }
    dataView(memory0).setUint32(arg0 + 4, len1, true);
    dataView(memory0).setUint32(arg0 + 0, result1, true);
    _debugLog('[iface="wasi:cli/environment@0.2.9", function="get-arguments"][Instruction::Return]', {
      funcName: 'get-arguments',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline12(arg0) {
    _debugLog('[iface="wasi:random/insecure-seed@0.2.9", function="insecure-seed"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'insecure-seed');
    const ret = insecureSeed();
    _debugLog('[iface="wasi:random/insecure-seed@0.2.9", function="insecure-seed"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var [tuple0_0, tuple0_1] = ret;
    dataView(memory0).setBigInt64(arg0 + 0, toUint64(tuple0_0), true);
    dataView(memory0).setBigInt64(arg0 + 8, toUint64(tuple0_1), true);
    _debugLog('[iface="wasi:random/insecure-seed@0.2.9", function="insecure-seed"][Instruction::Return]', {
      funcName: 'insecure-seed',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline13(arg0, arg1, arg2, arg3, arg4) {
    var handle1 = arg0;
    var rep2 = handleTable4[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable4.get(rep2);
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
  
  
  function trampoline14(arg0, arg1, arg2, arg3) {
    var handle1 = arg0;
    var rep2 = handleTable4[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable4.get(rep2);
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
  
  
  function trampoline15(arg0, arg1, arg2, arg3, arg4, arg5, arg6) {
    var handle1 = arg0;
    var rep2 = handleTable4[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable4.get(rep2);
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
          const rep = e[symbolRscRep] || ++captureCnt4;
          captureTable4.set(rep, e);
          handle7 = rscTableCreateOwn(handleTable4, rep);
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
  
  
  function trampoline16(arg0, arg1) {
    _debugLog('[iface="wasi:random/random@0.2.9", function="get-random-bytes"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-random-bytes');
    const ret = getRandomBytes(BigInt.asUintN(64, arg0));
    _debugLog('[iface="wasi:random/random@0.2.9", function="get-random-bytes"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var val0 = ret;
    var len0 = val0.byteLength;
    var ptr0 = realloc0(0, 0, 1, len0 * 1);
    var src0 = new Uint8Array(val0.buffer || val0, val0.byteOffset, len0 * 1);
    (new Uint8Array(memory0.buffer, ptr0, len0 * 1)).set(src0);
    dataView(memory0).setUint32(arg1 + 4, len0, true);
    dataView(memory0).setUint32(arg1 + 0, ptr0, true);
    _debugLog('[iface="wasi:random/random@0.2.9", function="get-random-bytes"][Instruction::Return]', {
      funcName: 'get-random-bytes',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  const handleTable5 = [T_FLAG, 0];
  const captureTable5= new Map();
  let captureCnt5 = 0;
  handleTables[5] = handleTable5;
  
  function trampoline17(arg0, arg1) {
    let enum0;
    switch (arg0) {
      case 0: {
        enum0 = 'ipv4';
        break;
      }
      case 1: {
        enum0 = 'ipv6';
        break;
      }
      default: {
        throw new TypeError('invalid discriminant specified for IpAddressFamily');
      }
    }
    _debugLog('[iface="wasi:sockets/udp-create-socket@0.2.9", function="create-udp-socket"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'create-udp-socket');
    let ret;
    try {
      ret = { tag: 'ok', val: createUdpSocket(enum0)};
    } catch (e) {
      ret = { tag: 'err', val: getErrorPayload(e) };
    }
    _debugLog('[iface="wasi:sockets/udp-create-socket@0.2.9", function="create-udp-socket"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var variant3 = ret;
    switch (variant3.tag) {
      case 'ok': {
        const e = variant3.val;
        dataView(memory0).setInt8(arg1 + 0, 0, true);
        if (!(e instanceof UdpSocket)) {
          throw new TypeError('Resource error: Not a valid "UdpSocket" resource.');
        }
        var handle1 = e[symbolRscHandle];
        if (!handle1) {
          const rep = e[symbolRscRep] || ++captureCnt5;
          captureTable5.set(rep, e);
          handle1 = rscTableCreateOwn(handleTable5, rep);
        }
        dataView(memory0).setInt32(arg1 + 4, handle1, true);
        break;
      }
      case 'err': {
        const e = variant3.val;
        dataView(memory0).setInt8(arg1 + 0, 1, true);
        var val2 = e;
        let enum2;
        switch (val2) {
          case 'unknown': {
            enum2 = 0;
            break;
          }
          case 'access-denied': {
            enum2 = 1;
            break;
          }
          case 'not-supported': {
            enum2 = 2;
            break;
          }
          case 'invalid-argument': {
            enum2 = 3;
            break;
          }
          case 'out-of-memory': {
            enum2 = 4;
            break;
          }
          case 'timeout': {
            enum2 = 5;
            break;
          }
          case 'concurrency-conflict': {
            enum2 = 6;
            break;
          }
          case 'not-in-progress': {
            enum2 = 7;
            break;
          }
          case 'would-block': {
            enum2 = 8;
            break;
          }
          case 'invalid-state': {
            enum2 = 9;
            break;
          }
          case 'new-socket-limit': {
            enum2 = 10;
            break;
          }
          case 'address-not-bindable': {
            enum2 = 11;
            break;
          }
          case 'address-in-use': {
            enum2 = 12;
            break;
          }
          case 'remote-unreachable': {
            enum2 = 13;
            break;
          }
          case 'connection-refused': {
            enum2 = 14;
            break;
          }
          case 'connection-reset': {
            enum2 = 15;
            break;
          }
          case 'connection-aborted': {
            enum2 = 16;
            break;
          }
          case 'datagram-too-large': {
            enum2 = 17;
            break;
          }
          case 'name-unresolvable': {
            enum2 = 18;
            break;
          }
          case 'temporary-resolver-failure': {
            enum2 = 19;
            break;
          }
          case 'permanent-resolver-failure': {
            enum2 = 20;
            break;
          }
          default: {
            if ((e) instanceof Error) {
              console.error(e);
            }
            
            throw new TypeError(`"${val2}" is not one of the cases of error-code`);
          }
        }
        dataView(memory0).setInt8(arg1 + 4, enum2, true);
        break;
      }
      default: {
        throw new TypeError('invalid variant specified for result');
      }
    }
    _debugLog('[iface="wasi:sockets/udp-create-socket@0.2.9", function="create-udp-socket"][Instruction::Return]', {
      funcName: 'create-udp-socket',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  const handleTable0 = [T_FLAG, 0];
  const captureTable0= new Map();
  let captureCnt0 = 0;
  handleTables[0] = handleTable0;
  
  function trampoline18(arg0, arg1, arg2) {
    var handle1 = arg0;
    var rep2 = handleTable2[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable2.get(rep2);
    if (!rsc0) {
      rsc0 = Object.create(InputStream.prototype);
      Object.defineProperty(rsc0, symbolRscHandle, { writable: true, value: handle1});
      Object.defineProperty(rsc0, symbolRscRep, { writable: true, value: rep2});
    }
    curResourceBorrows.push(rsc0);
    _debugLog('[iface="wasi:io/streams@0.2.9", function="[method]input-stream.read"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, '[method]input-stream.read');
    let ret;
    try {
      ret = { tag: 'ok', val: rsc0.read(BigInt.asUintN(64, arg1))};
    } catch (e) {
      ret = { tag: 'err', val: getErrorPayload(e) };
    }
    _debugLog('[iface="wasi:io/streams@0.2.9", function="[method]input-stream.read"] [Instruction::CallInterface] (sync, @ post-call)');
    for (const rsc of curResourceBorrows) {
      rsc[symbolRscHandle] = undefined;
    }
    curResourceBorrows = [];
    endCurrentTask(0);
    var variant6 = ret;
    switch (variant6.tag) {
      case 'ok': {
        const e = variant6.val;
        dataView(memory0).setInt8(arg2 + 0, 0, true);
        var val3 = e;
        var len3 = val3.byteLength;
        var ptr3 = realloc0(0, 0, 1, len3 * 1);
        var src3 = new Uint8Array(val3.buffer || val3, val3.byteOffset, len3 * 1);
        (new Uint8Array(memory0.buffer, ptr3, len3 * 1)).set(src3);
        dataView(memory0).setUint32(arg2 + 8, len3, true);
        dataView(memory0).setUint32(arg2 + 4, ptr3, true);
        break;
      }
      case 'err': {
        const e = variant6.val;
        dataView(memory0).setInt8(arg2 + 0, 1, true);
        var variant5 = e;
        switch (variant5.tag) {
          case 'last-operation-failed': {
            const e = variant5.val;
            dataView(memory0).setInt8(arg2 + 4, 0, true);
            if (!(e instanceof Error$1)) {
              throw new TypeError('Resource error: Not a valid "Error" resource.');
            }
            var handle4 = e[symbolRscHandle];
            if (!handle4) {
              const rep = e[symbolRscRep] || ++captureCnt0;
              captureTable0.set(rep, e);
              handle4 = rscTableCreateOwn(handleTable0, rep);
            }
            dataView(memory0).setInt32(arg2 + 8, handle4, true);
            break;
          }
          case 'closed': {
            dataView(memory0).setInt8(arg2 + 4, 1, true);
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
    _debugLog('[iface="wasi:io/streams@0.2.9", function="[method]input-stream.read"][Instruction::Return]', {
      funcName: '[method]input-stream.read',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline19(arg0, arg1, arg2, arg3) {
    var handle1 = arg0;
    var rep2 = handleTable3[(handle1 << 1) + 1] & ~T_FLAG;
    var rsc0 = captureTable3.get(rep2);
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
  
  
  function trampoline20(arg0, arg1, arg2) {
    var len3 = arg1;
    var base3 = arg0;
    var result3 = [];
    for (let i = 0; i < len3; i++) {
      const base = base3 + i * 4;
      var handle1 = dataView(memory0).getInt32(base + 0, true);
      var rep2 = handleTable1[(handle1 << 1) + 1] & ~T_FLAG;
      var rsc0 = captureTable1.get(rep2);
      if (!rsc0) {
        rsc0 = Object.create(Pollable.prototype);
        Object.defineProperty(rsc0, symbolRscHandle, { writable: true, value: handle1});
        Object.defineProperty(rsc0, symbolRscRep, { writable: true, value: rep2});
      }
      curResourceBorrows.push(rsc0);
      result3.push(rsc0);
    }
    _debugLog('[iface="wasi:io/poll@0.2.9", function="poll"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'poll');
    const ret = poll(result3);
    _debugLog('[iface="wasi:io/poll@0.2.9", function="poll"] [Instruction::CallInterface] (sync, @ post-call)');
    for (const rsc of curResourceBorrows) {
      rsc[symbolRscHandle] = undefined;
    }
    curResourceBorrows = [];
    endCurrentTask(0);
    var val4 = ret;
    var len4 = val4.length;
    var ptr4 = realloc0(0, 0, 4, len4 * 4);
    var src4 = new Uint8Array(val4.buffer, val4.byteOffset, len4 * 4);
    (new Uint8Array(memory0.buffer, ptr4, len4 * 4)).set(src4);
    dataView(memory0).setUint32(arg2 + 4, len4, true);
    dataView(memory0).setUint32(arg2 + 0, ptr4, true);
    _debugLog('[iface="wasi:io/poll@0.2.9", function="poll"][Instruction::Return]', {
      funcName: 'poll',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  const handleTable6 = [T_FLAG, 0];
  const captureTable6= new Map();
  let captureCnt6 = 0;
  handleTables[6] = handleTable6;
  
  function trampoline21(arg0, arg1) {
    let enum0;
    switch (arg0) {
      case 0: {
        enum0 = 'ipv4';
        break;
      }
      case 1: {
        enum0 = 'ipv6';
        break;
      }
      default: {
        throw new TypeError('invalid discriminant specified for IpAddressFamily');
      }
    }
    _debugLog('[iface="wasi:sockets/tcp-create-socket@0.2.9", function="create-tcp-socket"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'create-tcp-socket');
    let ret;
    try {
      ret = { tag: 'ok', val: createTcpSocket(enum0)};
    } catch (e) {
      ret = { tag: 'err', val: getErrorPayload(e) };
    }
    _debugLog('[iface="wasi:sockets/tcp-create-socket@0.2.9", function="create-tcp-socket"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var variant3 = ret;
    switch (variant3.tag) {
      case 'ok': {
        const e = variant3.val;
        dataView(memory0).setInt8(arg1 + 0, 0, true);
        if (!(e instanceof TcpSocket)) {
          throw new TypeError('Resource error: Not a valid "TcpSocket" resource.');
        }
        var handle1 = e[symbolRscHandle];
        if (!handle1) {
          const rep = e[symbolRscRep] || ++captureCnt6;
          captureTable6.set(rep, e);
          handle1 = rscTableCreateOwn(handleTable6, rep);
        }
        dataView(memory0).setInt32(arg1 + 4, handle1, true);
        break;
      }
      case 'err': {
        const e = variant3.val;
        dataView(memory0).setInt8(arg1 + 0, 1, true);
        var val2 = e;
        let enum2;
        switch (val2) {
          case 'unknown': {
            enum2 = 0;
            break;
          }
          case 'access-denied': {
            enum2 = 1;
            break;
          }
          case 'not-supported': {
            enum2 = 2;
            break;
          }
          case 'invalid-argument': {
            enum2 = 3;
            break;
          }
          case 'out-of-memory': {
            enum2 = 4;
            break;
          }
          case 'timeout': {
            enum2 = 5;
            break;
          }
          case 'concurrency-conflict': {
            enum2 = 6;
            break;
          }
          case 'not-in-progress': {
            enum2 = 7;
            break;
          }
          case 'would-block': {
            enum2 = 8;
            break;
          }
          case 'invalid-state': {
            enum2 = 9;
            break;
          }
          case 'new-socket-limit': {
            enum2 = 10;
            break;
          }
          case 'address-not-bindable': {
            enum2 = 11;
            break;
          }
          case 'address-in-use': {
            enum2 = 12;
            break;
          }
          case 'remote-unreachable': {
            enum2 = 13;
            break;
          }
          case 'connection-refused': {
            enum2 = 14;
            break;
          }
          case 'connection-reset': {
            enum2 = 15;
            break;
          }
          case 'connection-aborted': {
            enum2 = 16;
            break;
          }
          case 'datagram-too-large': {
            enum2 = 17;
            break;
          }
          case 'name-unresolvable': {
            enum2 = 18;
            break;
          }
          case 'temporary-resolver-failure': {
            enum2 = 19;
            break;
          }
          case 'permanent-resolver-failure': {
            enum2 = 20;
            break;
          }
          default: {
            if ((e) instanceof Error) {
              console.error(e);
            }
            
            throw new TypeError(`"${val2}" is not one of the cases of error-code`);
          }
        }
        dataView(memory0).setInt8(arg1 + 4, enum2, true);
        break;
      }
      default: {
        throw new TypeError('invalid variant specified for result');
      }
    }
    _debugLog('[iface="wasi:sockets/tcp-create-socket@0.2.9", function="create-tcp-socket"][Instruction::Return]', {
      funcName: 'create-tcp-socket',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline22(arg0) {
    _debugLog('[iface="wasi:clocks/wall-clock@0.2.9", function="resolution"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'resolution');
    const ret = resolution$1();
    _debugLog('[iface="wasi:clocks/wall-clock@0.2.9", function="resolution"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var {seconds: v0_0, nanoseconds: v0_1 } = ret;
    dataView(memory0).setBigInt64(arg0 + 0, toUint64(v0_0), true);
    dataView(memory0).setInt32(arg0 + 8, toUint32(v0_1), true);
    _debugLog('[iface="wasi:clocks/wall-clock@0.2.9", function="resolution"][Instruction::Return]', {
      funcName: 'resolution',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline23(arg0) {
    _debugLog('[iface="wasi:clocks/wall-clock@0.2.9", function="now"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'now');
    const ret = now$1();
    _debugLog('[iface="wasi:clocks/wall-clock@0.2.9", function="now"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var {seconds: v0_0, nanoseconds: v0_1 } = ret;
    dataView(memory0).setBigInt64(arg0 + 0, toUint64(v0_0), true);
    dataView(memory0).setInt32(arg0 + 8, toUint32(v0_1), true);
    _debugLog('[iface="wasi:clocks/wall-clock@0.2.9", function="now"][Instruction::Return]', {
      funcName: 'now',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  
  function trampoline24(arg0, arg1) {
    _debugLog('[iface="wasi:random/insecure@0.2.9", function="get-insecure-random-bytes"] [Instruction::CallInterface] (async? sync, @ enter)');
    const _interface_call_currentTaskID = startCurrentTask(0, false, 'get-insecure-random-bytes');
    const ret = getInsecureRandomBytes(BigInt.asUintN(64, arg0));
    _debugLog('[iface="wasi:random/insecure@0.2.9", function="get-insecure-random-bytes"] [Instruction::CallInterface] (sync, @ post-call)');
    endCurrentTask(0);
    var val0 = ret;
    var len0 = val0.byteLength;
    var ptr0 = realloc0(0, 0, 1, len0 * 1);
    var src0 = new Uint8Array(val0.buffer || val0, val0.byteOffset, len0 * 1);
    (new Uint8Array(memory0.buffer, ptr0, len0 * 1)).set(src0);
    dataView(memory0).setUint32(arg1 + 4, len0, true);
    dataView(memory0).setUint32(arg1 + 0, ptr0, true);
    _debugLog('[iface="wasi:random/insecure@0.2.9", function="get-insecure-random-bytes"][Instruction::Return]', {
      funcName: 'get-insecure-random-bytes',
      paramCount: 0,
      async: false,
      postReturn: false
    });
  }
  
  let exports2;
  Promise.all([module0, module1, module2]).catch(() => {});
  ({ exports: exports0 } = yield instantiateCore(yield module1));
  ({ exports: exports1 } = yield instantiateCore(yield module0, {
    'wasi:cli/environment@0.2.9': {
      'get-arguments': exports0['2'],
      'get-environment': exports0['1'],
    },
    'wasi:cli/stderr@0.2.9': {
      'get-stderr': trampoline2,
    },
    'wasi:cli/stdin@0.2.9': {
      'get-stdin': trampoline5,
    },
    'wasi:cli/stdout@0.2.9': {
      'get-stdout': trampoline6,
    },
    'wasi:clocks/monotonic-clock@0.2.9': {
      now: trampoline7,
      resolution: trampoline1,
      'subscribe-duration': trampoline3,
    },
    'wasi:clocks/wall-clock@0.2.9': {
      now: exports0['14'],
      resolution: exports0['13'],
    },
    'wasi:filesystem/preopens@0.2.9': {
      'get-directories': exports0['0'],
    },
    'wasi:filesystem/types@0.2.9': {
      '[method]descriptor.open-at': exports0['6'],
      '[method]descriptor.read': exports0['5'],
      '[method]descriptor.write': exports0['4'],
    },
    'wasi:io/poll@0.2.9': {
      '[method]pollable.ready': trampoline8,
      poll: exports0['11'],
    },
    'wasi:io/streams@0.2.9': {
      '[method]input-stream.read': exports0['9'],
      '[method]output-stream.blocking-write-and-flush': exports0['10'],
    },
    'wasi:random/insecure-seed@0.2.9': {
      'insecure-seed': exports0['3'],
    },
    'wasi:random/insecure@0.2.9': {
      'get-insecure-random-bytes': exports0['15'],
      'get-insecure-random-u64': trampoline4,
    },
    'wasi:random/random@0.2.9': {
      'get-random-bytes': exports0['7'],
      'get-random-u64': trampoline0,
    },
    'wasi:sockets/tcp-create-socket@0.2.9': {
      'create-tcp-socket': exports0['12'],
    },
    'wasi:sockets/udp-create-socket@0.2.9': {
      'create-udp-socket': exports0['8'],
    },
  }));
  memory0 = exports1.memory;
  realloc0 = exports1.cabi_realloc;
  ({ exports: exports2 } = yield instantiateCore(yield module2, {
    '': {
      $imports: exports0.$imports,
      '0': trampoline9,
      '1': trampoline10,
      '10': trampoline19,
      '11': trampoline20,
      '12': trampoline21,
      '13': trampoline22,
      '14': trampoline23,
      '15': trampoline24,
      '2': trampoline11,
      '3': trampoline12,
      '4': trampoline13,
      '5': trampoline14,
      '6': trampoline15,
      '7': trampoline16,
      '8': trampoline17,
      '9': trampoline18,
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
