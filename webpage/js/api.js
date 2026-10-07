const STORAGE_KEY = "adaptive-systolic-array-bridge-url";

export function getBridgeUrl() {
  const saved = window.localStorage.getItem(STORAGE_KEY);
  return (saved && saved.trim()) || window.location.origin;
}

export function saveBridgeUrl(value) {
  const raw = (value || "").trim();
  const url = raw || window.location.origin;
  const parsed = new URL(url);
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error("Use an http:// or https:// bridge address.");
  }
  window.localStorage.setItem(STORAGE_KEY, parsed.origin);
  return parsed.origin;
}

async function request(path, options) {
  let response;
  try {
    response = await fetch(getBridgeUrl() + path, { cache: "no-store", ...options });
  } catch (error) {
    const unavailable = new Error("Could not reach the hardware bridge. Check its address and local network connection.");
    unavailable.code = "bridge_unavailable";
    throw unavailable;
  }
  let payload;
  try {
    payload = await response.json();
  } catch (error) {
    const malformed = new Error("The bridge returned a response the page could not read.");
    malformed.code = "malformed_response";
    throw malformed;
  }
  if (!response.ok) {
    const detail = payload && payload.error;
    const failure = new Error((detail && detail.message) || "The bridge rejected the request.");
    failure.code = (detail && detail.code) || "bridge_error";
    failure.status = response.status;
    throw failure;
  }
  return payload;
}

export function fetchStatus() {
  return request("/api/status", { method: "GET" });
}

export function initializeHardware() {
  return request("/api/initialize", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
}

export function resetHardware() {
  return request("/api/reset", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
}

export function computeOnHardware(payload) {
  return request("/api/compute", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
}
