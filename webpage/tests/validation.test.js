import test from "node:test";
import assert from "node:assert/strict";
import { calculateReference, compareMatrices, validateJob } from "../js/validation.js";

function raw(values) {
  return {
    rows: values.length,
    cols: values[0] ? values[0].length : 0,
    values: values.map(function (row) { return row.map(String); })
  };
}

test("validates a signed INT8 matrix multiply job", function () {
  const result = validateJob(raw([[1, -2, 3], [4, 5, -6]]), raw([[1, 2], [-3, 4], [5, -6]]), "16", "16");
  assert.equal(result.valid, true);
  assert.deepEqual(result.shape, { m: 2, k: 3, n: 2 });
});

test("accepts INT8 boundaries and rejects out-of-range values", function () {
  assert.equal(validateJob(raw([[-128, 127]]), raw([[1], [1]]), "1", "1").valid, true);
  const result = validateJob(raw([[128]]), raw([[1]]), "1", "1");
  assert.equal(result.valid, false);
  assert.match(result.message, /−128 and 127/);
});

test("rejects mismatched dimensions, empty cells, and unsupported active regions", function () {
  assert.match(validateJob(raw([[1, 2]]), raw([[3]]), "1", "1").message, /Dimension mismatch/);
  assert.match(validateJob(raw([[""]]), raw([[1]]), "1", "1").message, /empty value/);
  assert.match(validateJob(raw([[1]]), raw([[1]]), "17", "1").message, /from 1 to 16/);
});

test("keeps larger host-tiled matrix shapes valid", function () {
  const a = Array.from({ length: 17 }, function () { return Array.from({ length: 17 }, function () { return "1"; }); });
  const b = Array.from({ length: 17 }, function () { return Array.from({ length: 18 }, function () { return "1"; }); });
  const result = validateJob(raw(a), raw(b), "16", "16");
  assert.equal(result.valid, true);
  assert.deepEqual(result.shape, { m: 17, k: 17, n: 18 });
});

test("reference matches signed INT32 wrap semantics", function () {
  const actual = calculateReference([[127, 127, 127]], [[127], [127], [127]]);
  const expected = Number(BigInt.asIntN(32, 3n * 127n * 127n));
  assert.deepEqual(actual, [[expected]]);
  assert.deepEqual(compareMatrices(actual, [[expected]]), { matches: true, maxAbsoluteDifference: 0 });
});
