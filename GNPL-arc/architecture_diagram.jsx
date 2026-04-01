import { useState } from "react";

const MODULES = {
  config: {
    label: "config/", color: "#b45309", bg: "rgba(180,83,9,0.08)", border: "#b45309",
    files: ["simConfig.m"],
    desc: "Single source of truth — all parameters for 20-node network", icon: "⚙",
  },
  network: {
    label: "network/", color: "#0369a1", bg: "rgba(3,105,161,0.08)", border: "#0369a1",
    files: ["initNetwork.m", "updateFlow.m", "updatePressure.m", "updateTemperature.m"],
    desc: "20-node topology, incidence matrix B(20×20), Darcy-Weisbach + hydrostatic", icon: "🔗",
  },
  equipment: {
    label: "equipment/", color: "#c2410c", bg: "rgba(194,65,12,0.08)", border: "#c2410c",
    files: ["initCompressor.m", "updateCompressor.m", "initPRS.m", "updatePRS.m", "updateStorage.m", "initValve.m", "updateDensity.m"],
    desc: "Dual CS1/CS2 compressors, PRS1/PRS2 stations, storage cavern, Peng-Robinson EOS", icon: "🔧",
  },
  scada: {
    label: "scada/", color: "#6d28d9", bg: "rgba(109,40,217,0.08)", border: "#6d28d9",
    files: ["initEKF.m", "updateEKF.m", "initPLC.m", "updatePLC.m"],
    desc: "Extended Kalman Filter (40-state), PLC polling & latency buffer", icon: "📡",
  },
  control: {
    label: "control/", color: "#047857", bg: "rgba(4,120,87,0.08)", border: "#047857",
    files: ["updateControlLogic.m"],
    desc: "PID for CS1/CS2, valve interlocks, PRS setpoints, emergency shutdown", icon: "🎛",
  },
  attacks: {
    label: "attacks/", color: "#b91c1c", bg: "rgba(185,28,28,0.08)", border: "#b91c1c",
    files: ["initAttackSchedule.m", "applyAttackEffects.m", "applySensorSpoof.m", "detectIncidents.m"],
    desc: "A1–A10 MITRE ATT&CK schedule, injection logic, sensor spoof, alarm detection", icon: "⚠",
  },
  profiling: {
    label: "profiling/", color: "#7c3aed", bg: "rgba(124,58,237,0.08)", border: "#7c3aed",
    files: ["generateSourceProfile.m"],
    desc: "Diurnal AR(1) source pressure & demand profiles (dual-source S1/S2)", icon: "📈",
  },
  logging: {
    label: "logging/", color: "#475569", bg: "rgba(71,85,105,0.08)", border: "#475569",
    files: ["initLogs.m", "updateLogs.m", "logEvent.m", "initLogger.m", "closeLogger.m"],
    desc: "Log pre-allocation for 20-node arrays, event logger, session management", icon: "📋",
  },
  export: {
    label: "export/", color: "#15803d", bg: "rgba(21,128,61,0.08)", border: "#15803d",
    files: ["exportDataset.m", "exportResults.m"],
    desc: "Dual-stream dataset export — physics CSV + protocol CSV", icon: "💾",
  },
  middleware: {
    label: "middleware/", color: "#0e7490", bg: "rgba(14,116,144,0.08)", border: "#0e7490",
    files: ["gateway.py", "data_logger.py", "diagnostic.py", "sendToGateway.m", "receiveFromGateway.m", "initGatewayState.m", "config.yaml"],
    desc: "Python Modbus TCP bridge ↔ CODESYS SoftPLC + MATLAB UDP link + transaction logger", icon: "🔌",
  },
};

