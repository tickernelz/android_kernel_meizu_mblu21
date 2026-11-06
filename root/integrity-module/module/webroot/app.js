const BIN = "/data/adb/modules/playintegrityfix/bin/webui.sh";
const msg = document.getElementById("msg");

function rows(tbody, data, keys) {
  tbody.innerHTML = "";
  for (const k of keys) {
    const tr = document.createElement("tr");
    const a = document.createElement("td");
    a.textContent = k.replace(/_/g, " ");
    const b = document.createElement("td");
    const v = data[k] ?? "-";
    b.textContent = v;
    if (["keybox_ecdsa", "keybox_rsa"].includes(k)) b.className = v && v !== "0" ? "ok" : "bad";
    if (k === "keybox_chain") b.className = v === "google" ? "ok" : "bad";
    if (k === "keystore_maps") b.className = Number(v) >= 1 ? "ok" : "bad";
    tr.append(a, b);
    tbody.append(tr);
  }
}

async function run(cmd) {
  const r = await ksu.exec(`su -c "sh ${BIN} ${cmd}"`, { cwd: "/data/adb" });
  const out = {};
  for (const line of String(r.stdout || "").split("\n")) {
    const i = line.indexOf("=");
    if (i > 0) out[line.slice(0, i)] = line.slice(i + 1);
  }
  return { out, err: r.stderr || "" };
}

async function load() {
  const { out, err } = await run("status");
  rows(document.getElementById("provider"), out, ["provider_pid", "keystore_pid", "keystore_maps"]);
  rows(document.getElementById("keybox"), out, ["keybox_sha256", "keybox_bytes", "keybox_ecdsa", "keybox_rsa", "keybox_chain", "keybox_mtime", "keybox_source", "fetch_auto", "fetch_interval_h", "fetch_last"]);
  rows(document.getElementById("verdict"), out, ["verdict_device", "verdict_app", "verdict_licensing", "verdict_ts"]);
  if (err) msg.textContent = err;
}

document.getElementById("refresh").addEventListener("click", async () => {
  msg.textContent = "menyegarkan...";
  const r = await run("refresh");
  msg.textContent = r.err || "selesai";
  await load();
});

document.getElementById("check").addEventListener("click", async () => {
  msg.textContent = "memeriksa verdict...";
  const r = await run("verdict");
  msg.textContent = r.err || "selesai";
  await load();
});

load();
