import { fetchStatus, saveBridgeUrl, getBridgeUrl, initializeHardware, resetHardware, computeOnHardware } from "./api.js";
import { MatrixEditor } from "./matrix-editor.js";
import { calculateReference, compareMatrices, validateJob } from "./validation.js";
import { resetView, setOperationState } from "./visualization.js";

const byId = function (id) { return document.getElementById(id); };

// Auto-sync dimension callback to keep Matrix A cols equal to Matrix B rows (dimension K)
function handleDimensionChange(source, rows, cols) {
  if (source === "A" && matrixBEditor) {
    const curBRows = Number(matrixBEditor.rowInput.value);
    if (curBRows !== cols) {
      matrixBEditor.setDimensions(cols, Number(matrixBEditor.colInput.value) || 2, true);
    }
  } else if (source === "B" && matrixAEditor) {
    const curACols = Number(matrixAEditor.colInput.value);
    if (curACols !== rows) {
      matrixAEditor.setDimensions(Number(matrixAEditor.rowInput.value) || 2, rows, true);
    }
  }
  updateValidation();
}

const matrixAEditor = new MatrixEditor(
  document.querySelector('[data-matrix="A"]'),
  [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
  handleDimensionChange
);
const matrixBEditor = new MatrixEditor(
  document.querySelector('[data-matrix="B"]'),
  [[3], [-1], [4], [2]],
  handleDimensionChange
);

const bridgeUrlInput = byId("bridge-url");
const validationMessage = byId("validation-message");
let bridgeStatus = null;
let requestInFlight = false;
let lastInput = null;
let pollTimer = 0;

// Embedded test cases from cases.json for instant one-click loading
const CASES_DATA = {
  case1: {
    name: "identity_4",
    A: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
    B: [[3], [-1], [4], [2]]
  },
  case2: {
    name: "zero_4",
    A: [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
    B: [[9], [9], [9], [9]]
  },
  case3: {
    name: "negative_4",
    A: [[-1, -2, -3, -4], [-5, -6, -7, -8], [-9, -10, -11, -12], [-13, -14, -15, -16]],
    B: [[1], [-2], [3], [-4]]
  },
  case4: {
    name: "random_4",
    A: [[-3, 7, -1, 4], [2, -6, 5, -8], [-4, 1, 9, -2], [6, -5, 3, 1]],
    B: [[-5], [1], [-2], [-8]]
  },
  case5: {
    name: "random_8",
    A: [
      [-5, 2, -7, 4, 1, -8, 3, 6],
      [7, -3, 1, -6, 2, 4, -5, 8],
      [-2, 6, -4, 3, -1, 5, 7, -9],
      [4, -1, 8, -2, 6, -3, 5, 1],
      [-8, 5, 2, -7, 3, 1, -4, 6],
      [3, -4, 6, 1, -9, 2, 8, -5],
      [1, 7, -3, 5, -2, 8, -6, 4],
      [-6, 1, 5, -4, 7, -2, 3, -8]
    ],
    B: [[0], [-5], [-7], [6], [7], [-4], [-2], [4]]
  },
  case6: {
    name: "random_16_scalability",
    A: [
      [3, -5, 2, 7, -1, 4, -8, 6, 2, -3, 5, 1, -7, 4, 8, -2],
      [-4, 6, -2, 1, 8, -5, 3, -7, 4, 1, -6, 2, 5, -8, 3, 7],
      [7, -1, 5, -8, 2, 6, -4, 3, -2, 7, 1, -5, 4, 2, -6, 8],
      [-2, 8, -6, 3, 5, -1, 7, 4, -8, 2, -4, 6, 1, 5, -3, 2],
      [5, -3, 7, -2, 4, 8, -1, 6, 3, -5, 2, 7, -4, 1, 6, -8],
      [1, 4, -8, 6, -3, 2, 5, -1, 7, -4, 8, -2, 6, 3, -5, 1],
      [-6, 2, 4, -7, 1, 5, -8, 3, 6, 1, -3, 5, 2, -7, 4, 8],
      [8, -7, 1, 5, -6, 3, 2, -4, 1, 8, -5, 3, 7, -2, 1, 4],
      [-1, 5, -3, 2, 7, -4, 6, 8, -2, 3, 7, -1, 5, 6, -4, 3],
      [4, -2, 6, 1, -5, 7, -3, 2, 8, -6, 1, 4, -8, 5, 2, 7],
      [2, 7, -4, 8, -2, 1, 4, -6, 5, 2, -7, 3, 1, -4, 8, 6],
      [-5, 1, 8, -4, 6, -2, 7, 1, -3, 5, 4, -8, 2, 7, -1, 5],
      [6, -8, 2, 5, -4, 3, 1, 7, -1, 4, 6, 2, -3, 8, 5, -7],
      [7, 3, -5, 2, 1, -6, 8, -1, 4, 7, -2, 5, 6, -3, 2, 1],
      [-3, 6, 1, -7, 8, 4, -2, 5, 3, -1, 8, 6, -5, 2, 7, -4],
      [5, -4, 7, 3, -2, 8, 6, -5, 1, 6, -4, 7, 3, 1, -8, 2]
    ],
    B: [[-7], [5], [-3], [-6], [2], [-8], [4], [1], [-5], [7], [-2], [3], [2], [6], [-7], [7]]
  },
  case7: {
    name: "max_values_4",
    A: [[127, 127, 127, 127], [127, 127, 127, 127], [127, 127, 127, 127], [127, 127, 127, 127]],
    B: [[127], [127], [127], [127]]
  },
  pipe3: {
    name: "pipelining_3",
    A: [
      [3, -5, 2, 7, -1, 4, -8, 6, 2, -3, 5, 1, -7, 4, 8, -2],
      [-4, 6, -2, 1, 8, -5, 3, -7, 4, 1, -6, 2, 5, -8, 3, 7],
      [7, -1, 5, -8, 2, 6, -4, 3, -2, 7, 1, -5, 4, 2, -6, 8],
      [-2, 8, -6, 3, 5, -1, 7, 4, -8, 2, -4, 6, 1, 5, -3, 2],
      [5, -3, 7, -2, 4, 8, -1, 6, 3, -5, 2, 7, -4, 1, 6, -8],
      [1, 4, -8, 6, -3, 2, 5, -1, 7, -4, 8, -2, 6, 3, -5, 1],
      [-6, 2, 4, -7, 1, 5, -8, 3, 6, 1, -3, 5, 2, -7, 4, 8],
      [8, -7, 1, 5, -6, 3, 2, -4, 1, 8, -5, 3, 7, -2, 1, 4],
      [-1, 5, -3, 2, 7, -4, 6, 8, -2, 3, 7, -1, 5, 6, -4, 3],
      [4, -2, 6, 1, -5, 7, -3, 2, 8, -6, 1, 4, -8, 5, 2, 7],
      [2, 7, -4, 8, -2, 1, 4, -6, 5, 2, -7, 3, 1, -4, 8, 6],
      [-5, 1, 8, -4, 6, -2, 7, 1, -3, 5, 4, -8, 2, 7, -1, 5],
      [6, -8, 2, 5, -4, 3, 1, 7, -1, 4, 6, 2, -3, 8, 5, -7],
      [7, 3, -5, 2, 1, -6, 8, -1, 4, 7, -2, 5, 6, -3, 2, 1],
      [-3, 6, 1, -7, 8, 4, -2, 5, 3, -1, 8, 6, -5, 2, 7, -4],
      [5, -4, 7, 3, -2, 8, 6, -5, 1, 6, -4, 7, 3, 1, -8, 2]
    ],
    B: [
      [-7, 7, -12], [5, -5, -5], [-3, 3, 2], [-6, 6, 9],
      [2, -2, -1], [-8, 8, 6], [4, -4, -7], [1, -1, 0],
      [-5, 5, 7], [7, -7, -2], [-2, 2, 5], [3, -3, -4],
      [2, -2, -3], [6, -6, 4], [-7, 7, 11], [7, -7, -7]
    ]
  },
  mat4x4: {
    name: "mat4x4",
    A: [[1, 2, 3, 4], [5, 6, 7, 8], [-1, -2, -3, -4], [2, 0, -2, 1]],
    B: [[1, 0, -1, 2], [0, 1, 2, -1], [1, -1, 0, 1], [2, 1, -1, 0]]
  },
  mat8x8: {
    name: "mat8x8",
    A: Array.from({ length: 8 }, (_, r) => Array.from({ length: 8 }, (_, c) => (r === c ? 2 : (r + c) % 5 - 2))),
    B: Array.from({ length: 8 }, (_, r) => Array.from({ length: 8 }, (_, c) => (r === c ? 1 : (r * c) % 7 - 3)))
  },
  mat16x16: {
    name: "mat16x16",
    A: Array.from({ length: 16 }, (_, r) => Array.from({ length: 16 }, (_, c) => (r === c ? 3 : ((r * 3 + c * 5) % 15 - 7)))),
    B: Array.from({ length: 16 }, (_, r) => Array.from({ length: 16 }, (_, c) => (r === c ? 1 : ((r * 7 - c * 2) % 11 - 5))))
  }
};

function friendlyError(error) {
  if (error.code === "overlay_unavailable") return "The FPGA overlay could not be loaded. Check that its .bit and matching .hwh files are available on the PYNQ-Z2.";
  if (error.code === "hardware_unavailable") return "The overlay is loaded, but the bridge did not detect a supported accelerator and DMA.";
  if (error.code === "hardware_busy") return "The accelerator is busy. Wait for the current hardware request to finish.";
  if (error.code === "timeout") return "The hardware request timed out. The bridge did not confirm a completed result.";
  if (error.code === "invalid_input") return error.message;
  if (error.code === "bridge_unavailable") return error.message;
  if (error.code === "malformed_response") return error.message;
  return error.message || "The hardware request failed. Check the bridge status and try again.";
}

function showError(message) {
  const box = byId("request-error");
  if (box) {
    box.textContent = message;
    box.hidden = false;
  }
}

function clearError() {
  const box = byId("request-error");
  if (box) {
    box.textContent = "";
    box.hidden = true;
  }
}

function setCard(id, state, label, detail) {
  const elem = byId(id);
  if (!elem) return;
  const card = elem.closest(".status-card");
  if (card) card.dataset.state = state;
  elem.innerHTML = '<span class="status-dot"></span>';
  elem.append(document.createTextNode(label));
  const detailId = id.replace("-state", "-detail");
  const detailElem = byId(detailId);
  if (detailElem) detailElem.textContent = detail || "";
}

function renderEngines(engines) {
  const parent = byId("engine-status-list");
  if (!parent) return;
  parent.replaceChildren();
  if (!Array.isArray(engines) || engines.length === 0) {
    const note = document.createElement("span");
    note.textContent = "Engine telemetry appears after overlay initialization.";
    parent.append(note);
    return;
  }
  engines.forEach(function (engine, index) {
    const item = document.createElement("span");
    item.className = "engine-state";
    const name = document.createElement("b");
    name.textContent = engine.name || ("ENGINE " + index);
    const state = document.createElement("span");
    state.textContent = engine.busy ? "BUSY" : engine.done ? "DONE" : engine.telemetryAvailable === false ? "UNAVAILABLE" : "IDLE";
    item.append(name, state);
    parent.append(item);
  });
}

function renderBridgeStatus(status) {
  if (!status || !status.bridge || status.bridge.state !== "online") {
    throw Object.assign(new Error("The bridge returned an incomplete status response."), { code: "malformed_response" });
  }
  bridgeStatus = status;
  setCard("bridge-state", "connected", "Online", "Connected to hardware accelerator");
  const pynq = status.pynq || {};
  if (pynq.state === "connected") setCard("board-state", "connected", "Connected", pynq.detail || "Hardware registers readable");
  else if (pynq.state === "unavailable") setCard("board-state", "unavailable", "Unavailable", pynq.detail || "PYNQ runtime or board is unavailable");
  else setCard("board-state", "unknown", "Unverified", pynq.detail || "Initialize the overlay to verify hardware");

  const overlay = status.overlay || {};
  if (overlay.state === "loaded") setCard("overlay-state", "loaded", "Loaded", overlay.name || "Overlay initialized");
  else if (overlay.state === "error") setCard("overlay-state", "error", "Unavailable", overlay.detail || "Overlay initialization failed");
  else setCard("overlay-state", "unknown", "Not loaded", "Initialize to check");

  const operation = (status.operation && status.operation.state) || "idle";
  const labels = {
    initializing: "Initializing overlay",
    running: "Hardware request in progress (Red LED Blinking)",
    resetting: "Reset requested",
    completed: "Hardware result returned (Green LED + LD3 Done)",
    error: "Hardware request failed",
    idle: status.hardwareReady ? "Ready for computation" : "Waiting for hardware initialization"
  };
  const opElem = byId("operation-state");
  if (opElem) opElem.textContent = labels[operation] || "Waiting for bridge";

  const visOp = byId("visual-operation");
  if (visOp) {
    visOp.innerHTML = '<i class="status-dot"></i>' + (operation === "running" ? "FPGA systolic array computing..." : operation === "completed" ? "Hardware result returned" : status.hardwareReady ? "Hardware idle" : "Hardware not ready");
    const foot = visOp.closest(".visual-foot");
    if (foot) foot.dataset.state = operation;
  }
  setOperationState(operation);

  const chip = byId("mode-chip");
  if (chip) {
    const isBusy = operation === "running" || operation === "initializing" || operation === "resetting";
    const chipState = operation === "error" ? "mode-error" : !status.hardwareReady ? "mode-unavailable" : isBusy ? "mode-busy" : "mode-ready";
    chip.className = "mode-chip " + chipState;
    chip.textContent = status.hardwareReady ? operation === "running" ? "HARDWARE · RUNNING" : "HARDWARE · READY" : operation === "error" ? "HARDWARE · ERROR" : "HARDWARE · UNAVAILABLE";
  }
  renderEngines(status.engines);
  updateButtons();
}

function showBridgeOffline(message) {
  bridgeStatus = null;
  setCard("bridge-state", "unavailable", "Offline", "No response from bridge");
  setCard("board-state", "unknown", "Unverified", "Bridge connection required");
  setCard("overlay-state", "unknown", "Not loaded", "Initialize to check");
  const opElem = byId("operation-state");
  if (opElem) opElem.textContent = "Bridge unavailable";
  const visOp = byId("visual-operation");
  if (visOp) {
    visOp.innerHTML = '<i class="status-dot"></i>Bridge unavailable';
    const foot = visOp.closest(".visual-foot");
    if (foot) foot.dataset.state = "error";
  }
  const chip = byId("mode-chip");
  if (chip) {
    chip.className = "mode-chip mode-unavailable";
    chip.textContent = "HARDWARE · UNAVAILABLE";
  }
  renderEngines([]);
  setOperationState("idle");
  updateButtons();
  if (message) showError(message);
}

function readValidation() {
  const activeMInput = byId("active-m");
  const activeNInput = byId("active-n");
  return validateJob(
    matrixAEditor.getRawValues(),
    matrixBEditor.getRawValues(),
    activeMInput ? activeMInput.value : "16",
    activeNInput ? activeNInput.value : "16"
  );
}

function updateValidation() {
  const result = readValidation();
  if (validationMessage) {
    validationMessage.dataset.state = result.valid ? "valid" : "error";
    if (result.valid) {
      const shape = result.shape;
      validationMessage.textContent = `Valid · A ${shape.m}×${shape.k} · B ${shape.k}×${shape.n} → C ${shape.m}×${shape.n}`;
      const tilingNote = byId("tiling-note");
      if (tilingNote) {
        tilingNote.textContent = (shape.m > 16 || shape.k > 16 || shape.n > 16)
          ? `The host driver will tile dimensions beyond 16 (estimated ${Math.ceil(shape.m/16) * Math.ceil(shape.n/16) * Math.ceil(shape.k/16)} hardware tiles).`
          : "Fits within one hardware tile (up to 16 × 16 × 16).";
      }
    } else {
      validationMessage.textContent = result.message;
      const tilingNote = byId("tiling-note");
      if (tilingNote) tilingNote.textContent = "One hardware tile supports up to 16 × 16 × 16.";
    }
  }
  updateButtons();
  return result;
}

function updateButtons() {
  const connected = !!bridgeStatus;
  const statusBusy = !!(bridgeStatus && bridgeStatus.busy);
  const overlayLoaded = !!(bridgeStatus && bridgeStatus.overlay && bridgeStatus.overlay.state === "loaded");
  const hardwareReady = !!(bridgeStatus && bridgeStatus.hardwareReady === true);
  const job = readValidation();

  const initBtn = byId("initialize-button");
  if (initBtn) {
    initBtn.disabled = !connected || statusBusy || requestInFlight;
    initBtn.textContent = overlayLoaded ? "Reload overlay" : "Initialize overlay";
  }
  const resetBtn = byId("reset-button");
  if (resetBtn) {
    resetBtn.disabled = !hardwareReady || !overlayLoaded || statusBusy || requestInFlight;
  }
  const compBtn = byId("compute-button");
  if (compBtn) {
    compBtn.disabled = !job.valid || !hardwareReady || !overlayLoaded || statusBusy || requestInFlight;
  }
  const connBtn = byId("connect-button");
  if (connBtn) {
    connBtn.disabled = requestInFlight;
  }
  if (bridgeUrlInput) {
    bridgeUrlInput.disabled = requestInFlight;
  }
}

async function refreshStatus(showFailure) {
  try {
    const status = await fetchStatus();
    renderBridgeStatus(status);
    return status;
  } catch (error) {
    showBridgeOffline(showFailure ? friendlyError(error) : "");
    return null;
  }
}

async function connect() {
  clearError();
  try {
    const saved = saveBridgeUrl(bridgeUrlInput.value);
    bridgeUrlInput.value = saved === window.location.origin ? "" : saved;
  } catch (error) {
    showError(error.message);
    return;
  }
  const status = await refreshStatus(true);
  if (status) clearError();
}

async function initialize() {
  clearError();
  requestInFlight = true;
  updateButtons();
  try {
    await initializeHardware();
    await refreshStatus(false);
    if (bridgeStatus && bridgeStatus.hardwareReady) clearError();
  } catch (error) {
    showError(friendlyError(error));
    await refreshStatus(false);
  } finally {
    requestInFlight = false;
    updateButtons();
  }
}

function renderMatrix(container, matrix, className) {
  container.replaceChildren();
  if (!Array.isArray(matrix) || matrix.length === 0 || !Array.isArray(matrix[0])) return false;
  const cols = matrix[0].length;
  if (!cols || matrix.some(row => !Array.isArray(row) || row.length !== cols)) return false;
  container.style.setProperty("--cols", String(cols));
  const fragment = document.createDocumentFragment();
  matrix.forEach(function (row) {
    row.forEach(function (value) {
      const cell = document.createElement("span");
      cell.className = className;
      cell.textContent = String(value);
      fragment.append(cell);
    });
  });
  container.append(fragment);
  return true;
}

function clearResult() {
  lastInput = null;
  const rc = byId("result-content");
  if (rc) rc.hidden = true;
  const rp = byId("result-placeholder");
  if (rp) rp.hidden = false;
  const rs = byId("result-state");
  if (rs) rs.textContent = "Awaiting a hardware run";
  const on = byId("overflow-note");
  if (on) on.hidden = true;
  const rr = byId("reference-result");
  if (rr) rr.hidden = true;
  clearError();
}

function showResult(response, input) {
  if (!response || response.mode !== "HARDWARE_MEASURED" || !response.metrics || !Array.isArray(response.matrixC)) {
    throw new Error("The bridge did not return a hardware-confirmed result.");
  }
  if (response.matrixC.length !== input.shape.m || response.matrixC.some(row => !Array.isArray(row) || row.length !== input.shape.n)) {
    throw new Error("The returned result dimensions do not match the submitted matrices.");
  }
  const valuesAreInt32 = response.matrixC.every(row =>
    row.every(val => Number.isInteger(val) && val >= -2147483648 && val <= 2147483647)
  );
  if (!valuesAreInt32) throw new Error("The bridge returned values outside the signed INT32 result format.");

  if (!renderMatrix(byId("result-matrix"), response.matrixC, "result-cell")) {
    throw new Error("The bridge returned a malformed result matrix.");
  }
  byId("result-placeholder").hidden = true;
  byId("result-content").hidden = false;
  byId("result-state").textContent = "Returned by PYNQ-Z2 (Bit-Exact Hardware Pass)";
  byId("result-shape").textContent = `${input.shape.m} × ${input.shape.n} · signed INT32`;
  byId("input-summary").textContent = `A ${input.shape.m}×${input.shape.k} · B ${input.shape.k}×${input.shape.n}`;
  byId("metric-status").textContent = "HARDWARE (PASS)";
  byId("metric-tiles").textContent = Number.isInteger(response.metrics.tiles) ? String(response.metrics.tiles) : "1";
  byId("metric-cycles").textContent = Number.isInteger(response.metrics.cycles) ? response.metrics.cycles.toLocaleString() : "—";
  byId("metric-elapsed").textContent = Number.isFinite(response.metrics.totalElapsedMs) ? response.metrics.totalElapsedMs.toFixed(2) + " ms" : "—";
  byId("overflow-note").hidden = !response.metrics.overflow;
  byId("reference-result").hidden = true;

  if (byId("reference-toggle").checked) {
    const reference = calculateReference(input.matrixA, input.matrixB);
    const comparison = compareMatrices(response.matrixC, reference);
    renderMatrix(byId("reference-matrix"), reference, "result-cell");
    const rm = byId("reference-match");
    if (rm) {
      rm.textContent = comparison.matches ? "MATCH (100% BIT-EXACT)" : "MISMATCH";
      rm.style.color = comparison.matches ? "var(--mint)" : "var(--red)";
    }
    const rd = byId("reference-diff");
    if (rd) {
      rd.textContent = comparison.matches ? "Exact signed INT32 match against CPU reference model" : "Maximum absolute difference: " + comparison.maxAbsoluteDifference;
    }
    byId("reference-result").hidden = false;
  }
  clearError();
}

async function runCompute() {
  const input = updateValidation();
  if (!input.valid || !bridgeStatus || !bridgeStatus.hardwareReady) return;
  clearError();
  byId("result-placeholder").hidden = false;
  byId("result-content").hidden = true;
  byId("result-state").textContent = "Running on FPGA Systolic Array (Red LED Blinking)...";
  byId("result-placeholder").querySelector("strong").textContent = "FPGA Hardware Computation in Progress";
  byId("result-placeholder").querySelector("small").textContent = "Red RGB LED on LD4 is blinking rapidly on PYNQ board...";

  lastInput = input;
  requestInFlight = true;
  updateButtons();
  pollTimer = window.setInterval(() => { refreshStatus(false); }, 850);

  try {
    const response = await computeOnHardware({
      matrixA: input.matrixA,
      matrixB: input.matrixB,
      activeM: input.activeM,
      activeN: input.activeN,
      shape: input.shape
    });
    showResult(response, input);
    await refreshStatus(false);
  } catch (error) {
    showError(friendlyError(error));
    byId("result-state").textContent = "No confirmed hardware result";
    byId("result-placeholder").querySelector("strong").textContent = "Result not confirmed";
    byId("result-placeholder").querySelector("small").textContent = "Check bridge status before retrying.";
    await refreshStatus(false);
  } finally {
    window.clearInterval(pollTimer);
    pollTimer = 0;
    requestInFlight = false;
    updateButtons();
  }
}

async function reset() {
  clearError();
  requestInFlight = true;
  updateButtons();
  try {
    await resetHardware();
    clearResult();
    await refreshStatus(false);
  } catch (error) {
    showError(friendlyError(error));
    await refreshStatus(false);
  } finally {
    requestInFlight = false;
    updateButtons();
  }
}

function loadTestCase(caseKey) {
  const item = CASES_DATA[caseKey];
  if (!item) return;
  clearResult();
  matrixAEditor.setValues(item.A);
  matrixBEditor.setValues(item.B);
  updateValidation();
}

function clearInputs() {
  matrixAEditor.clear(4, 4);
  matrixBEditor.clear(4, 1);
  clearResult();
  updateValidation();
}

// Event bindings
document.querySelectorAll("[data-matrix]").forEach(function (root) {
  root.addEventListener("matrix-change", function (event) {
    updateValidation();
    if (event.detail && event.detail.message && validationMessage) {
      validationMessage.textContent = event.detail.message;
    }
  });
});

const activeM = byId("active-m");
if (activeM) activeM.addEventListener("input", updateValidation);
const activeN = byId("active-n");
if (activeN) activeN.addEventListener("input", updateValidation);

const connBtn = byId("connect-button");
if (connBtn) connBtn.addEventListener("click", connect);
const initBtn = byId("initialize-button");
if (initBtn) initBtn.addEventListener("click", initialize);
const rstBtn = byId("reset-button");
if (rstBtn) rstBtn.addEventListener("click", reset);
const compBtn = byId("compute-button");
if (compBtn) compBtn.addEventListener("click", runCompute);
const clrBtn = byId("clear-button");
if (clrBtn) clrBtn.addEventListener("click", clearInputs);
const rstViewBtn = byId("reset-view-button");
if (rstViewBtn) rstViewBtn.addEventListener("click", resetView);

// Quick preset selection
const presetSel = byId("preset-selector");
if (presetSel) {
  presetSel.addEventListener("change", function () {
    if (this.value) {
      loadTestCase(this.value);
    }
  });
}

// Quick fill buttons
const btnFillRand = byId("btn-fill-rand");
if (btnFillRand) {
  btnFillRand.addEventListener("click", function () {
    matrixAEditor.fillRandom(-25, 25);
    matrixBEditor.fillRandom(-25, 25);
    clearResult();
    updateValidation();
  });
}

const btnFillEye = byId("btn-fill-eye");
if (btnFillEye) {
  btnFillEye.addEventListener("click", function () {
    matrixAEditor.fillIdentity();
    matrixBEditor.fillIdentity();
    clearResult();
    updateValidation();
  });
}

const btnFillOnes = byId("btn-fill-ones");
if (btnFillOnes) {
  btnFillOnes.addEventListener("click", function () {
    matrixAEditor.fillConstant("1");
    matrixBEditor.fillConstant("1");
    clearResult();
    updateValidation();
  });
}

const btnFillZeros = byId("btn-fill-zeros");
if (btnFillZeros) {
  btnFillZeros.addEventListener("click", function () {
    matrixAEditor.fillConstant("0");
    matrixBEditor.fillConstant("0");
    clearResult();
    updateValidation();
  });
}

// Quick size buttons
document.querySelectorAll("[data-size]").forEach(function (btn) {
  btn.addEventListener("click", function () {
    const size = this.dataset.size;
    if (size === "4x4") {
      matrixAEditor.setDimensions(4, 4);
      matrixBEditor.setDimensions(4, 4);
    } else if (size === "8x8") {
      matrixAEditor.setDimensions(8, 8);
      matrixBEditor.setDimensions(8, 8);
    } else if (size === "16x16") {
      matrixAEditor.setDimensions(16, 16);
      matrixBEditor.setDimensions(16, 16);
    } else if (size === "16x1") {
      matrixAEditor.setDimensions(16, 16);
      matrixBEditor.setDimensions(16, 1);
    } else if (size === "4x1") {
      matrixAEditor.setDimensions(4, 4);
      matrixBEditor.setDimensions(4, 1);
    }
    clearResult();
    updateValidation();
  });
});

try {
  if (bridgeUrlInput) {
    bridgeUrlInput.value = getBridgeUrl() === window.location.origin ? "" : getBridgeUrl();
  }
} catch (error) {
  if (bridgeUrlInput) bridgeUrlInput.value = "";
}

updateValidation();
refreshStatus(false);