const CALL_SEQUENCE = [
  { step: 1,  mod: "attacks",    fn: "applyAttackEffects",   note: "A1–A4: modify src_p / actuators per active attack ID" },
  { step: 2,  mod: "network",    fn: "updateFlow",           note: "Darcy-Weisbach + elevation hydrostatic + AR(1) turbulence" },
  { step: 3,  mod: "equipment",  fn: "updateStorage",        note: "Bidirectional inject/withdraw, inventory tracking" },
  { step: 4,  mod: "network",    fn: "updatePressure",       note: "Nodal mass-balance dp/dt = (c²/V)·B·q + acoustic AR(1)" },
  { step: 5,  mod: "equipment",  fn: "updateCompressor ×2",  note: "CS1 then CS2 — head curve, efficiency, blade-pass pulsation" },
  { step: 6,  mod: "equipment",  fn: "updatePRS ×2",         note: "PRS1 (30 bar) + PRS2 (25 bar) — first-order throttle response" },
  { step: 7,  mod: "network",    fn: "updateTemperature",    note: "Joule-Thomson cooling + thermal AR(1) per node" },
  { step: 8,  mod: "equipment",  fn: "updateDensity",        note: "Peng-Robinson EOS cubic Z solver, composition drift" },
  { step: 9,  mod: "attacks",    fn: "applySensorSpoof",     note: "A5/A6: corrupt sensor_p / sensor_q before PLC sees them" },
  { step: 10, mod: "middleware", fn: "sendToGateway",        note: "UDP → Python → Modbus FC16 → CODESYS (61 registers)" },
  { step: 11, mod: "middleware", fn: "receiveFromGateway",   note: "CODESYS → Modbus FC3/FC1 → Python → UDP (9 regs + 7 coils)" },
  { step: 12, mod: "scada",      fn: "updatePLC",            note: "Discrete sensor polling + A7 latency buffer inflation" },
  { step: 13, mod: "scada",      fn: "updateEKF",            note: "40-state Kalman correction [20p + 20q]" },
  { step: 14, mod: "control",    fn: "updateControlLogic",   note: "PID CS1/CS2 + valve interlocks + emergency shutdown" },
  { step: 15, mod: "logging",    fn: "updateLogs",           note: "Append full state: pressure, flow, temp, comp, PRS, storage" },
  { step: 16, mod: "attacks",    fn: "detectIncidents",      note: "Threshold alarms → logEvent" },
];

const OUTPUTS = [
  { file: "master_dataset.csv",        dir: "automated_dataset/", color: "#15803d",  note: "Physics + attack labels, 20-node columns" },
  { file: "normal_only.csv",           dir: "automated_dataset/", color: "#15803d",  note: "Subset: attack_id = 0" },
  { file: "attacks_only.csv",          dir: "automated_dataset/", color: "#b91c1c",  note: "Subset: attack_id > 0" },
  { file: "attack_metadata.json",      dir: "automated_dataset/", color: "#c2410c",  note: "Per-attack timing & parameters" },
  { file: "attack_timeline.log",       dir: "automated_dataset/", color: "#c2410c",  note: "Human-readable attack schedule" },
  { file: "execution_details.log",     dir: "automated_dataset/", color: "#475569",  note: "Per-step execution log" },
  { file: "sim_events.log",            dir: "logs/",              color: "#475569",  note: "Alarm + incident events" },
  { file: "modbus_transactions_*.csv", dir: "middleware/logs/",   color: "#0e7490",  note: "Protocol layer — FC codes, raw INT registers, timestamps" },
  { file: "pipeline_data_*.csv",       dir: "middleware/logs/",   color: "#0e7490",  note: "150-col snapshot: eng values + raw INTs + coils" },
];

