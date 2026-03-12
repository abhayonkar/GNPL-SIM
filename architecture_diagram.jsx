import { useState } from "react";

const MODULES = {
  config: {
    label: "config/",
    color: "#f59e0b",
    bg: "rgba(245,158,11,0.08)",
    border: "#f59e0b",
    files: ["simConfig.m"],
    desc: "Single source of truth — all magic numbers",
    icon: "⚙",
  },
  network: {
    label: "network/",
    color: "#38bdf8",
    bg: "rgba(56,189,248,0.08)",
    border: "#38bdf8",
    files: ["initNetwork.m", "updateFlow.m", "updatePressure.m", "updateTemperature.m"],
    desc: "Topology, incidence matrix, Darcy-Weisbach physics",
    icon: "🔗",
  },
  equipment: {
    label: "equipment/",
    color: "#fb923c",
    bg: "rgba(251,146,60,0.08)",
    border: "#fb923c",
    files: ["initCompressor.m", "updateCompressor.m", "initValve.m", "updateDensity.m"],
    desc: "Compressor curves, valve state, gas density",
    icon: "🔧",
  },
  scada: {
    label: "scada/",
    color: "#a78bfa",
    bg: "rgba(167,139,250,0.08)",
    border: "#a78bfa",
    files: ["initEKF.m", "updateEKF.m", "initPLC.m", "updatePLC.m"],
    desc: "Extended Kalman Filter, PLC polling & latency",
    icon: "📡",
  },
  control: {
    label: "control/",
    color: "#34d399",
    bg: "rgba(52,211,153,0.08)",
    border: "#34d399",
    files: ["updateControlLogic.m"],
    desc: "PID compressor control, valve interlocks, emergency shutdown",
    icon: "🎛",
  },
  attacks: {
    label: "attacks/",
    color: "#f87171",
    bg: "rgba(248,113,113,0.08)",
    border: "#f87171",
    files: ["initAttackSchedule.m", "applyAttackEffects.m", "detectIncidents.m"],
    desc: "MITRE ATT&CK schedule, injection logic, alarm detection",
    icon: "⚠",
  },
  profiling: {
    label: "profiling/",
    color: "#e879f9",
    bg: "rgba(232,121,249,0.08)",
    border: "#e879f9",
    files: ["generateSourceProfile.m"],
    desc: "Realistic AR(1) source pressure & demand profiles",
    icon: "📈",
  },
  logging: {
    label: "logging/",
    color: "#94a3b8",
    bg: "rgba(148,163,184,0.08)",
    border: "#94a3b8",
    files: ["initLogs.m", "updateLogs.m", "logEvent.m", "initLogger.m", "closeLogger.m"],
    desc: "Log pre-allocation, event logger, session management",
    icon: "📋",
  },
  export: {
    label: "export/",
    color: "#4ade80",
    bg: "rgba(74,222,128,0.08)",
    border: "#4ade80",
    files: ["exportDataset.m", "exportResults.m"],
    desc: "Structured dataset & legacy CSV export",
    icon: "💾",
  },
};

const CALL_SEQUENCE = [
  { step: 1, mod: "attacks",   fn: "applyAttackEffects",   note: "Modify src_p / actuators per active attack ID" },
  { step: 2, mod: "network",   fn: "updateFlow",           note: "Darcy-Weisbach edge flows" },
  { step: 3, mod: "network",   fn: "updatePressure",       note: "Nodal mass-balance pressure update" },
  { step: 4, mod: "equipment", fn: "updateCompressor",     note: "Head / power / pressure boost" },
  { step: 5, mod: "network",   fn: "updateTemperature",    note: "Lumped thermal model" },
  { step: 6, mod: "equipment", fn: "updateDensity",        note: "Real-gas density" },
  { step: 7, mod: "scada",     fn: "updatePLC",            note: "Discrete sensor polling + latency buffer" },
  { step: 8, mod: "scada",     fn: "updateEKF",            note: "Kalman correction step" },
  { step: 9, mod: "control",   fn: "updateControlLogic",   note: "PID + safety interlocks" },
  { step: 10, mod: "logging",  fn: "updateLogs",           note: "Append full state to log arrays" },
  { step: 11, mod: "attacks",  fn: "detectIncidents",      note: "Threshold alarms → logEvent" },
];

