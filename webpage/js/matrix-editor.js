const GRID_CELL_LIMIT = 2000;

function positiveInteger(value) {
  const number = Number(value);
  return Number.isSafeInteger(number) && number > 0 ? Math.min(number, 64) : null;
}

export class MatrixEditor {
  constructor(root, initialValues, onDimensionChange = null) {
    this.root = root;
    this.name = root.dataset.matrix || "M";
    this.rowInput = root.querySelector('[data-role="rows"]');
    this.colInput = root.querySelector('[data-role="cols"]');
    this.grid = root.querySelector('[data-role="grid"]');
    this.shape = root.querySelector('[data-role="shape"]');
    this.pasteArea = root.querySelector('[data-role="paste"]');
    this.onDimensionChange = onDimensionChange;
    this.values = (initialValues && initialValues.length > 0)
      ? initialValues.map(row => row.map(String))
      : [["0", "0"], ["0", "0"]];

    // Listen to both input and change so stepper arrows and keyboard typing update immediately
    this.rowInput.addEventListener("input", () => this.resizeFromFields(true));
    this.rowInput.addEventListener("change", () => this.resizeFromFields(true));
    this.colInput.addEventListener("input", () => this.resizeFromFields(true));
    this.colInput.addEventListener("change", () => this.resizeFromFields(true));

    this.grid.addEventListener("input", (event) => this.onCellInput(event));
    this.grid.addEventListener("keydown", (event) => this.onCellKeyDown(event));

    const applyBtn = root.querySelector('[data-role="apply-paste"]');
    if (applyBtn) {
      applyBtn.addEventListener("click", () => this.applyPaste());
    }

    this.render();
  }

  onCellInput(event) {
    const cell = event.target.closest("[data-row][data-col]");
    if (!cell || !this.values) return;
    const r = Number(cell.dataset.row);
    const c = Number(cell.dataset.col);
    if (this.values[r] !== undefined) {
      this.values[r][c] = cell.value;
    }
    this.validateCellVisual(cell);
    this.notifyChange();
  }

  onCellKeyDown(event) {
    // Convenient arrow key navigation across matrix grid
    const cell = event.target.closest("[data-row][data-col]");
    if (!cell) return;
    const r = Number(cell.dataset.row);
    const c = Number(cell.dataset.col);
    const rows = this.values ? this.values.length : 0;
    const cols = (this.values && this.values[0]) ? this.values[0].length : 0;

    let targetR = r;
    let targetC = c;

    if (event.key === "ArrowRight" && cell.selectionStart === cell.value.length) targetC = Math.min(cols - 1, c + 1);
    else if (event.key === "ArrowLeft" && cell.selectionEnd === 0) targetC = Math.max(0, c - 1);
    else if (event.key === "ArrowDown") targetR = Math.min(rows - 1, r + 1);
    else if (event.key === "ArrowUp") targetR = Math.max(0, r - 1);
    else if (event.key === "Enter") {
      event.preventDefault();
      targetR = Math.min(rows - 1, r + 1);
    } else {
      return;
    }

    if (targetR !== r || targetC !== c) {
      const targetCell = this.grid.querySelector(`[data-row="${targetR}"][data-col="${targetC}"]`);
      if (targetCell) targetCell.focus();
    }
  }

  validateCellVisual(cell) {
    const text = cell.value.trim();
    if (text === "") {
      cell.style.borderColor = "#E2CFB3";
      return;
    }
    const val = Number(text);
    if (!Number.isSafeInteger(val) || val < -128 || val > 127) {
      cell.style.borderColor = "#E05252";
      cell.style.backgroundColor = "#FFF0F0";
    } else {
      cell.style.borderColor = "#90C090";
      cell.style.backgroundColor = "#F9FFF9";
    }
  }

  resizeFromFields(notifyDimensions = false) {
    const rows = positiveInteger(this.rowInput.value);
    const cols = positiveInteger(this.colInput.value);
    if (!rows || !cols) {
      this.render();
      this.notifyChange();
      return;
    }

    if (rows * cols <= GRID_CELL_LIMIT) {
      const resized = [];
      for (let r = 0; r < rows; r += 1) {
        const row = [];
        for (let c = 0; c < cols; c += 1) {
          const prev = (this.values && this.values[r] && this.values[r][c] !== undefined)
            ? this.values[r][c]
            : (r === c && rows === cols ? "1" : "0");
          row.push(prev);
        }
        resized.push(row);
      }
      this.values = resized;
    } else {
      this.values = null;
    }

    this.render();
    this.notifyChange();

    if (notifyDimensions && typeof this.onDimensionChange === "function") {
      this.onDimensionChange(this.name, rows, cols);
    }
  }

