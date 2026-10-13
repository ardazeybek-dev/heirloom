// heirloom playground — UI glue around the Gleam core in ./heirloom.js.
// Every operation runs locally; the page's CSP forbids network requests.
import * as hl from "./heirloom.js";

const $ = (selector) => document.querySelector(selector);
const RECOVERY_URL = "ardazeybek-dev.github.io/heirloom";
const encoder = new TextEncoder();

// ---------------------------------------------------------------- tabs
const tabs = [$("#tab-split"), $("#tab-recover")];
function selectTab(name) {
  for (const tab of tabs) {
    const active = tab.id === `tab-${name}`;
    tab.setAttribute("aria-selected", String(active));
    tab.tabIndex = active ? 0 : -1;
    $(`#${tab.getAttribute("aria-controls")}`).hidden = !active;
  }
}
tabs.forEach((tab, i) => {
  tab.addEventListener("click", () => selectTab(tab.id.replace("tab-", "")));
  tab.addEventListener("keydown", (e) => {
    if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
    const next = tabs[(i + (e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length];
    next.focus();
    next.click();
  });
});
document.querySelectorAll("[data-tab-link]").forEach((link) =>
  link.addEventListener("click", () => selectTab(link.dataset.tabLink)),
);

// ---------------------------------------------------------------- hero fan
function renderFan() {
  const demo = hl.split("heirloom keeps this safe", false, 3, 5, true, "", "", "M", "a4", RECOVERY_URL);
  if (!demo.isOk()) return;
  const view = demo[0];
  const fan = $("#fan");
  const cards = view.cards.toArray();
  fan.innerHTML = cards
    .map((card, i) => {
      const qr = hl.qr_svg(card.compact, "M", "#14161c");
      const rows = card.rows.split("\n").slice(0, 3).map((r) => r.slice(4, 18)).join("\n");
      return `<div class="mini" data-i="${i}" aria-hidden="true">
        <header><span>heirloom</span><span>Card ${card.index} of ${card.total}</span></header>
        <div class="mini-qr">${qr.isOk() ? qr[0] : ""}</div>
        <div class="mini-rows">${rows}</div></div>`;
    })
    .join("");
  $("#fan-set").textContent = `set ${view.fingerprint}`;
  const minis = [...fan.querySelectorAll(".mini")];
  const spread = (amount) =>
    minis.forEach((m, i) => {
      const offset = i - (minis.length - 1) / 2;
      m.style.transform = `rotate(${offset * amount}deg) translateY(${Math.abs(offset) * amount * 0.6}px)`;
      m.style.zIndex = String(10 - Math.abs(Math.round(offset)));
    });
  spread(9);
  fan.addEventListener("mouseenter", () => spread(14));
  fan.addEventListener("mouseleave", () => spread(9));
}

// ---------------------------------------------------------------- split form
const thresholdInput = $("#threshold");
const sharesInput = $("#shares");
const secretInput = $("#secret");
const holdersBox = $("#holders");
let lastSplit = null;

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

function readKN() {
  let n = clamp(parseInt(sharesInput.value, 10) || 5, 2, 16);
  let k = clamp(parseInt(thresholdInput.value, 10) || 3, 2, n);
  return { k, n };
}

function syncKN() {
  const { k, n } = readKN();
  thresholdInput.value = k;
  sharesInput.value = n;
  $("#pips").innerHTML = Array.from({ length: n }, (_, i) => `<span class="pip${i < k ? " need" : ""}"></span>`).join("");
  const spare = n - k;
  $("#kn-text").innerHTML = `Any <b>${k}</b> of <b>${n}</b> recover · <b>${spare}</b> can be lost` +
    (spare === 0 ? " — <span style=\"color:var(--bad)\">no card may be lost</span>" : "");
  const existing = [...holdersBox.querySelectorAll("input")].map((input) => input.value);
  holdersBox.innerHTML = Array.from({ length: n }, (_, i) =>
    `<label class="holder"><span>#${i + 1}</span><input type="text" maxlength="40" placeholder="Holder ${i + 1}" aria-label="Holder of card ${i + 1}" value="${escapeAttr(existing[i] ?? "")}"></label>`,
  ).join("");
}

function escapeAttr(text) {
  return text.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
}

document.querySelectorAll("[data-step]").forEach((button) =>
  button.addEventListener("click", () => {
    const [name, delta] = button.dataset.step.split(":");
    const input = name === "threshold" ? thresholdInput : sharesInput;
    input.value = (parseInt(input.value, 10) || 0) + Number(delta);
    if (name === "shares" && parseInt(thresholdInput.value, 10) > parseInt(input.value, 10)) {
      thresholdInput.value = input.value;
    }
    if (name === "threshold" && parseInt(input.value, 10) > parseInt(sharesInput.value, 10)) {
      sharesInput.value = input.value;
    }
    syncKN();
  }),
);
[thresholdInput, sharesInput].forEach((input) => input.addEventListener("change", syncKN));

const kind = () => document.querySelector('input[name="kind"]:checked').value;
function updateSecretHint() {
  const value = secretInput.value;
  const bytes = kind() === "hex" ? Math.floor(value.replace(/[\s:]/g, "").replace(/^0x/, "").length / 2) : encoder.encode(value).length;
  $("#secret-hint").textContent = value ? `${bytes} of 512 bytes · never leaves this tab` : "Never leaves this tab. Up to 512 bytes.";
}
secretInput.addEventListener("input", updateSecretHint);
document.querySelectorAll('input[name="kind"]').forEach((r) => r.addEventListener("change", () => {
  secretInput.placeholder = kind() === "hex" ? "e.g. 3f9a 0c11 … (keys, wallet seeds)" : "e.g. my vault master password, or a list of recovery codes";
  updateSecretHint();
}));

$("#toggle-mask").addEventListener("click", (e) => {
  const button = e.currentTarget;
  const shown = button.getAttribute("aria-pressed") === "true";
  button.setAttribute("aria-pressed", String(!shown));
  button.setAttribute("aria-label", shown ? "Show secret" : "Hide secret");
  secretInput.classList.toggle("masked", shown);
});

$("#split-form").addEventListener("submit", (e) => {
  e.preventDefault();
  const error = $("#split-error");
  const { k, n } = readKN();
  const holders = [...holdersBox.querySelectorAll("input")].map((input) => input.value.trim()).join("\n");
  const result = hl.split(
    secretInput.value, kind() === "hex", k, n, $("#pad").checked,
    $("#label").value.trim(), holders, $("#ecl").value, $("#paper").value, RECOVERY_URL,
  );
  if (!result.isOk()) {
    error.textContent = capitalise(result[0]) + ".";
    error.hidden = false;
    return;
  }
  error.hidden = true;
  lastSplit = result[0];
  $("#out-set").textContent = lastSplit.fingerprint;
  $("#out-line").textContent = `${n} cards · any ${k} recover · ${lastSplit.share_bytes} bytes per card · QR version ${lastSplit.qr_version}`;
  $("#preview").srcdoc = lastSplit.sheet_html;
  const output = $("#split-output");
  output.hidden = false;
  output.scrollIntoView({ behavior: "smooth", block: "start" });
});

$("#print").addEventListener("click", () => $("#preview").contentWindow?.print());
$("#download").addEventListener("click", () => {
  if (!lastSplit) return;
  const url = URL.createObjectURL(new Blob([lastSplit.sheet_html], { type: "text/html" }));
  const a = Object.assign(document.createElement("a"), { href: url, download: `heirloom-cards-${lastSplit.fingerprint}.html` });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
$("#copy-text").addEventListener("click", async (e) => {
  if (!lastSplit) return;
  const text = lastSplit.cards.toArray()
    .map((c) => `Card ${c.index} of ${c.total} · any ${c.threshold} recover · set ${c.fingerprint}\n${c.compact}\n${c.rows}`)
    .join("\n\n");
  await copy(text, e.currentTarget);
});

async function copy(text, button) {
  try {
    await navigator.clipboard.writeText(text);
    const label = button.textContent;
    button.textContent = "Copied ✓";
    setTimeout(() => (button.textContent = label), 1400);
  } catch {
    button.textContent = "Copy blocked";
  }
}

const capitalise = (s) => s.charAt(0).toUpperCase() + s.slice(1);

// ---------------------------------------------------------------- recover
const cardsInput = $("#cards-input");

function refreshStatus() {
  const statuses = hl.inspect(cardsInput.value).toArray();
  const good = statuses.filter((s) => s.ok);
  const sets = [...new Set(good.map((s) => s.fingerprint))];
  const unique = new Set(good.map((s) => `${s.fingerprint}#${s.index}`)).size;
  const need = good[0]?.threshold ?? 0;
  const chips = $("#chips");
  chips.innerHTML = statuses
    .map((s, i) => s.ok
      ? `<li class="chip ok"><span>Card <b>#${s.index}</b> of ${s.total}</span><span class="meta">set ${s.fingerprint}</span></li>`
      : `<li class="chip bad"><span>Card ${i + 1}: ${escapeAttr(s.message)}</span></li>`)
    .join("");
  const bar = $("#progress-bar");
  const text = $("#progress-text");
  const ready = need > 0 && unique >= need && sets.length === 1 && good.length === statuses.length;
  bar.style.width = need ? `${Math.min(100, (unique / need) * 100)}%` : "0%";
  bar.classList.toggle("full", ready);
  if (!statuses.length) text.textContent = "No cards yet.";
  else if (sets.length > 1) text.textContent = "These cards come from different sets.";
  else if (!need) text.textContent = "Fix the card errors below.";
  else if (unique >= need) text.textContent = `${unique} of ${need} cards — ready.` + (unique > need ? " Extra cards will be cross-checked." : "");
  else text.textContent = `${unique} of ${need} cards — ${need - unique} more needed.`;
  $("#recover-btn").disabled = !ready;
  $("#recover-error").hidden = true;
}
cardsInput.addEventListener("input", refreshStatus);

$("#recover-btn").addEventListener("click", () => {
  const result = hl.recover(cardsInput.value);
  const error = $("#recover-error");
  if (!result.isOk()) {
    error.textContent = capitalise(result[0]) + ".";
    error.hidden = false;
    return;
  }
  const r = result[0];
  const out = $("#secret-out");
  out.textContent = r.is_text ? r.text : r.hex;
  out.classList.add("blurred");
  $("#reveal").hidden = false;
  const used = r.used.toArray().map((x) => `#${x}`).join(" ");
  const suspicious = r.suspicious.toArray();
  $("#result-meta").innerHTML =
    `Set ${r.fingerprint} · used cards ${used}${r.is_text ? "" : " · binary secret, shown as hex"}` +
    (suspicious.length ? `<br><b style="color:var(--bad)">Ignored inconsistent card(s): ${suspicious.map((x) => "#" + x).join(" ")}</b> — damaged or forged.` : "");
  $("#result").hidden = false;
});

$("#reveal").addEventListener("click", (e) => {
  $("#secret-out").classList.remove("blurred");
  e.currentTarget.hidden = true;
});
$("#copy-secret").addEventListener("click", (e) => copy($("#secret-out").textContent, e.currentTarget));
$("#clear").addEventListener("click", () => {
  cardsInput.value = "";
  $("#secret-out").textContent = "";
  $("#result").hidden = true;
  refreshStatus();
});

$("#example").addEventListener("click", () => {
  const demo = hl.split("correct horse battery staple", false, 3, 5, true, "Demo", "", "M", "a4", RECOVERY_URL);
  const cards = demo[0].cards.toArray();
  // Mix both text forms: two QR texts and one card typed in as rows.
  cardsInput.value = [cards[0].compact, cards[2].rows, cards[4].compact].join("\n\n");
  refreshStatus();
  cardsInput.focus();
});

// QR scanning via the built-in BarcodeDetector (Chromium, Android, Safari 17+).
const hasDetector = "BarcodeDetector" in window;
let detector = null;
async function getDetector() {
  if (!detector) {
    const formats = await window.BarcodeDetector.getSupportedFormats?.() ?? ["qr_code"];
    if (!formats.includes("qr_code")) throw new Error("no QR support");
    detector = new window.BarcodeDetector({ formats: ["qr_code"] });
  }
  return detector;
}

function addScanned(value) {
  if (!/^hl1:/i.test(value.trim())) return false;
  if (cardsInput.value.includes(value.trim())) return false;
  cardsInput.value = (cardsInput.value.trim() ? cardsInput.value.trim() + "\n\n" : "") + value.trim();
  refreshStatus();
  return true;
}

if (!hasDetector) {
  $("#scan-camera").disabled = true;
  $("#scan-file").disabled = true;
  $("#scan-file").parentElement.classList.add("is-disabled");
  $("#scan-hint").textContent = "QR scanning needs Chrome, Edge or Android — or type the rows.";
}

let stream = null;
$("#scan-camera").addEventListener("click", async (e) => {
  const button = e.currentTarget;
  const video = $("#camera");
  if (stream) {
    stream.getTracks().forEach((t) => t.stop());
    stream = null;
    video.hidden = true;
    button.textContent = "Scan with camera";
    return;
  }
  try {
    const d = await getDetector();
    stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
    video.srcObject = stream;
    video.hidden = false;
    await video.play();
    button.textContent = "Stop camera";
    const tick = async () => {
      if (!stream) return;
      try {
        for (const code of await d.detect(video)) {
          if (addScanned(code.rawValue)) $("#scan-hint").textContent = "Card added ✓ — show the next one.";
        }
      } catch { /* frame not ready */ }
      requestAnimationFrame(tick);
    };
    tick();
  } catch {
    $("#scan-hint").textContent = "Camera unavailable — try “From a photo” or type the rows.";
  }
});

$("#scan-file").addEventListener("change", async (e) => {
  const file = e.target.files?.[0];
  if (!file) return;
  try {
    const d = await getDetector();
    const codes = await d.detect(await createImageBitmap(file));
    const added = codes.filter((c) => addScanned(c.rawValue)).length;
    $("#scan-hint").textContent = added ? `Added ${added} card${added > 1 ? "s" : ""} from the photo ✓` : "No heirloom QR found in that photo.";
  } catch {
    $("#scan-hint").textContent = "Could not read that image.";
  }
  e.target.value = "";
});

// ---------------------------------------------------------------- curve demo
const svgNS = "http://www.w3.org/2000/svg";
const curve = $("#curve");
const X0 = 54, X1 = 540, Y0 = 300, Y1 = 22, XMAX = 5.4, YMIN = -1.5, YMAX = 7.5;
const px = (x) => X0 + (x / XMAX) * (X1 - X0);
const py = (y) => Y0 - ((y - YMIN) / (YMAX - YMIN)) * (Y0 - Y1);
const secretY = 2.2, coefA = 1.9, coefB = -0.33;
const f = (x, s = secretY, a = coefA, b = coefB) => s + a * x + b * x * x;

function el(name, attrs, parent = curve) {
  const node = document.createElementNS(svgNS, name);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  parent.append(node);
  return node;
}

function pathFor(fn) {
  let d = "";
  for (let x = 0; x <= XMAX + 1e-9; x += 0.05) d += `${d ? "L" : "M"}${px(x).toFixed(1)} ${py(fn(x)).toFixed(1)}`;
  return d;
}

function drawCurve(held) {
  curve.innerHTML = "";
  const defs = el("defs", {});
  const clip = el("clipPath", { id: "plot" }, defs);
  el("rect", { x: X0, y: Y1 - 10, width: X1 - X0, height: Y0 - Y1 + 10 }, clip);
  // axes
  el("line", { x1: X0, y1: Y1 - 8, x2: X0, y2: Y0, style: "stroke:var(--ink-2);stroke-width:1.5" });
  el("line", { x1: X0, y1: py(0), x2: X1, y2: py(0), style: "stroke:var(--line);stroke-width:1.5" });
  for (let i = 1; i <= 5; i++) {
    el("text", { x: px(i), y: Y0 + 26, "text-anchor": "middle", style: "fill:var(--muted);font:600 12px var(--sans)" }).textContent = `card ${i}`;
    el("line", { x1: px(i), y1: Y1, x2: px(i), y2: Y0, style: "stroke:var(--line);stroke-dasharray:2 5" });
  }
  el("text", { x: X0 - 10, y: Y1 + 4, "text-anchor": "end", style: "fill:var(--muted);font:600 11px var(--sans)" }).textContent = "value";
  const heldXs = [[3], [1, 3], [1, 3, 4]][held - 1];
  const group = el("g", { "clip-path": "url(#plot)" });

  let intercepts = [];
  if (held === 3) {
    el("path", { d: pathFor((x) => f(x)), style: "fill:none;stroke:var(--brass);stroke-width:3;stroke-linecap:round" }, group);
    intercepts = [secretY];
  } else {
    const candidates = [-1, -0.2, 0.6, 1.4, 2.2, 3.0, 3.8, 4.6, 5.4, 6.2];
    candidates.forEach((s, i) => {
      let a, b;
      if (held === 2) {
        const y1 = f(1), y3 = f(3);
        b = (y3 - 3 * y1 + 2 * s) / 6;
        a = y1 - s - b;
      } else {
        b = [-0.6, -0.35, -0.1, 0.15, 0.4][i % 5];
        a = (f(3) - s - 9 * b) / 3;
      }
      el("path", { d: pathFor((x) => f(x, s, a, b)), style: `fill:none;stroke:var(--muted);stroke-width:1.6;opacity:${0.25 + (i % 3) * 0.12}` }, group);
    });
    intercepts = candidates;
  }
  // card points: held ones solid, the rest hollow
  for (let i = 1; i <= 5; i++) {
    const isHeld = heldXs.includes(i);
    el("circle", { cx: px(i), cy: py(f(i)), r: isHeld ? 7 : 5,
      style: isHeld ? "fill:var(--ink);stroke:var(--surface);stroke-width:2.5" : "fill:none;stroke:var(--muted);stroke-width:1.5;opacity:.5" });
  }
  // the secret on the vertical axis
  intercepts.forEach((y) => {
    if (y < YMIN || y > YMAX) return;
    el("circle", { cx: X0, cy: py(y), r: held === 3 ? 8 : 4.5,
      style: held === 3 ? "fill:var(--brass);stroke:var(--surface);stroke-width:3" : "fill:var(--muted);opacity:.55" });
  });
  const label = held === 3 ? "the secret — exactly one" : "the secret could be any of these";
  el("text", { x: X0 + 14, y: held === 3 ? py(secretY) + 5 : Y1 + 12, style: `fill:${held === 3 ? "var(--brass)" : "var(--muted)"};font:700 13px var(--sans)` }).textContent = label;
}

document.querySelectorAll('input[name="held"]').forEach((r) =>
  r.addEventListener("change", () => drawCurve(Number(r.value))),
);

// ---------------------------------------------------------------- boot
syncKN();
renderFan();
drawCurve(3);
refreshStatus();