const OUTPUTS = [
  { file: "master_dataset.csv",      dir: "automated_dataset/", color: "#4ade80" },
  { file: "normal_only.csv",         dir: "automated_dataset/", color: "#4ade80" },
  { file: "attacks_only.csv",        dir: "automated_dataset/", color: "#f87171" },
  { file: "attack_metadata.json",    dir: "automated_dataset/", color: "#fb923c" },
  { file: "attack_timeline.log",     dir: "automated_dataset/", color: "#fb923c" },
  { file: "execution_details.log",   dir: "automated_dataset/", color: "#94a3b8" },
  { file: "sim_events.log",          dir: "logs/",              color: "#94a3b8" },
  { file: "pressure.csv + others",   dir: "data/",              color: "#38bdf8" },
];

function ModuleCard({ id, data, selected, onClick }) {
  const isSelected = selected === id;
  return (
    <div
      onClick={() => onClick(id)}
      style={{
        background: isSelected ? data.bg : "rgba(15,23,42,0.6)",
        border: `1px solid ${isSelected ? data.color : "rgba(255,255,255,0.07)"}`,
        borderRadius: 8,
        padding: "12px 14px",
        cursor: "pointer",
        transition: "all 0.2s ease",
        boxShadow: isSelected ? `0 0 18px ${data.color}33` : "none",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
        <span style={{ fontSize: 16 }}>{data.icon}</span>
        <span style={{ color: data.color, fontFamily: "'Fira Code', monospace", fontSize: 12, fontWeight: 700, letterSpacing: 1 }}>
          {data.label}
        </span>
      </div>
      <div style={{ color: "rgba(255,255,255,0.45)", fontSize: 10, lineHeight: 1.5, marginBottom: 8 }}>
        {data.desc}
      </div>
      {isSelected && (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
          {data.files.map(f => (
            <span key={f} style={{
              background: `${data.color}18`,
              border: `1px solid ${data.color}40`,
              borderRadius: 4,
              padding: "2px 7px",
              color: data.color,
              fontFamily: "'Fira Code', monospace",
              fontSize: 10,
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
    padding: "7px 20px",
    borderRadius: 6,
    border: "none",
    cursor: "pointer",
    fontFamily: "'Fira Code', monospace",
    fontSize: 11,
    letterSpacing: 1,
    fontWeight: 700,
    background: active ? "#f59e0b" : "transparent",
    color: active ? "#0f172a" : "rgba(255,255,255,0.4)",
    transition: "all 0.2s",
  });

  return (
    <div style={{
      minHeight: "100vh",
      background: "#060d1a",
      fontFamily: "'Inter', sans-serif",
      color: "#e2e8f0",
      padding: "32px 24px",
      backgroundImage: `radial-gradient(ellipse at 20% 20%, rgba(245,158,11,0.04) 0%, transparent 60%),
                        radial-gradient(ellipse at 80% 80%, rgba(56,189,248,0.04) 0%, transparent 60%)`,
    }}>
      {/* Header */}
      <div style={{ maxWidth: 1100, margin: "0 auto" }}>
        <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginBottom: 32 }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 6 }}>
              <div style={{ width: 3, height: 36, background: "#f59e0b", borderRadius: 2 }} />
              <div>
                <div style={{ fontSize: 11, color: "#f59e0b", fontFamily: "'Fira Code', monospace", letterSpacing: 2, textTransform: "uppercase", marginBottom: 2 }}>
                  Gas Pipeline CPS Simulator v5
                </div>
                <h1 style={{ margin: 0, fontSize: 24, fontWeight: 800, letterSpacing: -0.5, color: "#f1f5f9" }}>
                  System Architecture
                </h1>
              </div>
            </div>
            <div style={{ color: "rgba(255,255,255,0.35)", fontSize: 12, paddingLeft: 15 }}>
              27 files · 9 modules · MITRE ATT&CK ICS · EKF · PID
            </div>
          </div>
          <div style={{ display: "flex", gap: 6, background: "rgba(255,255,255,0.04)", padding: 4, borderRadius: 8, border: "1px solid rgba(255,255,255,0.07)" }}>
            {[["arch","Modules"],["flow","Call Sequence"],["outputs","Outputs"]].map(([key, label]) => (
              <button key={key} style={TAB_STYLE(tab === key)} onClick={() => setTab(key)}>{label}</button>
            ))}
          </div>
        </div>

        {/* TAB: ARCHITECTURE */}
        {tab === "arch" && (
          <div>
            {/* Entry point */}
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginBottom: 4 }}>
              <div style={{
                background: "rgba(245,158,11,0.12)",
                border: "1.5px solid #f59e0b",
                borderRadius: 10,
                padding: "14px 32px",
                textAlign: "center",
                boxShadow: "0 0 32px rgba(245,158,11,0.15)",
                minWidth: 260,
              }}>
                <div style={{ color: "#f59e0b", fontFamily: "'Fira Code', monospace", fontSize: 13, fontWeight: 800, letterSpacing: 1 }}>
                  main_simulation.m
                </div>
                <div style={{ color: "rgba(255,255,255,0.4)", fontSize: 10, marginTop: 3 }}>
                  Entry point · addpath() · calls all inits + runSimulation
                </div>
              </div>
              {/* Arrow down */}
              <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
                <div style={{ width: 2, height: 14, background: "rgba(255,255,255,0.15)" }} />
                <div style={{ width: 0, height: 0, borderLeft: "6px solid transparent", borderRight: "6px solid transparent", borderTop: "8px solid rgba(255,255,255,0.2)" }} />
              </div>
            </div>

            {/* Config banner */}
            <div style={{
              background: "rgba(245,158,11,0.06)",
              border: "1px dashed rgba(245,158,11,0.4)",
              borderRadius: 8,
              padding: "10px 20px",
              display: "flex",
              alignItems: "center",
              gap: 12,
              marginBottom: 4,
            }}>
              <span style={{ fontSize: 14 }}>⚙</span>
              <span style={{ color: "#f59e0b", fontFamily: "'Fira Code', monospace", fontSize: 11, fontWeight: 700 }}>config/simConfig.m</span>
              <span style={{ color: "rgba(255,255,255,0.3)", fontSize: 10 }}>——  cfg struct injected into every module · no magic numbers elsewhere</span>
            </div>

            {/* Arrow */}
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginBottom: 4 }}>
              <div style={{ width: 2, height: 14, background: "rgba(255,255,255,0.15)" }} />
              <div style={{ width: 0, height: 0, borderLeft: "6px solid transparent", borderRight: "6px solid transparent", borderTop: "8px solid rgba(255,255,255,0.2)" }} />
            </div>

            {/* Init layer */}
            <div style={{ marginBottom: 4 }}>
              <div style={{ fontSize: 10, color: "rgba(255,255,255,0.25)", textTransform: "uppercase", letterSpacing: 2, marginBottom: 8, fontFamily: "'Fira Code', monospace" }}>
                ── INIT PHASE ──────────────────────────────────────────────────────
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr", gap: 10 }}>
                {["network","equipment","scada","logging"].map(id => (
                  <ModuleCard key={id} id={id} data={MODULES[id]} selected={selected} onClick={handleClick} />
                ))}
              </div>
            </div>

            {/* Arrow */}
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginBottom: 4 }}>
              <div style={{ width: 2, height: 14, background: "rgba(255,255,255,0.15)" }} />
              <div style={{ width: 0, height: 0, borderLeft: "6px solid transparent", borderRight: "6px solid transparent", borderTop: "8px solid rgba(255,255,255,0.2)" }} />
            </div>

            {/* Profiling + attacks init */}
            <div style={{ marginBottom: 4 }}>
              <div style={{ fontSize: 10, color: "rgba(255,255,255,0.25)", textTransform: "uppercase", letterSpacing: 2, marginBottom: 8, fontFamily: "'Fira Code', monospace" }}>
                ── PROFILE & SCHEDULE PHASE ─────────────────────────────────────────
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
                {["profiling","attacks"].map(id => (
                  <ModuleCard key={id} id={id} data={MODULES[id]} selected={selected} onClick={handleClick} />
                ))}
              </div>
            </div>

            {/* Arrow */}
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginBottom: 4 }}>
              <div style={{ width: 2, height: 14, background: "rgba(255,255,255,0.15)" }} />
              <div style={{ width: 0, height: 0, borderLeft: "6px solid transparent", borderRight: "6px solid transparent", borderTop: "8px solid rgba(255,255,255,0.2)" }} />
            </div>

            {/* RunSimulation orchestrator */}
            <div style={{ marginBottom: 4 }}>
              <div style={{ fontSize: 10, color: "rgba(255,255,255,0.25)", textTransform: "uppercase", letterSpacing: 2, marginBottom: 8, fontFamily: "'Fira Code', monospace" }}>
                ── SIMULATION LOOP ──────────────────────────────────────────────────
              </div>
              <div style={{
                background: "rgba(56,189,248,0.05)",
                border: "1px solid rgba(56,189,248,0.25)",
                borderRadius: 10,
                padding: "14px 18px",
                marginBottom: 10,
              }}>
                <div style={{ color: "#38bdf8", fontFamily: "'Fira Code', monospace", fontSize: 12, fontWeight: 700, marginBottom: 8 }}>
                  runSimulation.m  <span style={{ color: "rgba(255,255,255,0.25)", fontWeight: 400 }}>— orchestrator loop (N steps)</span>
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
                  {["attacks","network","equipment","scada","control","logging"].map(id => (
                    <ModuleCard key={id} id={id} data={MODULES[id]} selected={selected} onClick={handleClick} />
                  ))}
                </div>
              </div>
            </div>

            {/* Arrow */}
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginBottom: 4 }}>
              <div style={{ width: 2, height: 14, background: "rgba(255,255,255,0.15)" }} />
              <div style={{ width: 0, height: 0, borderLeft: "6px solid transparent", borderRight: "6px solid transparent", borderTop: "8px solid rgba(255,255,255,0.2)" }} />
            </div>

            {/* Export */}
            <div>
              <div style={{ fontSize: 10, color: "rgba(255,255,255,0.25)", textTransform: "uppercase", letterSpacing: 2, marginBottom: 8, fontFamily: "'Fira Code', monospace" }}>
                ── EXPORT PHASE ─────────────────────────────────────────────────────
              </div>
              <ModuleCard id="export" data={MODULES.export} selected={selected} onClick={handleClick} />
            </div>

            <div style={{ marginTop: 20, color: "rgba(255,255,255,0.2)", fontSize: 10, textAlign: "center", fontFamily: "'Fira Code', monospace" }}>
              click any module to expand its files
            </div>
          </div>
        )}

        {/* TAB: CALL SEQUENCE */}
        {tab === "flow" && (
          <div>
            <div style={{ fontSize: 10, color: "rgba(255,255,255,0.25)", textTransform: "uppercase", letterSpacing: 2, marginBottom: 16, fontFamily: "'Fira Code', monospace" }}>
              Per-step call sequence inside runSimulation (k = 1 … N)
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 0 }}>
              {CALL_SEQUENCE.map((item, i) => {
                const mod = MODULES[item.mod];
                return (
                  <div key={i} style={{ display: "flex", alignItems: "stretch", gap: 0 }}>
                    {/* Timeline spine */}
                    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", width: 40, flexShrink: 0 }}>
                      <div style={{
                        width: 28, height: 28, borderRadius: "50%",
                        background: `${mod.color}20`,
                        border: `1.5px solid ${mod.color}`,
                        display: "flex", alignItems: "center", justifyContent: "center",
                        color: mod.color, fontSize: 11, fontWeight: 800,
                        fontFamily: "'Fira Code', monospace", zIndex: 1,
                        flexShrink: 0,
                      }}>{item.step}</div>
                      {i < CALL_SEQUENCE.length - 1 && (
                        <div style={{ width: 2, flex: 1, background: "rgba(255,255,255,0.07)", minHeight: 12 }} />
                      )}
                    </div>
                    {/* Card */}
                    <div style={{
                      flex: 1, marginLeft: 12, marginBottom: 10,
                      background: "rgba(15,23,42,0.6)",
                      border: `1px solid ${mod.color}30`,
                      borderLeft: `3px solid ${mod.color}`,
                      borderRadius: 8,
                      padding: "10px 14px",
                    }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 4 }}>
                        <span style={{ color: mod.color, fontFamily: "'Fira Code', monospace", fontSize: 12, fontWeight: 700 }}>
                          {item.fn}
                        </span>
                        <span style={{
                          background: `${mod.color}18`, border: `1px solid ${mod.color}40`,
                          borderRadius: 4, padding: "1px 7px",
                          color: mod.color, fontSize: 9, fontFamily: "'Fira Code', monospace",
                          letterSpacing: 1,
                        }}>{mod.label}</span>
                      </div>
                      <div style={{ color: "rgba(255,255,255,0.4)", fontSize: 11 }}>{item.note}</div>
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
            <div style={{ fontSize: 10, color: "rgba(255,255,255,0.25)", textTransform: "uppercase", letterSpacing: 2, marginBottom: 16, fontFamily: "'Fira Code', monospace" }}>
              Files generated after simulation
            </div>

            {/* Group by folder */}
            {[
              { dir: "automated_dataset/", label: "Structured Dataset (SWaT-style)", icon: "📦" },
              { dir: "logs/",              label: "Event Log",                        icon: "📋" },
              { dir: "data/",             label: "Legacy Per-Signal CSVs",            icon: "📊" },
            ].map(group => {
              const files = OUTPUTS.filter(o => o.dir === group.dir);
              return (
                <div key={group.dir} style={{ marginBottom: 18 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 10 }}>
                    <span>{group.icon}</span>
                    <span style={{ color: "rgba(255,255,255,0.6)", fontSize: 11, fontFamily: "'Fira Code', monospace", fontWeight: 700 }}>
                      {group.dir}
                    </span>
                    <span style={{ color: "rgba(255,255,255,0.2)", fontSize: 11 }}>— {group.label}</span>
                  </div>
                  <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(240px, 1fr))", gap: 8, paddingLeft: 24 }}>
                    {files.map(f => (
                      <div key={f.file} style={{
                        background: `${f.color}0a`,
                        border: `1px solid ${f.color}30`,
                        borderRadius: 8, padding: "10px 14px",
                        display: "flex", alignItems: "center", gap: 10,
                      }}>
                        <div style={{ width: 6, height: 6, borderRadius: "50%", background: f.color, flexShrink: 0 }} />
                        <div>
                          <div style={{ color: f.color, fontFamily: "'Fira Code', monospace", fontSize: 11, fontWeight: 700 }}>{f.file}</div>
                          <div style={{ color: "rgba(255,255,255,0.3)", fontSize: 10, marginTop: 2 }}>{f.dir}</div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}

            {/* Schema summary */}
            <div style={{
              background: "rgba(15,23,42,0.8)",
              border: "1px solid rgba(255,255,255,0.07)",
              borderRadius: 10, padding: "16px 20px", marginTop: 8,
            }}>
              <div style={{ color: "rgba(255,255,255,0.5)", fontSize: 11, marginBottom: 12, fontFamily: "'Fira Code', monospace", letterSpacing: 1 }}>
                MASTER DATASET COLUMNS
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
                {[
                  ["Timestamp",       "#94a3b8", "datetime per step"],
                  ["S1..D2_pressure_bar", "#38bdf8", "8 nodal pressures"],
                  ["E1..E7_flow_kgs", "#38bdf8", "7 edge flows"],
                  ["*_temp_K",        "#fb923c", "8 node temperatures"],
                  ["*_density",       "#fb923c", "8 node densities"],
                  ["COMP_Power/Head/Eff/Ratio","#a78bfa","4 compressor metrics"],
                  ["VALVE_CMD",       "#34d399", "valve open/close"],
                  ["*_ekf_residual",  "#f59e0b", "8 EKF residuals"],
                  ["SRC_Pressure_bar","#e879f9", "source pressure (post-attack)"],
                  ["*_plc_p / *_plc_q","#94a3b8","PLC sensor bus values"],
                  ["ATTACK_ID",       "#f87171", "integer label"],
                  ["ATTACK_NAME / MITRE_ID","#f87171","string labels"],
                ].map(([col, color, note]) => (
                  <div key={col} style={{
                    background: `${color}08`, border: `1px solid ${color}25`,
                    borderRadius: 6, padding: "7px 10px",
                  }}>
                    <div style={{ color, fontFamily: "'Fira Code', monospace", fontSize: 10, fontWeight: 700 }}>{col}</div>
                    <div style={{ color: "rgba(255,255,255,0.3)", fontSize: 10, marginTop: 2 }}>{note}</div>
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
