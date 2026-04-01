import { useState, useEffect } from "react";

const PROJECT_DATA = {
  project: "Gas Pipeline CPS Simulator v7",
  saved: new Date().toISOString(),
  structure: {
    totalFiles: 38,
    folders: ["config","network","equipment","scada","control","attacks","profiling","logging","export","middleware"],
    files: {
      "main_simulation.m": "Entry point — registers paths, loads cfg, calls all inits, runSimulation, exports",
      "runSimulation.m": "Orchestrator loop — 16-step per-tick call sequence",
      "config/simConfig.m": "Single source of truth — all magic numbers + Phase 7 resilience edges E21/E22",
      "network/initNetwork.m": "Builds params + incidence matrix B from cfg",
      "network/updateFlow.m": "Darcy-Weisbach + E21/E22 resilience flow injection + V_D1 isolation",
      "network/updatePressure.m": "Nodal mass-balance pressure update",
      "network/updateTemperature.m": "Lumped thermal model",
      "equipment/initCompressor.m": "Compressor struct from cfg",
      "equipment/updateCompressor.m": "Head / power / efficiency / ratio",
      "equipment/initValve.m": "Valve struct from cfg",
      "equipment/updateDensity.m": "Real-gas density",
      "scada/initEKF.m": "EKF struct — state dim = nNodes + nEdges",
      "scada/updateEKF.m": "Kalman correction step",
      "scada/initPLC.m": "PLC struct — polling period + latency buffers + Phase 7 resilience actuators",
      "scada/updatePLC.m": "Discrete sensor polling + latency",
      "control/updateControlLogic.m": "PID + safety interlocks + D1 isolation + E21/E22 activation",
      "attacks/initAttackSchedule.m": "A1–A10 MITRE ATT&CK schedule",
      "attacks/applyAttackEffects.m": "Per-step attack injection",
      "attacks/detectIncidents.m": "Threshold alarms → logEvent",
      "profiling/generateSourceProfile.m": "AR(1) source pressure + demand with step changes",
      "logging/initLogs.m": "Pre-allocate all log arrays + Phase 7 resilience actuator logs",
      "logging/updateLogs.m": "Append state to log arrays each step",
      "logging/logEvent.m": "Core logger — file + console, INFO/WARNING/ERROR/CRITICAL",
      "logging/initLogger.m": "Opens logs/sim_events.log, writes session header",
      "logging/closeLogger.m": "Writes footer, closes file handle",
      "export/exportDataset.m": "master_dataset.csv with v_d1_cmd/crosstie/bypass columns",
      "export/exportResults.m": "Legacy per-signal CSVs to data/",
      "middleware/gateway.py": "Python Modbus TCP bridge — 12 actuator registers (addr 100-111)",
      "middleware/data_logger.py": "Standalone 156-col CSV logger at 10 Hz (12 actuators)",
    }
  },
  network: {
    nodes: 20,
    edges: 22,
    resilience_edges: ["E21 (J4→J7 cross-tie, DN100, 8km)", "E22 (J3→J5 bypass, DN80, 12km)"],
    isolation_valve: "V_D1 on E10 (Modbus addr 109)",
    compressors: ["CS1 (node 3)", "CS2 (node 7)"],
    prs: ["PRS1 (node 10, 18 barg)", "PRS2 (node 13, 14 barg)"],
    storage: "STO (node 12)"
  },
  modbus: {
    sensor_registers: "addr 0-60 (61 registers)",
    actuator_registers: "addr 100-111 (12 registers)",
    new_registers: {
      "109": "v_d1_cmd (D1 isolation valve)",
      "110": "crosstie_E21_cmd",
      "111": "bypass_E22_cmd"
    },
    coils: "addr 0-6 (7 coils)"
  },
  attacks: [
    {id: 1, name: "Source Pressure Manipulation", mitre: "T0835"},
    {id: 2, name: "Compressor Ratio Spoof",       mitre: "T0855"},
    {id: 3, name: "Valve Forcing",                mitre: "T0855"},
    {id: 4, name: "Demand Manipulation",          mitre: "T0835"},
    {id: 5, name: "Pressure Sensor Spoof",        mitre: "T0832"},
    {id: 6, name: "Flow Meter Spoof",             mitre: "T0832"},
    {id: 7, name: "PLC Latency Inflation",        mitre: "T0814"},
    {id: 8, name: "Pipeline Leak Simulation",     mitre: "T0882"},
    {id: 9, name: "Stealthy FDI Triangle",        mitre: "T0832"},
    {id: 10, name: "Replay Attack",               mitre: "T0830"},
  ],
  config: {
    dt_s: 0.1, T_min: 30, pipe_D_m: 0.202, pipe_L_km: 40,
    pid1_setpoint_bar: 18.0, pid2_setpoint_bar: 14.0,
    comp1_ratio_init: 1.15, comp2_ratio_init: 1.10,
    alarm_P_high: 26.0, alarm_P_low: 14.0, emer_shutdown: 27.0,
    regulatory_std: "PNGRB_T4S_2024", gas_sg: 0.57
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
                <div><span style={{color:"rgba(255,255,255,0.4)"}}>Edges: </span><span style={{color:"#38bdf8"}}>{result.network.edges} (20+E21+E22)</span></div>
                <div><span style={{color:"rgba(255,255,255,0.4)"}}>Resilience: </span><span style={{color:"#f59e0b"}}>E21 + E22 + V_D1</span></div>
                <div><span style={{color:"rgba(255,255,255,0.4)"}}>Modbus regs: </span><span style={{color:"#22d3ee"}}>112 + 7 coils</span></div>
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