  setDimensions(rows, cols, preserve = true) {
    rows = positiveInteger(rows) || 2;
    cols = positiveInteger(cols) || 2;
    this.rowInput.value = String(rows);
    this.colInput.value = String(cols);

    const resized = [];
    for (let r = 0; r < rows; r += 1) {
      const row = [];
      for (let c = 0; c < cols; c += 1) {
        if (preserve && this.values && this.values[r] && this.values[r][c] !== undefined) {
          row.push(this.values[r][c]);
        } else {
          row.push(r === c && rows === cols ? "1" : "0");
        }
      }
      resized.push(row);
    }
    this.values = resized;
    this.render();
    this.notifyChange();
  }

  applyPaste() {
    let content = (this.pasteArea ? this.pasteArea.value : "").trim();
    if (!content) {
      this.notifyChange("Paste numbers, a 1D vector [3, -1, 4], or a 2D matrix [[1, 2], [3, 4]].");
      return;
    }

    // 1. Try JSON / Python list parsing
    try {
      // Normalize single quotes or Python syntax if present
      const cleanJson = content.replace(/'/g, '"');
      const parsed = JSON.parse(cleanJson);
      if (Array.isArray(parsed)) {
        if (parsed.length > 0 && Array.isArray(parsed[0])) {
          // 2D matrix
          this.setValues(parsed.map(row => row.map(String)));
          return;
        } else if (parsed.length > 0 && !Array.isArray(parsed[0])) {
          // 1D vector
          // If pasted into Matrix B or user has cols=1, format as column vector (K x 1)
          if (this.name === "B" || this.colInput.value === "1") {
            this.setValues(parsed.map(val => [String(val)]));
          } else {
            // Format as 1 x K row vector
            this.setValues([parsed.map(String)]);
          }
          return;
        }
      }
    } catch (e) {
      // Fallback to text parsing
    }

    // 2. Text Parser: Strip all bracket formatting [ ] ( ) { }
    let stripped = content.replace(/[\[\]\(\)\{\}]/g, " ").trim();

    // Check if it's a 1D comma/space separated vector on a single line
    let lines = stripped.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
    if (lines.length === 1) {
      const tokens = lines[0].split(/[\s,;]+/).filter(Boolean);
      if (tokens.length > 1) {
        if (this.name === "B" || this.colInput.value === "1") {
          // Auto-convert to column vector
          this.setValues(tokens.map(t => [t]));
          return;
        } else if (tokens.length === Number(this.colInput.value)) {
          lines = [tokens.join(" ")];
        } else {
          // Check if square matrix
          const sqrt = Math.round(Math.sqrt(tokens.length));
          if (sqrt * sqrt === tokens.length) {
            const sq = [];
            for (let i = 0; i < sqrt; i++) sq.push(tokens.slice(i * sqrt, (i + 1) * sqrt));
            this.setValues(sq);
            return;
          }
        }
      }
    }

    // Multi-line rectangular parsing
    const rows = lines.map(line => line.split(/[\s,;]+/).filter(Boolean));
    const width = rows[0] ? rows[0].length : 0;
    if (!width || rows.some(row => row.length !== width)) {
      this.notifyChange("Pasted values must form a rectangular matrix or valid vector.");
      return;
    }

    this.setValues(rows);
  }

  setValues(values) {
    if (!values || values.length === 0) return;
    this.values = values.map(row => row.map(v => String(v).trim()));
    const r = this.values.length;
    const c = this.values[0] ? this.values[0].length : 0;
    this.rowInput.value = String(r);
    this.colInput.value = String(c);
    this.render();
    this.notifyChange();

    if (typeof this.onDimensionChange === "function") {
      this.onDimensionChange(this.name, r, c);
    }
  }

  fillRandom(min = -25, max = 25) {
    const rows = positiveInteger(this.rowInput.value) || 2;
    const cols = positiveInteger(this.colInput.value) || 2;
    const vals = [];
    for (let r = 0; r < rows; r++) {
      const row = [];
      for (let c = 0; c < cols; c++) {
        const rand = Math.floor(Math.random() * (max - min + 1)) + min;
        row.push(String(rand));
      }
      vals.push(row);
    }
    this.setValues(vals);
  }

  fillIdentity() {
    const rows = positiveInteger(this.rowInput.value) || 4;
    const cols = positiveInteger(this.colInput.value) || rows;
    const vals = [];
    for (let r = 0; r < rows; r++) {
      const row = [];
      for (let c = 0; c < cols; c++) {
        row.push(r === c ? "1" : "0");
      }
      vals.push(row);
    }
    this.setValues(vals);
  }

  fillConstant(val = "1") {
    const rows = positiveInteger(this.rowInput.value) || 2;
    const cols = positiveInteger(this.colInput.value) || 2;
    const vals = [];
    for (let r = 0; r < rows; r++) {
      const row = [];
      for (let c = 0; c < cols; c++) {
        row.push(String(val));
      }
      vals.push(row);
    }
    this.setValues(vals);
  }

  clear(rows = 2, cols = 2) {
    const rCount = rows || 2;
    const cCount = cols || 2;
    this.values = Array.from({ length: rCount }, () => Array.from({ length: cCount }, () => "0"));
    this.rowInput.value = String(rCount);
    this.colInput.value = String(cCount);
    if (this.pasteArea) this.pasteArea.value = "";
    this.render();
    this.notifyChange();
  }

  getRawValues() {
    const rows = positiveInteger(this.rowInput.value);
    const cols = positiveInteger(this.colInput.value);
    if (!rows || !cols) return { rows: rows, cols: cols, values: null };
    if (!this.values || this.values.length !== rows || this.values.some(row => row.length !== cols)) {
      return { rows: rows, cols: cols, values: null };
    }
    return { rows: rows, cols: cols, values: this.values.map(row => row.slice()) };
  }

  render() {
    const rows = positiveInteger(this.rowInput.value);
    const cols = positiveInteger(this.colInput.value);
    if (!rows || !cols) {
      if (this.shape) this.shape.textContent = "—";
      this.grid.replaceChildren();
      return;
    }
    if (this.shape) this.shape.textContent = `${rows} × ${cols}`;
    this.grid.replaceChildren();

    if (!this.values || rows * cols > GRID_CELL_LIMIT) {
      const note = document.createElement("p");
      note.className = "grid-limit-note";
      note.textContent = `Large matrix (${rows}×${cols}): cell editing is supported up to ${GRID_CELL_LIMIT} cells. Paste full values below.`;
      this.grid.append(note);
      return;
    }

    // Adapt cell size based on dimension so 16x16 fits cleanly without horizontal scrolling
    let cellWidth = 39;
    let fontSize = 10;
    if (cols > 12) {
      cellWidth = 32;
      fontSize = 9;
    } else if (cols > 8) {
      cellWidth = 35;
      fontSize = 9;
    }

    this.grid.style.gridTemplateColumns = `repeat(${cols}, ${cellWidth}px)`;
    const fragment = document.createDocumentFragment();

    for (let r = 0; r < rows; r += 1) {
      for (let c = 0; c < cols; c += 1) {
        const cell = document.createElement("input");
        cell.type = "number";
        cell.step = "1";
        cell.min = "-128";
        cell.max = "127";
        cell.inputMode = "numeric";
        cell.className = "matrix-cell";
        cell.style.width = `${cellWidth}px`;
        cell.style.fontSize = `${fontSize}px`;
        const val = (this.values[r] && this.values[r][c] !== undefined) ? this.values[r][c] : "0";
        cell.value = val;
        cell.dataset.row = String(r);
        cell.dataset.col = String(c);
        cell.setAttribute("aria-label", `Row ${r + 1}, Col ${c + 1}`);
        this.validateCellVisual(cell);
        fragment.append(cell);
      }
    }
    this.grid.append(fragment);
  }

  notifyChange(message) {
    this.root.dispatchEvent(new CustomEvent("matrix-change", { bubbles: true, detail: { message: message || "" } }));
  }
}
