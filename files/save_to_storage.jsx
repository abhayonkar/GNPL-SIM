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
      "export/exportResults.m": "Legacy per-signal CSVs to data/"
    }
  },
  network: {
    nodes: ["S1","J1","J2","J3","J4","J5","D1","D2"],
    edges: ["E1","E2","E3","E4","ValveLine","E6","E7"],
    compressorNode: "J1 (node 2)",
    valveEdge: "ValveLine (edge 5, J4→J5)"
  },
  attacks: [
    {id:11, name:"Valve Manipulation Attack",    mitre:"T0855", start_min:12.5, dur_s:530},
    {id:12, name:"Slow Ramp Attack",             mitre:"T0835", start_min:34.5, dur_s:473},
    {id:12, name:"Slow Ramp Attack",             mitre:"T0835", start_min:48.0, dur_s:591},
    {id:11, name:"Valve Manipulation Attack",    mitre:"T0855", start_min:55.5, dur_s:489},
    {id:13, name:"Compressor Overspeed Attack",  mitre:"T0855", start_min:59.5, dur_s:317}
  ],
  config: {
    dt_s: 0.1, T_min: 64, pipe_D_m: 0.8, pipe_L_km: 40,
    pid_setpoint_bar: 5.0, comp_ratio_init: 1.25,
    alarm_P_high: 8.5, alarm_P_low: 1.0, emer_shutdown: 9.0
  }
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
    <div style={{minHeight:"100vh",background:"#060d1a",color:"#e2e8f0",fontFamily:"'Fira Code',monospace",padding:32}}>
      <div style={{maxWidth:700,margin:"0 auto"}}>
        <div style={{color:"#f59e0b",fontSize:11,letterSpacing:3,marginBottom:8}}>PERSISTENT STORAGE</div>
        <h2 style={{margin:"0 0 24px",fontSize:20,fontWeight:800}}>Gas Pipeline Sim — Project Saved</h2>

        {status === "saving" && <div style={{color:"#94a3b8"}}>Saving to storage…</div>}
        {status.startsWith("error") && <div style={{color:"#f87171"}}>Error: {status}</div>}

        {status === "done" && result && (
          <div style={{display:"flex",flexDirection:"column",gap:16}}>
            <div style={{background:"rgba(74,222,128,0.08)",border:"1px solid rgba(74,222,128,0.3)",borderRadius:8,padding:16}}>
              <div style={{color:"#4ade80",fontWeight:700,marginBottom:8}}>✓ Saved to persistent storage</div>
              <div style={{color:"rgba(255,255,255,0.5)",fontSize:11}}>Key: gas_pipeline_sim_project</div>
              <div style={{color:"rgba(255,255,255,0.5)",fontSize:11}}>Saved: {result.saved}</div>
            </div>

            <div style={{background:"rgba(255,255,255,0.03)",border:"1px solid rgba(255,255,255,0.07)",borderRadius:8,padding:16}}>
              <div style={{color:"#38bdf8",fontWeight:700,marginBottom:12}}>Project Summary</div>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:8,fontSize:11}}>
                <div><span style={{color:"rgba(255,255,255,0.4)"}}>Files: </span><span style={{color:"#f59e0b"}}>{result.structure.totalFiles}</span></div>
                <div><span style={{color:"rgba(255,255,255,0.4)"}}>Modules: </span><span style={{color:"#f59e0b"}}>{result.structure.folders.length}</span></div>
                <div><span style={{color:"rgba(255,255,255,0.4)"}}>Attacks: </span><span style={{color:"#f87171"}}>{result.attacks.length}</span></div>
                <div><span style={{color:"rgba(255,255,255,0.4)"}}>Duration: </span><span style={{color:"#f59e0b"}}>{result.config.T_min} min</span></div>
              </div>
            </div>

            <div style={{background:"rgba(255,255,255,0.03)",border:"1px solid rgba(255,255,255,0.07)",borderRadius:8,padding:16}}>
              <div style={{color:"#a78bfa",fontWeight:700,marginBottom:12}}>All 27 Files</div>
              <div style={{display:"flex",flexDirection:"column",gap:4}}>
                {Object.entries(result.structure.files).map(([f,desc]) => (
                  <div key={f} style={{fontSize:10,display:"flex",gap:8}}>
                    <span style={{color:"#4ade80",minWidth:260,flexShrink:0}}>{f}</span>
                    <span style={{color:"rgba(255,255,255,0.3)"}}>{desc}</span>
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