function ModuleCard({ id, data, selected, onClick }) {
  const isSelected = selected === id;
  return (
    <div onClick={() => onClick(id)} style={{
      background: isSelected ? data.bg : "#f8fafc",
      border: `1.5px solid ${isSelected ? data.color : "#e2e8f0"}`,
      borderRadius: 8, padding: "12px 14px", cursor: "pointer",
      transition: "all 0.2s ease",
      boxShadow: isSelected ? `0 0 0 3px ${data.color}22` : "0 1px 3px rgba(0,0,0,0.06)",
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
        <span style={{ fontSize: 15 }}>{data.icon}</span>
        <span style={{ color: data.color, fontFamily: "'Fira Code', monospace", fontSize: 12, fontWeight: 700, letterSpacing: 0.5 }}>
          {data.label}
        </span>
      </div>
      <div style={{ color: "#64748b", fontSize: 10, lineHeight: 1.5, marginBottom: isSelected ? 8 : 0 }}>
        {data.desc}
      </div>
      {isSelected && (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
          {data.files.map(f => (
            <span key={f} style={{
              background: `${data.color}12`, border: `1px solid ${data.color}40`,
              borderRadius: 4, padding: "2px 7px",
              color: data.color, fontFamily: "'Fira Code', monospace", fontSize: 10,
            }}>{f}</span>
          ))}
        </div>
      )}
    </div>
  );
}

export default function App() {
  const [selected, setSelected] = useState(null);
  const [tab, setTab] = useState("arch");
  const handleClick = (id) => setSelected(prev => prev === id ? null : id);

  const TAB_STYLE = (active) => ({
    padding: "7px 18px", borderRadius: 6, border: "none", cursor: "pointer",
    fontFamily: "'Fira Code', monospace", fontSize: 11, letterSpacing: 0.5, fontWeight: 700,
    background: active ? "#b45309" : "transparent",
    color: active ? "#fff" : "#64748b",
    transition: "all 0.2s",
  });

  const Arrow = () => (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", margin: "4px 0" }}>
      <div style={{ width: 2, height: 14, background: "#cbd5e1" }} />
      <div style={{ width: 0, height: 0, borderLeft: "6px solid transparent", borderRight: "6px solid transparent", borderTop: "8px solid #cbd5e1" }} />
    </div>
  );

  return (
    <div style={{
      minHeight: "100vh", background: "#f1f5f9",
      fontFamily: "'Inter', sans-serif", color: "#1e293b", padding: "32px 24px",
    }}>
      <div style={{ maxWidth: 1100, margin: "0 auto" }}>
        {/* Header */}
        <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginBottom: 28 }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 4 }}>
              <div style={{ width: 3, height: 36, background: "#b45309", borderRadius: 2 }} />
              <div>
                <div style={{ fontSize: 11, color: "#b45309", fontFamily: "'Fira Code', monospace", letterSpacing: 2, textTransform: "uppercase", marginBottom: 2 }}>
                  Gas Pipeline CPS Simulator v6
                </div>
                <h1 style={{ margin: 0, fontSize: 22, fontWeight: 800, letterSpacing: -0.5, color: "#0f172a" }}>
                  System Architecture
                </h1>
              </div>
            </div>
            <div style={{ color: "#64748b", fontSize: 12, paddingLeft: 15 }}>
              38 files · 10 modules · 20 nodes · 20 edges · CODESYS Modbus TCP · MITRE ATT&CK ICS · EKF-40
            </div>
          </div>
          <div style={{ display: "flex", gap: 4, background: "#e2e8f0", padding: 4, borderRadius: 8 }}>
            {[["arch","Modules"],["flow","Call Sequence"],["outputs","Outputs"],["stack","CPS Stack"]].map(([key, label]) => (
              <button key={key} style={TAB_STYLE(tab === key)} onClick={() => setTab(key)}>{label}</button>
            ))}
          </div>
        </div>

        {/* TAB: ARCHITECTURE */}
        {tab === "arch" && (
          <div>
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginBottom: 4 }}>
              <div style={{
                background: "#fff", border: "2px solid #b45309", borderRadius: 10,
                padding: "14px 32px", textAlign: "center",
                boxShadow: "0 4px 16px rgba(180,83,9,0.12)", minWidth: 280,
              }}>
                <div style={{ color: "#b45309", fontFamily: "'Fira Code', monospace", fontSize: 13, fontWeight: 800 }}>
                  main_simulation.m
                </div>
                <div style={{ color: "#64748b", fontSize: 10, marginTop: 3 }}>
                  Entry point · addpath() · inits all subsystems · delegates to runSimulation.m
                </div>
              </div>
              <Arrow />
            </div>

            <div style={{
              background: "#fffbeb", border: "1px dashed #b45309", borderRadius: 8,
              padding: "10px 20px", display: "flex", alignItems: "center", gap: 12, marginBottom: 4,
            }}>
              <span style={{ fontSize: 14 }}>⚙</span>
              <span style={{ color: "#b45309", fontFamily: "'Fira Code', monospace", fontSize: 11, fontWeight: 700 }}>config/simConfig.m</span>
              <span style={{ color: "#64748b", fontSize: 10 }}>—— cfg struct injected into every module · 20-node topology · dual compressor · PR EOS params</span>
            </div>
            <Arrow />

            <div style={{ marginBottom: 4 }}>
              <div style={{ fontSize: 10, color: "#94a3b8", textTransform: "uppercase", letterSpacing: 2, marginBottom: 8, fontFamily: "'Fira Code', monospace" }}>
                ── INIT PHASE ──────────────────────────────────────────────────────
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr 1fr", gap: 10 }}>
                {["network","equipment","scada","logging","middleware"].map(id => (
                  <ModuleCard key={id} id={id} data={MODULES[id]} selected={selected} onClick={handleClick} />
                ))}
              </div>
            </div>
            <Arrow />

            <div style={{ marginBottom: 4 }}>
              <div style={{ fontSize: 10, color: "#94a3b8", textTransform: "uppercase", letterSpacing: 2, marginBottom: 8, fontFamily: "'Fira Code', monospace" }}>
                ── PROFILE & SCHEDULE PHASE ─────────────────────────────────────────
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
                {["profiling","attacks"].map(id => (
                  <ModuleCard key={id} id={id} data={MODULES[id]} selected={selected} onClick={handleClick} />
                ))}
              </div>
            </div>
            <Arrow />

            <div style={{ marginBottom: 4 }}>
              <div style={{ fontSize: 10, color: "#94a3b8", textTransform: "uppercase", letterSpacing: 2, marginBottom: 8, fontFamily: "'Fira Code', monospace" }}>
                ── SIMULATION LOOP ──────────────────────────────────────────────────
              </div>
              <div style={{
                background: "#eff6ff", border: "1.5px solid #bfdbfe", borderRadius: 10,
                padding: "14px 18px", marginBottom: 10,
              }}>
                <div style={{ color: "#0369a1", fontFamily: "'Fira Code', monospace", fontSize: 12, fontWeight: 700, marginBottom: 8 }}>
                  runSimulation.m  <span style={{ color: "#64748b", fontWeight: 400 }}>— orchestrator loop (N steps @ 10 Hz)</span>
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
                  {["attacks","network","equipment","middleware","scada","control","logging"].map(id => (
                    <ModuleCard key={id} id={id} data={MODULES[id]} selected={selected} onClick={handleClick} />
                  ))}
                </div>
              </div>
            </div>
            <Arrow />

            <div>
              <div style={{ fontSize: 10, color: "#94a3b8", textTransform: "uppercase", letterSpacing: 2, marginBottom: 8, fontFamily: "'Fira Code', monospace" }}>
                ── EXPORT PHASE ─────────────────────────────────────────────────────
              </div>
              <ModuleCard id="export" data={MODULES.export} selected={selected} onClick={handleClick} />
            </div>
            <div style={{ marginTop: 16, color: "#94a3b8", fontSize: 10, textAlign: "center", fontFamily: "'Fira Code', monospace" }}>
              click any module to expand its files
            </div>
          </div>
        )}

        {/* TAB: CALL SEQUENCE */}
        {tab === "flow" && (
          <div>
            <div style={{ fontSize: 10, color: "#94a3b8", textTransform: "uppercase", letterSpacing: 2, marginBottom: 16, fontFamily: "'Fira Code', monospace" }}>
              Per-step call sequence inside runSimulation (k = 1 … N)
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 0 }}>
              {CALL_SEQUENCE.map((item, i) => {
                const mod = MODULES[item.mod];
                return (
                  <div key={i} style={{ display: "flex", alignItems: "stretch", gap: 0 }}>
                    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", width: 40, flexShrink: 0 }}>
                      <div style={{
                        width: 28, height: 28, borderRadius: "50%",
                        background: `${mod.color}15`, border: `2px solid ${mod.color}`,
                        display: "flex", alignItems: "center", justifyContent: "center",
                        color: mod.color, fontSize: 11, fontWeight: 800,
                        fontFamily: "'Fira Code', monospace", zIndex: 1, flexShrink: 0,
                      }}>{item.step}</div>
                      {i < CALL_SEQUENCE.length - 1 && (
                        <div style={{ width: 2, flex: 1, background: "#e2e8f0", minHeight: 12 }} />
                      )}
                    </div>
                    <div style={{
                      flex: 1, marginLeft: 12, marginBottom: 10,
                      background: "#fff", border: `1px solid ${mod.color}30`,
                      borderLeft: `3px solid ${mod.color}`, borderRadius: 8, padding: "10px 14px",
                      boxShadow: "0 1px 3px rgba(0,0,0,0.05)",
                    }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 4 }}>
                        <span style={{ color: mod.color, fontFamily: "'Fira Code', monospace", fontSize: 12, fontWeight: 700 }}>
                          {item.fn}
                        </span>
                        <span style={{
                          background: `${mod.color}12`, border: `1px solid ${mod.color}40`,
                          borderRadius: 4, padding: "1px 7px",
                          color: mod.color, fontSize: 9, fontFamily: "'Fira Code', monospace", letterSpacing: 1,
                        }}>{mod.label}</span>
                      </div>
                      <div style={{ color: "#475569", fontSize: 11 }}>{item.note}</div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* TAB: OUTPUTS */}
        {tab === "outputs" && (
          <div>
            <div style={{ fontSize: 10, color: "#94a3b8", textTransform: "uppercase", letterSpacing: 2, marginBottom: 16, fontFamily: "'Fira Code', monospace" }}>
              Files generated after simulation
            </div>
            {[
              { dir: "automated_dataset/", label: "Structured Dataset (physics + labels)", icon: "📦" },
              { dir: "logs/",              label: "Event Log",                              icon: "📋" },
              { dir: "middleware/logs/",   label: "Protocol Layer Dataset",                 icon: "🔌" },
            ].map(group => {
              const files = OUTPUTS.filter(o => o.dir === group.dir);
              return (
                <div key={group.dir} style={{ marginBottom: 18 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 10 }}>
                    <span>{group.icon}</span>
                    <span style={{ color: "#1e293b", fontSize: 11, fontFamily: "'Fira Code', monospace", fontWeight: 700 }}>{group.dir}</span>
                    <span style={{ color: "#64748b", fontSize: 11 }}>— {group.label}</span>
                  </div>
                  <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: 8, paddingLeft: 24 }}>
                    {files.map(f => (
                      <div key={f.file} style={{
                        background: "#fff", border: `1px solid ${f.color}30`,
                        borderRadius: 8, padding: "10px 14px",
                        boxShadow: "0 1px 3px rgba(0,0,0,0.05)",
                      }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
                          <div style={{ width: 6, height: 6, borderRadius: "50%", background: f.color, flexShrink: 0 }} />
                          <div style={{ color: f.color, fontFamily: "'Fira Code', monospace", fontSize: 11, fontWeight: 700 }}>{f.file}</div>
                        </div>
                        <div style={{ color: "#64748b", fontSize: 10, paddingLeft: 14 }}>{f.note}</div>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
            <div style={{ background: "#fff", border: "1px solid #e2e8f0", borderRadius: 10, padding: "16px 20px", marginTop: 8, boxShadow: "0 1px 3px rgba(0,0,0,0.05)" }}>
              <div style={{ color: "#475569", fontSize: 11, marginBottom: 12, fontFamily: "'Fira Code', monospace", letterSpacing: 1 }}>
                MASTER DATASET COLUMNS (physics stream)
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
                {[
                  ["Timestamp","#475569","datetime per step"],
                  ["p_S1..p_D6 (20×)","#0369a1","20 nodal pressures bar"],
                  ["q_E1..q_E20 (20×)","#0369a1","20 edge flows kg/s"],
                  ["T_S1..T_D6 (20×)","#c2410c","20 node temperatures K"],
                  ["rho_* (20×)","#c2410c","20 node densities kg/m³"],
                  ["CS1/CS2 W/H/eta/ratio","#6d28d9","dual compressor metrics"],
                  ["PRS1/PRS2 throttle","#0e7490","pressure regulating stations"],
                  ["sto_inventory","#1d4ed8","storage cavern fill fraction"],
                  ["linepack (20×)","#1d4ed8","per-segment line pack kg"],
                  ["ekf_residual_p/q","#b45309","40-state EKF residuals"],
                  ["ATTACK_ID / MITRE_ID","#b91c1c","integer + string labels"],
                  ["plc_p / plc_q","#475569","PLC sensor bus snapshot"],
                ].map(([col, color, note]) => (
                  <div key={col} style={{ background: `${color}08`, border: `1px solid ${color}25`, borderRadius: 6, padding: "7px 10px" }}>
                    <div style={{ color, fontFamily: "'Fira Code', monospace", fontSize: 10, fontWeight: 700 }}>{col}</div>
                    <div style={{ color: "#64748b", fontSize: 10, marginTop: 2 }}>{note}</div>
                  </div>
                ))}
              </div>
              <div style={{ marginTop: 14, padding: "12px 14px", background: "#f0fdff", border: "1px solid #a5f3fc", borderRadius: 8 }}>
                <div style={{ color: "#0e7490", fontFamily: "'Fira Code', monospace", fontSize: 10, fontWeight: 700, marginBottom: 6 }}>
                  PROTOCOL DATASET COLUMNS (middleware/logs/pipeline_data_*.csv · 150 cols)
                </div>
                <div style={{ color: "#475569", fontSize: 10, lineHeight: 1.7 }}>
                  timestamp_ms · datetime_utc · cycle &nbsp;|&nbsp;
                  20× p_*_bar (eng) · 20× q_*_kgs (eng) · 20× T_*_K (eng) · demand_scalar &nbsp;|&nbsp;
                  9× actuator_eng · 7× coil bool &nbsp;|&nbsp;
                  61× sensor_raw INT · 9× actuator_raw INT
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB: CPS STACK */}
        {tab === "stack" && (
          <div>
            <div style={{ fontSize: 10, color: "#94a3b8", textTransform: "uppercase", letterSpacing: 2, marginBottom: 16, fontFamily: "'Fira Code', monospace" }}>
              Full CPS Communication Stack
            </div>
            {[
              {
                label: "MATLAB — Physics & Dataset Layer", color: "#b45309",
                items: [
                  "20-node Peng-Robinson gas network (Darcy-Weisbach + hydrostatic)",
                  "Dual compressor CS1/CS2, PRS1/PRS2, storage cavern, 20 edges",
                  "10 attack scenarios A1–A10 with MITRE ATT&CK labels",
                  "Extended Kalman Filter (40-state: 20p + 20q)",
                  "Exports master_dataset.csv (physics + labels)",
                  "UDP TX port 5005 → gateway  |  UDP RX port 6006 ← gateway",
                ],
              },
              {
                label: "Python Gateway — Protocol Bridge", color: "#0e7490",
                items: [
                  "gateway.py: MATLAB UDP ↔ Modbus TCP bridge (CodesysModbus + S7PLC classes)",
                  "Receives 61×float64 (488 bytes) from MATLAB, scales to INT, writes FC16",
                  "Reads FC3 (9 actuator registers) + FC1 (7 coils), sends 16×float64 to MATLAB",
                  "data_logger.py: standalone 150-col CSV logger at 10 Hz",
                  "diagnostic.py: full connection test (TCP + write + read + coils)",
                  "config.yaml: plc.type = modbus | s7  (one line swap for S7-1200)",
                ],
              },
              {
                label: "CODESYS SoftPLC — Control Layer", color: "#6d28d9",
                items: [
                  "ModbusTCP_Server_Device @ 127.0.0.1:1502, unit=1",
                  "70 holding registers: addr 0–60 sensor inputs, addr 100–108 actuator outputs",
                  "7 coils: emergency_shutdown, cs1/cs2_alarm, sto_inject/withdraw, prs1/2_active",
                  "All variables INT (no REAL) — scaling: bar×100, kg/s×100, K×10, ratio×1000",
                  "PLC_PRG: dual PID (CS1→D1@30bar, CS2→D3@25bar), valve interlocks, safety trip",
                  "Hardware swap: change config.yaml host + type for Siemens S7-1200",
                ],
              },
            ].map((layer, i) => (
              <div key={i} style={{
                marginBottom: 14, background: "#fff",
                border: `1px solid ${layer.color}30`, borderLeft: `4px solid ${layer.color}`,
                borderRadius: 10, padding: "14px 18px",
                boxShadow: "0 1px 4px rgba(0,0,0,0.06)",
              }}>
                <div style={{ color: layer.color, fontFamily: "'Fira Code', monospace", fontSize: 12, fontWeight: 800, marginBottom: 10 }}>
                  {layer.label}
                </div>
                <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                  {layer.items.map((item, j) => (
                    <div key={j} style={{ display: "flex", gap: 8, alignItems: "flex-start" }}>
                      <div style={{ width: 4, height: 4, borderRadius: "50%", background: layer.color, marginTop: 6, flexShrink: 0 }} />
                      <div style={{ color: "#475569", fontSize: 11, lineHeight: 1.6 }}>{item}</div>
                    </div>
                  ))}
                </div>
                {i < 2 && <div style={{ textAlign: "center", marginTop: 10, color: layer.color, fontSize: 18, opacity: 0.6 }}>↕</div>}
              </div>
            ))}

            <div style={{ background: "#fff", border: "1px solid #e2e8f0", borderRadius: 10, padding: "14px 18px", boxShadow: "0 1px 3px rgba(0,0,0,0.05)" }}>
              <div style={{ color: "#475569", fontFamily: "'Fira Code', monospace", fontSize: 10, marginBottom: 10, letterSpacing: 1 }}>
                MODBUS REGISTER MAP (0-based CODESYS addresses)
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
                {[
                  ["Addr 0–19","#0369a1","p_* sensor (20 nodes) · bar×100"],
                  ["Addr 20–39","#0369a1","q_* sensor (20 edges) · kg/s×100"],
                  ["Addr 40–59","#c2410c","T_* sensor (20 nodes) · K×10"],
                  ["Addr 60","#475569","demand_scalar · ×1000"],
                  ["Addr 100–101","#6d28d9","CS1/CS2 speed cmd · ratio×1000"],
                  ["Addr 102–103","#047857","valve_E8 / valve_E14 cmd"],
                  ["Addr 104–108","#047857","PRS1/PRS2 + storage cmds"],
                  ["Coils 0–1","#b91c1c","emergency_shutdown · cs1/cs2_alarm"],
                  ["Coils 2–6","#0e7490","sto_inject/withdraw · prs1/2_active"],
                ].map(([addr, color, note]) => (
                  <div key={addr} style={{ background: `${color}08`, border: `1px solid ${color}25`, borderRadius: 6, padding: "7px 10px" }}>
                    <div style={{ color, fontFamily: "'Fira Code', monospace", fontSize: 10, fontWeight: 700 }}>{addr}</div>
                    <div style={{ color: "#64748b", fontSize: 10, marginTop: 2 }}>{note}</div>
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
