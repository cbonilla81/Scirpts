const form = document.querySelector("#archive-form");
const scanButton = document.querySelector("#scan-button");
const runButton = document.querySelector("#run-button");
const selectAllInput = document.querySelector("#select-all");
const exportCsvButton = document.querySelector("#export-csv");
const folderList = document.querySelector("#folder-list");
const candidateSummary = document.querySelector("#candidate-summary");
const selectionCount = document.querySelector("#selection-count");
const exportJobCsvButton = document.querySelector("#export-job-csv");
const dryRunInput = document.querySelector("#dry-run");
const liveConfirmation = document.querySelector("#live-confirmation");
const confirmLive = document.querySelector("#confirm-live");
const activityLog = document.querySelector("#activity-log");
const jobStatus = document.querySelector("#job-status");
const jobTitle = document.querySelector("#job-title");
const progressTrack = document.querySelector("#progress-track");
const progressBar = document.querySelector("#progress-bar");
const jobStats = document.querySelector("#job-stats");
const toast = document.querySelector("#toast");

let sessionToken = "";
const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content ?? "";
let folders = [];
let selectedFolders = [];
let latestJobStatus = null;
let jobRunning = false;
let toastTimeout;

async function initialize() {
  if (csrfToken) {
    scanButton.disabled = false;
    return;
  }

  try {
    const response = await fetch("/api/session", { cache: "no-store" });
    if (!response.ok) throw new Error("Could not establish a local console session.");
    ({ token: sessionToken } = await response.json());
    scanButton.disabled = false;
  } catch (error) {
    showToast(error.message, true);
    scanButton.disabled = true;
  }
}

function requestOptions() {
  return {
    sourcePath: document.querySelector("#source").value.trim(),
    destinationPath: document.querySelector("#destination").value.trim(),
    ageDays: Number(document.querySelector("#age-days").value),
    includeExtensions: document.querySelector("#include-extensions").value.trim(),
    excludeExtensions: document.querySelector("#exclude-extensions").value.trim(),
    minSizeMb: optionalNumber("#min-size-mb"),
    maxSizeMb: optionalNumber("#max-size-mb"),
    excludePaths: document.querySelector("#exclude-paths").value.trim()
  };
}

function optionalNumber(selector) {
  const value = document.querySelector(selector).value.trim();
  return value === "" ? null : Number(value);
}

async function api(path, body) {
  const headers = { "Content-Type": "application/json" };
  if (csrfToken) {
    headers["X-CSRF-TOKEN"] = csrfToken;
  } else {
    headers["X-Archive-Console-Token"] = sessionToken;
  }

  const response = await fetch(path, {
    method: "POST",
    headers,
    body: JSON.stringify(body ?? {})
  });
  if (response.status === 204) return null;
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || payload.detail || `Request failed (${response.status}).`);
  return payload;
}

scanButton.addEventListener("click", async () => {
  if (!form.reportValidity() || jobRunning) return;
  scanButton.disabled = true;
  runButton.disabled = true;
  selectAllInput.disabled = true;
  exportCsvButton.disabled = true;
  scanButton.classList.add("loading");
  candidateSummary.textContent = "Scanning source folders…";
  try {
    const result = await api("/api/scan", requestOptions());
    folders = result.folders;
    selectedFolders = [];
    renderFolders(result);
    setActivity(`Scan complete. ${folders.length.toLocaleString()} subfolder(s) found; ${result.candidateCount.toLocaleString()} file(s) match the filters.`);
    setJobDisplay("Scan complete", "READY");
  } catch (error) {
    folders = [];
    selectedFolders = [];
    renderFolders();
    candidateSummary.textContent = "The scan could not be completed.";
    showToast(error.message, true);
  } finally {
    scanButton.disabled = false;
    scanButton.classList.remove("loading");
  }
});

