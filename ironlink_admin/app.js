/* IronLink Ops Panel — dependency-free SPA against the admin API. */
"use strict";

const API = localStorage.getItem("mil_api_base") || "/api/v1";
let TOKEN = sessionStorage.getItem("mil_admin_token") || "";
let statsTimer = null;
let pendingAction = null; // {userId, action}

const $ = (sel) => document.querySelector(sel);

// ── API helper ────────────────────────────────────────────────────────────────

async function api(path, options = {}) {
  const res = await fetch(API + path, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${TOKEN}`,
      ...(options.headers || {}),
    },
  });
  if (res.status === 401 || res.status === 403) {
    logout();
    throw new Error("انتهت الجلسة أو الصلاحية غير كافية");
  }
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.detail || `HTTP ${res.status}`);
  }
  return res.status === 204 ? null : res.json();
}

// ── Auth ──────────────────────────────────────────────────────────────────────

function login() {
  const token = $("#token-input").value.trim();
  if (!token) return;
  TOKEN = token;
  // Validate against a real endpoint before entering
  api("/admin/stats")
    .then(() => {
      sessionStorage.setItem("mil_admin_token", token);
      $("#login-view").classList.add("hidden");
      $("#app-view").classList.remove("hidden");
      startStats();
      loadUsers();
    })
    .catch((e) => {
      const el = $("#login-error");
      el.textContent = e.message;
      el.classList.remove("hidden");
    });
}

function logout() {
  sessionStorage.removeItem("mil_admin_token");
  TOKEN = "";
  clearInterval(statsTimer);
  $("#app-view").classList.add("hidden");
  $("#login-view").classList.remove("hidden");
}

// ── Stats (auto-refresh 10s) ──────────────────────────────────────────────────

function fmtBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 ** 2) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 ** 3) return `${(n / 1024 ** 2).toFixed(1)} MB`;
  return `${(n / 1024 ** 3).toFixed(2)} GB`;
}

async function refreshStats() {
  try {
    const s = await api("/admin/stats");
    $("#s-online").textContent = s.online_now;
    $("#s-messages").textContent = s.messages_today;
    $("#s-total").textContent = s.total_users;
    $("#s-active").textContent = s.active_users;
    $("#s-suspended").textContent = s.suspended_users;
    $("#s-storage").textContent = fmtBytes(s.storage_used_bytes);
  } catch (_) {
    /* transient errors: keep last values on screen */
  }
}

function startStats() {
  refreshStats();
  clearInterval(statsTimer);
  statsTimer = setInterval(refreshStats, 10_000);
}

// ── Users ─────────────────────────────────────────────────────────────────────

async function loadUsers() {
  const params = new URLSearchParams();
  const q = $("#f-search").value.trim();
  const dept = $("#f-dept").value.trim();
  const status = $("#f-status").value;
  if (q) params.set("q", q);
  if (dept) params.set("department", dept);
  if (status) params.set("status", status);

  const users = await api(`/admin/users?${params}`);
  const tbody = $("#users-table tbody");
  tbody.innerHTML = "";
  for (const u of users) {
    const tr = document.createElement("tr");
    const isActive = u.status === "active";
    tr.innerHTML = `
      <td>${esc(u.full_name)}</td>
      <td dir="ltr">${esc(u.phone_number)}</td>
      <td>${esc(u.department || "—")}</td>
      <td>${esc(u.role)}</td>
      <td><span class="badge ${isActive ? "active" : "suspended"}">
            ${isActive ? "نشط" : "معطل"}</span></td>
      <td>${u.last_seen_at ? new Date(u.last_seen_at).toLocaleString("ar-EG") : "—"}</td>
      <td></td>`;
    const btn = document.createElement("button");
    btn.className = `btn-small ${isActive ? "btn-danger" : "btn-gold"}`;
    btn.style.marginTop = "0";
    btn.textContent = isActive ? "تعطيل" : "تفعيل";
    btn.onclick = () => openModal(u.id, isActive ? "suspend" : "activate");
    tr.lastElementChild.appendChild(btn);
    tbody.appendChild(tr);
  }
}

function esc(s) {
  const d = document.createElement("div");
  d.textContent = String(s);
  return d.innerHTML;
}

// ── Suspend/activate modal (mandatory reason) ─────────────────────────────────

function openModal(userId, action) {
  pendingAction = { userId, action };
  $("#modal-title").textContent =
    action === "suspend" ? "تعطيل الحساب" : "تفعيل الحساب";
  $("#modal-reason").value = "";
  $("#modal").classList.remove("hidden");
}

async function confirmModal() {
  const reason = $("#modal-reason").value.trim();
  if (reason.length < 5) {
    $("#modal-reason").style.borderColor = "var(--red)";
    return;
  }
  const { userId, action } = pendingAction;
  await api(`/admin/users/${userId}/status`, {
    method: "POST",
    body: JSON.stringify({ action, reason }),
  });
  $("#modal").classList.add("hidden");
  loadUsers();
}

// ── Broadcast ─────────────────────────────────────────────────────────────────

async function sendBroadcast() {
  const title = $("#b-title").value.trim();
  const body = $("#b-body").value.trim();
  const dept = $("#b-dept").value.trim();
  if (title.length < 2 || body.length < 2) return;

  $("#b-send").disabled = true;
  try {
    const r = await api("/admin/broadcast", {
      method: "POST",
      body: JSON.stringify({
        title,
        body,
        department: dept || null,
      }),
    });
    $("#b-result").textContent =
      `أُرسل إلى ${r.target_users} مستخدم — وصل فورياً لـ ${r.push_delivered} جهاز غير متصل`;
    $("#b-title").value = "";
    $("#b-body").value = "";
  } catch (e) {
    $("#b-result").textContent = `خطأ: ${e.message}`;
  } finally {
    $("#b-send").disabled = false;
  }
}

// ── Tabs & wiring ─────────────────────────────────────────────────────────────

document.addEventListener("DOMContentLoaded", () => {
  $("#login-btn").onclick = login;
  $("#token-input").addEventListener("keydown", (e) => {
    if (e.key === "Enter") login();
  });
  $("#logout-btn").onclick = logout;
  $("#f-apply").onclick = loadUsers;
  $("#b-send").onclick = sendBroadcast;
  $("#modal-cancel").onclick = () => $("#modal").classList.add("hidden");
  $("#modal-confirm").onclick = confirmModal;

  document.querySelectorAll(".tab").forEach((tab) => {
    tab.onclick = () => {
      document.querySelectorAll(".tab").forEach((t) => t.classList.remove("active"));
      tab.classList.add("active");
      document.querySelectorAll(".panel").forEach((p) => p.classList.add("hidden"));
      $(`#tab-${tab.dataset.tab}`).classList.remove("hidden");
      if (tab.dataset.tab === "users") loadUsers();
    };
  });

  if (TOKEN) {
    // Try resuming the previous session
    api("/admin/stats")
      .then(() => {
        $("#login-view").classList.add("hidden");
        $("#app-view").classList.remove("hidden");
        startStats();
        loadUsers();
      })
      .catch(() => {});
  }
});
