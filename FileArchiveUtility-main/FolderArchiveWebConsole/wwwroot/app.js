const form = document.querySelector("#archive-form");
const scanButton = document.querySelector("#scan-button");
const runButton = document.querySelector("#run-button");
const selectAllButton = document.querySelector("#select-all");
const candidateList = document.querySelector("#candidate-list");
const candidateSummary = document.querySelector("#candidate-summary");
const selectionCount = document.querySelector("#selection-count");
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
let candidates = [];
let jobRunning = false;
let toastTimeout;

async function initialize() {
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
  const optionalNumber = (selector) => {
    const value = document.querySelector(selector).value.trim();
    return value === "" ? null : Number(value);
  };
  return {
    sourcePath: document.querySelector("#source").value.trim(),
    destinationPath: document.querySelector("#destination").value.trim(),
    ageDays: Number(document.querySelector("#age-days").value),
    includeExtensions: document.querySelector("#include-extensions").value,
    excludeExtensions: document.querySelector("#exclude-extensions").value,
    excludePaths: document.querySelector("#exclude-paths").value,
    minSizeMb: optionalNumber("#min-size"),
    maxSizeMb: optionalNumber("#max-size")
  };
}

async function api(path, body) {
  const response = await fetch(path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Archive-Console-Token": sessionToken
    },
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
  scanButton.classList.add("loading");
  candidateSummary.textContent = "Scanning source folder…";
  try {
    const result = await api("/api/scan", requestOptions());
    candidates = result.candidates;
    renderCandidates(result);
    setActivity(`Scan complete. ${result.candidateCount.toLocaleString()} eligible file(s) found.`);
    setJobDisplay("Scan complete", "READY");
  } catch (error) {
    candidates = [];
    renderCandidates();
    candidateSummary.textContent = "The scan could not be completed.";
    showToast(error.message, true);
  } finally {
    scanButton.disabled = false;
    scanButton.classList.remove("loading");
  }
});

function renderCandidates(result) {
  candidateList.replaceChildren();
  if (!result || result.candidates.length === 0) {
    const row = document.createElement("tr");
    row.className = "empty-row";
    const cell = document.createElement("td");
    cell.colSpan = 4;
    cell.textContent = result ? "No files match the selected criteria." : "No scan results yet. Set your locations and scan to begin.";
    row.append(cell);
    candidateList.append(row);
  } else {
    const fragment = document.createDocumentFragment();
    for (const candidate of result.candidates) {
      const row = document.createElement("tr");
      const checkCell = document.createElement("td");
      checkCell.className = "check-col";
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "candidate-check";
      checkbox.value = candidate.path;
      checkbox.setAttribute("aria-label", `Select ${candidate.path}`);
      checkbox.addEventListener("change", updateSelection);
      checkCell.append(checkbox);

      const fileCell = document.createElement("td");
      fileCell.className = "file-cell";
      const fileName = document.createElement("strong");
      fileName.textContent = candidate.name;
      const filePath = document.createElement("small");
      filePath.textContent = candidate.path;
      fileCell.append(fileName, filePath);

      const modifiedCell = document.createElement("td");
      modifiedCell.textContent = new Date(candidate.lastWriteTimeUtc).toISOString().replace("T", " ").replace("Z", "");
      const sizeCell = document.createElement("td");
      sizeCell.className = "size-col";
      sizeCell.textContent = formatSize(candidate.sizeBytes);
      row.append(checkCell, fileCell, modifiedCell, sizeCell);
      fragment.append(row);
    }
    candidateList.append(fragment);
  }

  const note = result?.truncated ? ` First ${result.candidateCount.toLocaleString()} shown; scan limit reached.` : "";
  candidateSummary.textContent = result
    ? `${result.candidateCount.toLocaleString()} eligible file(s)${note}`
    : "Run a scan to see eligible files here.";
  selectAllButton.disabled = !result || result.candidates.length === 0 || jobRunning;
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

function selectedPaths() {
  return [...document.querySelectorAll(".candidate-check:checked")].map((checkbox) => checkbox.value);
}

function updateSelection() {
  const selected = selectedPaths().length;
  selectionCount.textContent = `${selected.toLocaleString()} selected`;
  runButton.disabled = selected === 0 || jobRunning || ( !dryRunInput.checked && !confirmLive.checked);
}

selectAllButton.addEventListener("click", () => {
  const checks = [...document.querySelectorAll(".candidate-check")];
  const select = checks.some((checkbox) => !checkbox.checked);
  checks.forEach((checkbox) => { checkbox.checked = select; });
  selectAllButton.textContent = select ? "Clear selection" : "Select all";
  updateSelection();
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
  const paths = selectedPaths();
  if (paths.length === 0 || jobRunning) return;
  if (!dryRunInput.checked && !confirm("This will move selected files from the source folder. Continue?")) return;

  const request = {
    ...requestOptions(),
    selectedPaths: paths,
    dryRun: dryRunInput.checked,
    removeEmptyFolders: document.querySelector("#remove-empty").checked,
    replaceNewerDestination: document.querySelector("#replace-newer").checked,
    confirmLiveRun: confirmLive.checked
  };

  try {
    const { id: jobId } = await api("/api/jobs", request);
    jobRunning = true;
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
      const percent = status.total === 0 ? 100 : Math.min(100, Math.round((status.processed / status.total) * 100));
      progressBar.style.width = `${percent}%`;
      jobStats.textContent = `${status.processed.toLocaleString()} / ${status.total.toLocaleString()} processed  ·  ${status.archived.toLocaleString()} moved  ·  ${status.skipped.toLocaleString()} skipped  ·  ${status.failed.toLocaleString()} failed`;
      activityLog.textContent = status.logs.join("\n") || "Preparing…";
      activityLog.scrollTop = activityLog.scrollHeight;
      if (status.status !== "Running") {
        jobRunning = false;
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
    setControlsDisabled(false);
    setJobDisplay("Could not read job status", "ERROR");
    showToast(error.message, true);
  }
}

function setControlsDisabled(disabled) {
  scanButton.disabled = disabled;
  runButton.disabled = disabled || selectedPaths().length === 0 || (!dryRunInput.checked && !confirmLive.checked);
  selectAllButton.disabled = disabled || candidates.length === 0;
  document.querySelectorAll("#archive-form input").forEach((input) => { input.disabled = disabled; });
  document.querySelectorAll(".candidate-check").forEach((checkbox) => { checkbox.disabled = disabled; });
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