function renderFolders(result) {
  folderList.replaceChildren();
  if (!result || result.folders.length === 0) {
    const row = document.createElement("tr");
    row.className = "empty-row";
    const cell = document.createElement("td");
    cell.colSpan = 4;
    cell.textContent = result ? "No subfolders were found under the source folder." : "No scan results yet. Set your locations and scan to begin.";
    row.append(cell);
    folderList.append(row);
  } else {
    const fragment = document.createDocumentFragment();
    for (const folder of result.folders) {
      const row = document.createElement("tr");
      const checkCell = document.createElement("td");
      checkCell.className = "check-col";
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "folder-check";
      checkbox.value = folder.path;
      checkbox.setAttribute("aria-label", `Select folder ${folder.path}`);
      checkbox.addEventListener("change", () => updateFolderSelection(folder.path, checkbox.checked));
      checkCell.append(checkbox);

      const folderCell = document.createElement("td");
      folderCell.className = "folder-cell";
      const folderName = document.createElement("strong");
      folderName.textContent = relativeFolderPath(folder.path);
      const folderPath = document.createElement("small");
      folderPath.textContent = folder.path;
      folderCell.append(folderName, folderPath);

      const contentsCell = document.createElement("td");
      contentsCell.textContent = `${folder.fileCount.toLocaleString()} eligible file(s) · ${folder.subfolderCount.toLocaleString()} subfolder(s)`;
      const sizeCell = document.createElement("td");
      sizeCell.className = "size-col";
      sizeCell.textContent = formatSize(folder.sizeBytes);
      row.append(checkCell, folderCell, contentsCell, sizeCell);
      fragment.append(row);
    }
    folderList.append(fragment);
  }

  candidateSummary.textContent = result
    ? `${result.folders.length.toLocaleString()} subfolder(s) found · ${result.candidateCount.toLocaleString()} file(s) match filters`
    : "Run a scan to list source subfolders.";
  selectAllInput.disabled = !result || result.folders.length === 0 || jobRunning;
  exportCsvButton.disabled = !result || result.folders.length === 0 || jobRunning;
  synchronizeFolderChecks();
  updateSelection();
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value.toFixed(value >= 100 ? 0 : 1)} ${units[unit]}`;
}

function normalizedPath(path) {
  return path.replaceAll("/", "\\").replace(/[\\]+$/, "").toLowerCase();
}

function isWithinFolder(path, parent) {
  const normalizedPathValue = normalizedPath(path);
  const normalizedParent = normalizedPath(parent);
  return normalizedPathValue === normalizedParent || normalizedPathValue.startsWith(`${normalizedParent}\\`);
}

function isFolderCovered(path) {
  return selectedFolders.some((selected) => isWithinFolder(path, selected));
}

function relativeFolderPath(path) {
  const source = document.querySelector("#source").value.trim().replace(/[\\]+$/, "");
  return path.slice(source.length).replace(/^[\\/]+/, "");
}

function synchronizeFolderChecks() {
  const checks = [...document.querySelectorAll(".folder-check")];
  for (const checkbox of checks) {
    const explicitlySelected = selectedFolders.some((path) => normalizedPath(path) === normalizedPath(checkbox.value));
    checkbox.checked = isFolderCovered(checkbox.value);
    checkbox.disabled = jobRunning || (checkbox.checked && !explicitlySelected);
  }

  const selectedCount = checks.filter((checkbox) => checkbox.checked).length;
  selectAllInput.checked = checks.length > 0 && selectedCount === checks.length;
  selectAllInput.indeterminate = selectedCount > 0 && selectedCount < checks.length;
}

function updateFolderSelection(path, checked) {
  if (checked) {
    if (!selectedFolders.some((selected) => isWithinFolder(path, selected))) {
      selectedFolders = selectedFolders.filter((selected) => !isWithinFolder(selected, path));
      selectedFolders.push(path);
    }
  } else {
    selectedFolders = selectedFolders.filter((selected) => normalizedPath(selected) !== normalizedPath(path));
  }
  synchronizeFolderChecks();
  updateSelection();
}

function updateSelection() {
  selectionCount.textContent = `${selectedFolders.length.toLocaleString()} folder(s) selected`;
  runButton.disabled = selectedFolders.length === 0 || jobRunning || (!dryRunInput.checked && !confirmLive.checked);
}

selectAllInput.addEventListener("change", () => {
  if (selectAllInput.checked) {
    selectedFolders = folders
      .filter((folder) => !relativeFolderPath(folder.path).replaceAll("/", "\\").includes("\\"))
      .map((folder) => folder.path);
  } else {
    selectedFolders = [];
  }
  synchronizeFolderChecks();
  updateSelection();
});

function csvCell(value) {
  const text = String(value ?? "");
  const safeText = /^[\t\r\n ]*[=+\-@]/.test(text) ? `'${text}` : text;
  return `"${safeText.replaceAll('"', '""')}"`;
}

function downloadCsv(filename, rows) {
  const csv = `\uFEFF${rows.map((row) => row.map(csvCell).join(",")).join("\r\n")}`;
  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

exportCsvButton.addEventListener("click", () => {
  if (folders.length === 0 || jobRunning) return;
  const rows = [
    ["Path", "Folder", "Eligible Files", "Subfolders", "Eligible Size (bytes)", "Selected"],
    ...folders.map((folder) => [
      folder.path,
      relativeFolderPath(folder.path),
      folder.fileCount,
      folder.subfolderCount,
      folder.sizeBytes,
      isFolderCovered(folder.path) ? "Yes" : "No"
    ])
  ];
  downloadCsv("archive-folders.csv", rows);
});

exportJobCsvButton.addEventListener("click", () => {
  if (!latestJobStatus || latestJobStatus.status === "Running") return;

  const rows = [[
    "Record Type", "Timestamp", "Outcome", "Message",
    "Status", "Total", "Processed", "Archived", "Skipped", "Failed"
  ]];
  rows.push([
    "Summary", "", "", "",
    latestJobStatus.status,
    latestJobStatus.total,
    latestJobStatus.processed,
    latestJobStatus.archived,
    latestJobStatus.skipped,
    latestJobStatus.failed
  ]);

  for (const log of latestJobStatus.logs) {
    const match = log.match(/^\[([^\]]+)\]\s+([^:]+):\s?([\s\S]*)$/);
    rows.push([
      "Activity",
      match?.[1] ?? "",
      match?.[2] ?? "",
      match?.[3] ?? log,
      "", "", "", "", "", ""
    ]);
  }

  downloadCsv("archive-job-output.csv", rows);
});

