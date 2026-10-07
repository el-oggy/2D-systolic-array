import * as THREE from "../vendor/three.module.js";

const mount = document.getElementById("three-scene");
const fallback = document.getElementById("scene-fallback");
let renderer = null;
let camera = null;
let scene = null;
let fabric = null;
let meshMaterials = [];
let active = false;
let animationFrame = 0;
let startTime = 0;
let pointer = null;
let resizeObserver = null;
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function addEngine(centerX, color) {
  const engine = new THREE.Group();
  engine.position.x = centerX;
  const geometry = new THREE.BoxGeometry(0.47, 0.2, 0.47);
  const material = new THREE.MeshStandardMaterial({
    color: color,
    emissive: color,
    emissiveIntensity: 0.12,
    roughness: 0.62,
    metalness: 0.12
  });
  meshMaterials.push(material);
  const wirePoints = [];
  const spacing = 0.66;
  for (let row = 0; row < 16; row += 1) {
    for (let col = 0; col < 16; col += 1) {
      const pe = new THREE.Mesh(geometry, material);
      pe.position.set((col - 7.5) * spacing, 0, (7.5 - row) * spacing);
      engine.add(pe);
      if (col < 15) {
        wirePoints.push(
          new THREE.Vector3((col - 7.5) * spacing + centerX, 0.035, (7.5 - row) * spacing),
          new THREE.Vector3((col + 1 - 7.5) * spacing + centerX, 0.035, (7.5 - row) * spacing)
        );
      }
      if (row < 15) {
        wirePoints.push(
          new THREE.Vector3((col - 7.5) * spacing + centerX, 0.035, (7.5 - row) * spacing),
          new THREE.Vector3((col - 7.5) * spacing + centerX, 0.035, (7.5 - row - 1) * spacing)
        );
      }
    }
  }
  fabric.add(engine);
  const wires = new THREE.BufferGeometry().setFromPoints(wirePoints);
  const wireMaterial = new THREE.LineBasicMaterial({ color: color, transparent: true, opacity: 0.2 });
  scene.add(new THREE.LineSegments(wires, wireMaterial));
}

function resize() {
  if (!renderer || !camera) return;
  const width = Math.max(1, mount.clientWidth);
  const height = Math.max(1, mount.clientHeight);
  renderer.setSize(width, height, false);
  const aspect = width / height;
  const frustumHeight = 18;
  camera.left = -frustumHeight * aspect / 2;
  camera.right = frustumHeight * aspect / 2;
  camera.top = frustumHeight / 2;
  camera.bottom = -frustumHeight / 2;
  camera.updateProjectionMatrix();
  scheduleRender();
}

function draw(timestamp) {
  animationFrame = 0;
  if (active && !reducedMotion) {
    if (!startTime) startTime = timestamp;
    const wave = 0.08 + (Math.sin((timestamp - startTime) / 390) + 1) * 0.075;
    meshMaterials.forEach(function (material) { material.emissiveIntensity = wave; });
  } else {
    meshMaterials.forEach(function (material) { material.emissiveIntensity = 0.12; });
  }
  if (renderer && scene && camera) renderer.render(scene, camera);
  if (active && !reducedMotion) animationFrame = window.requestAnimationFrame(draw);
}

function scheduleRender() {
  if (!animationFrame) animationFrame = window.requestAnimationFrame(draw);
}

function setupInteraction() {
  mount.addEventListener("pointerdown", function (event) {
    pointer = { id: event.pointerId, x: event.clientX, y: event.clientY };
    mount.setPointerCapture(event.pointerId);
  });
  mount.addEventListener("pointermove", function (event) {
    if (!pointer || pointer.id !== event.pointerId || !fabric) return;
    const dx = event.clientX - pointer.x;
    const dy = event.clientY - pointer.y;
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    fabric.rotation.y += dx * 0.006;
    fabric.rotation.x = Math.max(-0.32, Math.min(0.32, fabric.rotation.x + dy * 0.004));
    scheduleRender();
  });
  const finish = function () { pointer = null; };
  mount.addEventListener("pointerup", finish);
  mount.addEventListener("pointercancel", finish);
  mount.addEventListener("wheel", function (event) {
    event.preventDefault();
    camera.zoom = Math.max(0.72, Math.min(1.65, camera.zoom - event.deltaY * 0.0007));
    camera.updateProjectionMatrix();
    scheduleRender();
  }, { passive: false });
}

function createScene() {
  try {
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0xfff7e9);
    camera = new THREE.OrthographicCamera(-14, 14, 9, -9, 0.1, 100);
    camera.position.set(0, 19, 26);
    camera.lookAt(0, 0, 0);
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.8));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.setClearColor(0xfff7e9, 1);
    mount.append(renderer.domElement);
    scene.add(new THREE.HemisphereLight(0xfffbf2, 0xd7bea0, 1.8));
    const key = new THREE.DirectionalLight(0xffffff, 2.0);
    key.position.set(-6, 15, 12);
    scene.add(key);
    fabric = new THREE.Group();
    fabric.rotation.x = -0.04;
    scene.add(fabric);
    addEngine(-6.05, 0xff8a24);
    addEngine(6.05, 0x8a5634);
    setupInteraction();
    resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(mount);
    resize();
  } catch (error) {
    fallback.hidden = false;
    mount.setAttribute("aria-label", "Three.js visualization could not be created in this browser.");
  }
}

export function setOperationState(operation) {
  active = operation === "running";
  if (!active) startTime = 0;
  scheduleRender();
}

export function resetView() {
  if (!fabric || !camera) return;
  fabric.rotation.set(-0.04, 0, 0);
  camera.zoom = 1;
  camera.updateProjectionMatrix();
  scheduleRender();
}

createScene();
