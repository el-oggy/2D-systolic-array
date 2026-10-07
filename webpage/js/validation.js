function parseMatrix(raw, label) {
  if (!raw.values) return { error: "Enter all " + label + " values, or paste a complete matrix." };
  const parsed = [];
  for (let r = 0; r < raw.values.length; r += 1) {
    const row = [];
    for (let c = 0; c < raw.values[r].length; c += 1) {
      const text = String(raw.values[r][c]).trim();
      if (!text) return { error: label + " has an empty value at row " + (r + 1) + ", column " + (c + 1) + "." };
      const value = Number(text);
      if (!Number.isSafeInteger(value)) return { error: label + " values must be whole numbers." };
      if (value < -128 || value > 127) return { error: label + " values must stay between −128 and 127." };
      row.push(value);
    }
    parsed.push(row);
  }
  return { value: parsed };
}

export function validateJob(rawA, rawB, activeMValue, activeNValue) {
  if (!rawA.rows || !rawA.cols || !rawB.rows || !rawB.cols) {
    return { valid: false, message: "Matrix dimensions must be positive whole numbers." };
  }
  if (rawA.rows !== rawA.values?.length || rawA.cols !== rawA.values?.[0]?.length) {
    return { valid: false, message: "Enter all Matrix A values, or paste a complete matrix." };
  }
  if (rawB.rows !== rawB.values?.length || rawB.cols !== rawB.values?.[0]?.length) {
    return { valid: false, message: "Enter all Matrix B values, or paste a complete matrix." };
  }
  if (rawA.cols !== rawB.rows) {
    return { valid: false, message: "Dimension mismatch: A has " + rawA.cols + " columns but B has " + rawB.rows + " rows." };
  }
  const activeM = Number(activeMValue);
  const activeN = Number(activeNValue);
  if (!Number.isInteger(activeM) || activeM < 1 || activeM > 16) {
    return { valid: false, message: "Active rows must be a whole number from 1 to 16." };
  }
  if (!Number.isInteger(activeN) || activeN < 1 || activeN > 16) {
    return { valid: false, message: "Active columns must be a whole number from 1 to 16." };
  }
  const a = parseMatrix(rawA, "Matrix A");
  if (a.error) return { valid: false, message: a.error };
  const b = parseMatrix(rawB, "Matrix B");
  if (b.error) return { valid: false, message: b.error };
  return {
    valid: true,
    matrixA: a.value,
    matrixB: b.value,
    activeM: activeM,
    activeN: activeN,
    shape: { m: rawA.rows, k: rawA.cols, n: rawB.cols }
  };
}

export function calculateReference(matrixA, matrixB) {
  const rows = matrixA.length;
  const shared = matrixA[0].length;
  const cols = matrixB[0].length;
  const output = [];
  for (let r = 0; r < rows; r += 1) {
    const row = [];
    for (let c = 0; c < cols; c += 1) {
      let sum = 0n;
      for (let k = 0; k < shared; k += 1) {
        sum += BigInt(matrixA[r][k]) * BigInt(matrixB[k][c]);
      }
      row.push(Number(BigInt.asIntN(32, sum)));
    }
    output.push(row);
  }
  return output;
}

export function compareMatrices(actual, reference) {
  let matches = true;
  let maxAbsoluteDifference = 0;
  for (let r = 0; r < actual.length; r += 1) {
    for (let c = 0; c < actual[r].length; c += 1) {
      const diff = Math.abs(Number(actual[r][c]) - Number(reference[r][c]));
      if (diff !== 0) matches = false;
      if (diff > maxAbsoluteDifference) maxAbsoluteDifference = diff;
    }
  }
  return { matches: matches, maxAbsoluteDifference: maxAbsoluteDifference };
}