dryRunInput.addEventListener("change", () => {
  liveConfirmation.hidden = dryRunInput.checked;
  confirmLive.checked = false;
  runButton.innerHTML = dryRunInput.checked
    ? '<span aria-hidden="true">➜</span> Start dry run'
    : '<span aria-hidden="true">➜</span> Start live archive';
  updateSelection();
});
confirmLive.addEventListener("change", updateSelection);

runButton.addEventListener("click", async () => {
  if (selectedFolders.length === 0 || jobRunning || !form.reportValidity()) return;
  if (!dryRunInput.checked && !confirm("This will move the selected folders and all their contents from the source folder. Continue?")) return;

  const request = {
    ...requestOptions(),
    selectedPaths: [],
    selectedFolders,
    dryRun: dryRunInput.checked,
    removeEmptyFolders: document.querySelector("#remove-empty").checked,
    replaceNewerDestination: document.querySelector("#replace-newer").checked,
    confirmLiveRun: confirmLive.checked
  };

  try {
    const { id: jobId } = await api("/api/jobs", request);
    jobRunning = true;
    latestJobStatus = null;
    exportJobCsvButton.disabled = true;
    setControlsDisabled(true);
    setJobDisplay(dryRunInput.checked ? "Dry run in progress" : "Archive in progress", "RUNNING");
    progressTrack.hidden = false;
    jobStats.hidden = false;
    jobStats.textContent = "Starting job…";
    setActivity("Job started.");
    await pollJob(jobId);
  } catch (error) {
    showToast(error.message, true);
    setControlsDisabled(false);
  }
});

async function pollJob(jobId) {
  try {
    while (jobRunning) {
      const status = await api("/api/jobs/status");
      if (!status || status.id !== jobId) throw new Error("The archive job status is unavailable.");
      latestJobStatus = status;
      const percent = status.total === 0 ? 100 : Math.min(100, Math.round((status.processed / status.total) * 100));
      progressBar.style.width = `${percent}%`;
      jobStats.textContent = `${status.processed.toLocaleString()} / ${status.total.toLocaleString()} processed  ·  ${status.archived.toLocaleString()} moved  ·  ${status.skipped.toLocaleString()} skipped  ·  ${status.failed.toLocaleString()} failed`;
      activityLog.textContent = status.logs.join("\n") || "Preparing…";
      activityLog.scrollTop = activityLog.scrollHeight;
      if (status.status !== "Running") {
        jobRunning = false;
        exportJobCsvButton.disabled = false;
        setControlsDisabled(false);
        const finalStatus = status.status === "Failed"
          ? "FAILED"
          : status.failed ? "COMPLETED WITH ERRORS" : "COMPLETED";
        setJobDisplay(status.status === "Completed" ? "Job complete" : "Job failed", finalStatus);
        setActivity(activityLog.textContent);
        return;
      }
      await new Promise((resolve) => setTimeout(resolve, 900));
    }
  } catch (error) {
    jobRunning = false;
    exportJobCsvButton.disabled = !latestJobStatus || latestJobStatus.status === "Running";
    setControlsDisabled(false);
    setJobDisplay("Could not read job status", "ERROR");
    showToast(error.message, true);
  }
}

function setControlsDisabled(disabled) {
  scanButton.disabled = disabled;
  runButton.disabled = disabled || selectedFolders.length === 0 || (!dryRunInput.checked && !confirmLive.checked);
  selectAllInput.disabled = disabled || folders.length === 0;
  exportCsvButton.disabled = disabled || folders.length === 0;
  document.querySelectorAll("#archive-form input").forEach((input) => { input.disabled = disabled; });
  synchronizeFolderChecks();
}

function setJobDisplay(title, status) {
  jobTitle.textContent = title;
  jobStatus.textContent = status;
  jobStatus.className = `job-status ${status.includes("ERROR") || status === "FAILED" ? "status-error" : status === "RUNNING" ? "status-running" : ""}`;
}

function setActivity(message) {
  activityLog.textContent = message;
  activityLog.scrollTop = activityLog.scrollHeight;
}

function showToast(message, isError = false) {
  clearTimeout(toastTimeout);
  toast.textContent = message;
  toast.className = `toast visible${isError ? " toast-error" : ""}`;
  toastTimeout = setTimeout(() => { toast.className = "toast"; }, 6000);
}

initialize();
