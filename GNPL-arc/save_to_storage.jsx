import { useState, useEffect } from "react";

const PROJECT_DATA = {
  project: "Gas Pipeline CPS Simulator v5",
  saved: new Date().toISOString(),
  structure: {
    totalFiles: 27,
    folders: ["config","network","equipment","scada","control","attacks","profiling","logging","export"],
    files: {
      "main_simulation.m": "Entry point — registers paths, loads cfg, calls all inits, runSimulation, exports",
      "runSimulation.m": "Orchestrator loop — 13-step per-tick call sequence",
      "config/simConfig.m": "Single source of truth — all magic numbers",
      "network/initNetwork.m": "Builds params + incidence matrix B from cfg",
      "network/updateFlow.m": "Darcy-Weisbach edge flows",
      "network/updatePressure.m": "Nodal mass-balance pressure update",
      "network/updateTemperature.m": "Lumped thermal model",
      "equipment/initCompressor.m": "Compressor struct from cfg",
      "equipment/updateCompressor.m": "Head / power / efficiency / ratio",
      "equipment/initValve.m": "Valve struct from cfg",
      "equipment/updateDensity.m": "Real-gas density",
      "scada/initEKF.m": "EKF struct — state dim = nNodes + nEdges",
      "scada/updateEKF.m": "Kalman correction step",
      "scada/initPLC.m": "PLC struct — polling period + latency buffers",
      "scada/updatePLC.m": "Discrete sensor polling + latency",
      "control/updateControlLogic.m": "PID + safety interlocks — reads all gains from cfg",
      "attacks/initAttackSchedule.m": "5-attack MITRE ATT&CK schedule",
      "attacks/applyAttackEffects.m": "Per-step attack injection",
      "attacks/detectIncidents.m": "Threshold alarms → logEvent",
      "profiling/generateSourceProfile.m": "AR(1) source pressure + demand with step changes",
      "logging/initLogs.m": "Pre-allocate all log arrays",
      "logging/updateLogs.m": "Append state to log arrays each step",
      "logging/logEvent.m": "Core logger — file + console, INFO/WARNING/ERROR/CRITICAL",
      "logging/initLogger.m": "Opens logs/sim_events.log, writes session header",
      "logging/closeLogger.m": "Writes footer, closes file handle",
      "export/exportDataset.m": "master_dataset.csv, normal_only.csv, attacks_only.csv, attack_metadata.json, attack_timeline.log",
      "export/exportResults.m": "Legacy per-signal CSVs to data/",
    },
  },
  attacks: [
    { id: 11, name: "Valve Manipulation Attack",   mitre: "T0855", start_min: 12.5, dur_s: 530 },
    { id: 12, name: "Slow Ramp Attack",            mitre: "T0835", start_min: 34.5, dur_s: 473 },
    { id: 12, name: "Slow Ramp Attack",            mitre: "T0835", start_min: 48.0, dur_s: 591 },
    { id: 11, name: "Valve Manipulation Attack",   mitre: "T0855", start_min: 55.5, dur_s: 489 },
    { id: 13, name: "Compressor Overspeed Attack", mitre: "T0855", start_min: 59.5, dur_s: 317 },
  ],
  config: {
    dt_s: 0.1, T_min: 64, pipe_D_m: 0.8, pipe_L_km: 40,
    pid_setpoint_bar: 5.0, comp_ratio_init: 1.25,
    alarm_P_high: 8.5, alarm_P_low: 1.0, emer_shutdown: 9.0,
  },
};

export default function App() {
  const [status, setStatus] = useState("saving");
  const [result, setResult] = useState(null);

  useEffect(() => {
    async function save() {
      try {
        await window.storage.set("gas_pipeline_sim_project", JSON.stringify(PROJECT_DATA));
        await window.storage.set("gas_pipeline_sim_saved_at", new Date().toISOString());
        const check = await window.storage.get("gas_pipeline_sim_project");
        const parsed = JSON.parse(check.value);
        setResult(parsed);
        setStatus("done");
      } catch (e) {
        setStatus("error:" + e.message);
      }
    }
    save();
  }, []);

  return (
    <div style={{ minHeight: "100vh", background: "#f8fafc", color: "#1e293b", fontFamily: "'Fira Code', monospace", padding: 32 }}>
      <div style={{ maxWidth: 700, margin: "0 auto" }}>
        <div style={{ color: "#b45309", fontSize: 11, letterSpacing: 3, marginBottom: 8, textTransform: "uppercase" }}>
          Persistent Storage
        </div>
        <h2 style={{ margin: "0 0 24px", fontSize: 20, fontWeight: 800, color: "#0f172a" }}>
          Gas Pipeline Sim — Project Snapshot
        </h2>

        {status === "saving" && (
          <div style={{ color: "#64748b", padding: 16, background: "#fff", borderRadius: 8, border: "1px solid #e2e8f0" }}>
            Saving to storage…
          </div>
        )}
        {status.startsWith("error") && (
          <div style={{ color: "#b91c1c", padding: 16, background: "#fef2f2", borderRadius: 8, border: "1px solid #fecaca" }}>
            Error: {status}
            <div style={{ marginTop: 8, fontSize: 10, color: "#64748b" }}>
              Note: window.storage is a Kiro IDE API — not available in a plain browser.
            </div>
          </div>
        )}

        {status === "done" && result && (
          <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
            <div style={{ background: "#f0fdf4", border: "1px solid #bbf7d0", borderRadius: 8, padding: 16 }}>
              <div style={{ color: "#15803d", fontWeight: 700, marginBottom: 8 }}>✓ Saved to persistent storage</div>
              <div style={{ color: "#475569", fontSize: 11 }}>Key: gas_pipeline_sim_project</div>
              <div style={{ color: "#475569", fontSize: 11 }}>Saved: {result.saved}</div>
            </div>

            <div style={{ background: "#fff", border: "1px solid #e2e8f0", borderRadius: 8, padding: 16, boxShadow: "0 1px 3px rgba(0,0,0,0.05)" }}>
              <div style={{ color: "#0369a1", fontWeight: 700, marginBottom: 12 }}>Project Summary</div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, fontSize: 11 }}>
                <div><span style={{ color: "#64748b" }}>Files: </span><span style={{ color: "#b45309", fontWeight: 700 }}>{result.structure.totalFiles}</span></div>
                <div><span style={{ color: "#64748b" }}>Modules: </span><span style={{ color: "#b45309", fontWeight: 700 }}>{result.structure.folders.length}</span></div>
                <div><span style={{ color: "#64748b" }}>Attacks: </span><span style={{ color: "#b91c1c", fontWeight: 700 }}>{result.attacks.length}</span></div>
                <div><span style={{ color: "#64748b" }}>Duration: </span><span style={{ color: "#b45309", fontWeight: 700 }}>{result.config.T_min} min</span></div>
              </div>
            </div>

            <div style={{ background: "#fff", border: "1px solid #e2e8f0", borderRadius: 8, padding: 16, boxShadow: "0 1px 3px rgba(0,0,0,0.05)" }}>
              <div style={{ color: "#6d28d9", fontWeight: 700, marginBottom: 12 }}>All 27 Files</div>
              <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                {Object.entries(result.structure.files).map(([f, desc]) => (
                  <div key={f} style={{ fontSize: 10, display: "flex", gap: 8 }}>
                    <span style={{ color: "#15803d", minWidth: 260, flexShrink: 0 }}>{f}</span>
                    <span style={{ color: "#64748b" }}>{desc}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
