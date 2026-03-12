import { useState } from "react";

// ── Network topology (mirrors initNetwork.m exactly) ─────────────────────────
// nodeNames = ["S1","J1","J2","J3","J4","J5","D1","D2"]  (index 1-based in MATLAB)
// edges = [1 2; 2 3; 3 4; 3 5; 5 6; 4 7; 6 8]
// Compressor node = 2 (J1)
// Valve edge     = 5 (ValveLine: J4→J5)

const W = 900, H = 500;

// Node positions (SVG coords)
const NODES = {
  S1: { x: 60,  y: 250, type: "source",   label: "S1",  sub: "Source" },
  J1: { x: 200, y: 250, type: "junction", label: "J1",  sub: "Junction" },
  J2: { x: 370, y: 250, type: "junction", label: "J2",  sub: "Branch" },
  J3: { x: 520, y: 140, type: "junction", label: "J3",  sub: "Junction" },
  J4: { x: 520, y: 360, type: "junction", label: "J4",  sub: "Junction" },
  J5: { x: 660, y: 360, type: "junction", label: "J5",  sub: "Junction" },
  D1: { x: 820, y: 140, type: "demand",   label: "D1",  sub: "Demand" },
  D2: { x: 820, y: 360, type: "demand",   label: "D2",  sub: "Demand" },
};

// Edges with metadata
const EDGES = [
  { id: "E1",       from: "S1", to: "J1", type: "pipe",     label: "E1" },
  { id: "E2",       from: "J1", to: "J2", type: "pipe",     label: "E2" },
  { id: "E3",       from: "J2", to: "J3", type: "pipe",     label: "E3" },
  { id: "E4",       from: "J2", to: "J4", type: "pipe",     label: "E4" },
  { id: "ValveLine",from: "J4", to: "J5", type: "valve",    label: "ValveLine" },
  { id: "E6",       from: "J3", to: "D1", type: "pipe",     label: "E6" },
  { id: "E7",       from: "J5", to: "D2", type: "pipe",     label: "E7" },
];

const PARAMS = {
  D: "0.8 m", L: "40 km", rough: "20 μm",
};

function midpoint(a, b) {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

function angle(a, b) {
  return Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI;
}

// ── Sub-components ─────────────────────────────────────────────────────────────

function PipeSegment({ from, to, selected, onClick, id }) {
  const isSelected = selected === id;
  const color = isSelected ? "#f59e0b" : "#334155";
  const strokeW = isSelected ? 5 : 4;
  return (
    <line
      x1={from.x} y1={from.y} x2={to.x} y2={to.y}
      stroke={color} strokeWidth={strokeW}
      strokeLinecap="round"
      style={{ cursor: "pointer", transition: "all 0.2s" }}
      onClick={onClick}
    />
  );
}

function PipeLabel({ from, to, label, selected }) {
  const mid = midpoint(from, to);
  const isV = Math.abs(from.x - to.x) < 10;
  const offsetX = isV ? 14 : 0;
  const offsetY = isV ? 0 : -12;
  return (
    <text
      x={mid.x + offsetX} y={mid.y + offsetY}
      textAnchor="middle" fontSize={10}
      fill={selected ? "#f59e0b" : "rgba(148,163,184,0.7)"}
      fontFamily="'Fira Code', monospace"
      style={{ pointerEvents: "none" }}
    >{label}</text>
  );
}

function ValveSymbol({ from, to, selected, onClick }) {
  const mid = midpoint(from, to);
  const deg = angle(from, to);
  const isSelected = selected === "ValveLine";
  const col = isSelected ? "#f59e0b" : "#60a5fa";
  return (
    <g transform={`translate(${mid.x},${mid.y}) rotate(${deg})`}
       onClick={onClick} style={{ cursor: "pointer" }}>
      {/* pipe behind */}
      <line x1={-36} y1={0} x2={36} y2={0} stroke={isSelected ? "#f59e0b" : "#334155"} strokeWidth={4} />
      {/* valve body - two triangles facing each other */}
      <polygon points="-12,-10 12,-10 0,0" fill={col} opacity={0.9} />
      <polygon points="-12,10 12,10 0,0"  fill={col} opacity={0.9} />
      {/* valve stem */}
      <line x1={0} y1={-10} x2={0} y2={-20} stroke={col} strokeWidth={2} />
      <rect x={-6} y={-24} width={12} height={4} rx={2} fill={col} />
      {/* valve outline */}
      <rect x={-14} y={-12} width={28} height={24} rx={3}
        fill="none" stroke={col} strokeWidth={1.5} opacity={0.5} />
    </g>
  );
}

function CompressorSymbol({ node, selected, onClick }) {
  const isSelected = selected === "COMP";
  const col = isSelected ? "#f59e0b" : "#a78bfa";
  const r = 22;
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      {/* Compressor circle */}
      <circle cx={0} cy={0} r={r}
        fill={isSelected ? "rgba(245,158,11,0.15)" : "rgba(167,139,250,0.12)"}
        stroke={col} strokeWidth={2}
        style={{ filter: isSelected ? `drop-shadow(0 0 8px ${col})` : "none" }} />
      {/* Impeller blades */}
      {[0,60,120,180,240,300].map(deg => (
        <line key={deg}
          x1={0} y1={0}
          x2={Math.cos(deg*Math.PI/180)*16}
          y2={Math.sin(deg*Math.PI/180)*16}
          stroke={col} strokeWidth={2} strokeLinecap="round" />
      ))}
      <circle cx={0} cy={0} r={4} fill={col} />
      {/* C label */}
      <text x={0} y={-30} textAnchor="middle" fontSize={9}
        fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">COMP</text>
    </g>
  );
}

function NodeCircle({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const isSource = node.type === "source";
  const isDemand = node.type === "demand";
  const isJunction = node.type === "junction";

  const col = isSource ? "#4ade80" : isDemand ? "#f87171" : "#64748b";
  const fillCol = isSelected
    ? (isSource ? "rgba(74,222,128,0.2)" : isDemand ? "rgba(248,113,113,0.2)" : "rgba(100,116,139,0.2)")
    : (isSource ? "rgba(74,222,128,0.08)" : isDemand ? "rgba(248,113,113,0.08)" : "rgba(100,116,139,0.08)");

  const r = isJunction ? 10 : 14;

  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <circle cx={0} cy={0} r={r}
        fill={fillCol}
        stroke={isSelected ? "#f59e0b" : col}
        strokeWidth={isSelected ? 2.5 : 1.5}
        style={{ filter: isSelected ? "drop-shadow(0 0 8px #f59e0b)" : "none", transition: "all 0.2s" }}
      />
      {isSource && (
        <>
          <line x1={-6} y1={0} x2={6} y2={0} stroke={col} strokeWidth={2} />
          <line x1={0} y1={-6} x2={0} y2={6} stroke={col} strokeWidth={2} />
        </>
      )}
      {isDemand && (
        <polygon points="0,-7 6,4 -6,4" fill={col} opacity={0.8} />
      )}
      {/* Labels */}
      <text x={0} y={isSource || isDemand ? -20 : -16}
        textAnchor="middle" fontSize={12} fontWeight="800"
        fill={isSelected ? "#f59e0b" : (isSource ? "#4ade80" : isDemand ? "#f87171" : "#94a3b8")}
        fontFamily="'Fira Code', monospace"
        style={{ pointerEvents: "none" }}>
        {node.label}
      </text>
      <text x={0} y={isSource || isDemand ? -9 : -5}
        textAnchor="middle" fontSize={8}
        fill={"rgba(255,255,255,0.3)"}
        fontFamily="sans-serif"
        style={{ pointerEvents: "none" }}>
        {node.sub}
      </text>
    </g>
  );
}

// ── Info panel ────────────────────────────────────────────────────────────────
const INFO = {
  S1:  { title: "Source Node (S1)",  color: "#4ade80", body: "Inlet node — pressure driven by generateSourceProfile.m. Initial pressure 4.5 bar. Time-varying: AR(1) random walk + multi-frequency oscillations (22 min, 6 min, 75 s cycles)." },
  J1:  { title: "Junction J1 + Compressor", color: "#a78bfa", body: "Compressor injection node. PID-controlled compression ratio (1.1 – 2.0). Head curve: H = 500 − 0.5ṁ − 0.001ṁ². Efficiency: η = 0.80 − 0.002ṁ − 0.0001ṁ²." },
  J2:  { title: "Branch Junction (J2)", color: "#64748b", body: "Main network branch point. Splits flow between the upper delivery branch (J3 → D1) and the lower valve-controlled branch (J4 → J5 → D2). Incidence matrix B handles mass balance." },
  J3:  { title: "Junction J3",  color: "#64748b", body: "Upper branch intermediate node. Carries flow from J2 toward delivery node D1 via edge E6. Nodal volume 6 m³ (lumped capacitance model)." },
  J4:  { title: "Junction J4",  color: "#64748b", body: "Lower branch node upstream of the control valve. Valve pressure threshold monitored by PLC/PID: opens below 4.1 bar, closes above 5.1 bar (EKF estimate of J4 pressure)." },
  J5:  { title: "Junction J5",  color: "#64748b", body: "Node downstream of the control valve. Pressure here depends on whether ValveLine is open. PLC latency buffer (2 steps) delays valve command delivery." },
  D1:  { title: "Delivery Node D1",  color: "#f87171", body: "Primary demand sink. PID setpoint target = 5.0 bar. Emergency shutdown triggered if pressure > 9 bar (90% MAOP). EKF tracks this node for control feedback." },
  D2:  { title: "Delivery Node D2",  color: "#f87171", body: "Secondary demand sink on valve-controlled branch. Receives flow only when ValveLine is open. Demand withdrawal: 0.06 base + sinusoidal fluctuation + industrial step changes." },
  COMP:{ title: "Compressor (J1 node)", color: "#a78bfa", body: "Centrifugal compressor model. Shaft power W = ṁ·H/η. PID controls comp.ratio to maintain D1 pressure at setpoint. Compressor Overspeed Attack (ID 13) bypasses PID and ramps ratio → 1.95." },
  E1:  { title: "Pipe E1: S1 → J1", color: "#38bdf8", body: `D=${PARAMS.D}  L=${PARAMS.L}  ε=${PARAMS.rough}\nDarcy-Weisbach: λ from Colebrook-White. Flow: q = sign(Δp²)·√|Δp²| / K` },
  E2:  { title: "Pipe E2: J1 → J2", color: "#38bdf8", body: `D=${PARAMS.D}  L=${PARAMS.L}  ε=${PARAMS.rough}\nCarries full compressor output flow toward the branch junction.` },
  E3:  { title: "Pipe E3: J2 → J3", color: "#38bdf8", body: `D=${PARAMS.D}  L=${PARAMS.L}  ε=${PARAMS.rough}\nUpper branch feed pipe.` },
  E4:  { title: "Pipe E4: J2 → J4", color: "#38bdf8", body: `D=${PARAMS.D}  L=${PARAMS.L}  ε=${PARAMS.rough}\nLower branch feed pipe. Slow Ramp Attack (ID 12) inflates upstream pressure up to +30% over this segment.` },
  ValveLine:{ title: "ValveLine (E5): J4 → J5 — Control Valve", color: "#60a5fa", body: "Motorised isolation valve. act_valve_cmd ∈ {0,1}. Valve Manipulation Attack (ID 11) forces cmd=0 (closed). Command passes through PLC latency buffer (2-step delay). PID logic: opens when p(J4)<4.1 bar, closes when p(J4)>5.1 bar." },
  E6:  { title: "Pipe E6: J3 → D1", color: "#38bdf8", body: `D=${PARAMS.D}  L=${PARAMS.L}  ε=${PARAMS.rough}\nFinal delivery pipe to primary demand node.` },
  E7:  { title: "Pipe E7: J5 → D2", color: "#38bdf8", body: `D=${PARAMS.D}  L=${PARAMS.L}  ε=${PARAMS.rough}\nFinal delivery pipe to secondary demand node.` },
};

export default function App() {
  const [selected, setSelected] = useState(null);

  const sel = (id) => () => setSelected(prev => prev === id ? null : id);
  const info = selected ? INFO[selected] : null;

  // Draw pipes first (behind valves and nodes)
  const pipesOnly = EDGES.filter(e => e.type === "pipe");
  const valveEdge = EDGES.find(e => e.type === "valve");

  return (
    <div style={{
      minHeight: "100vh",
      background: "#07111f",
      fontFamily: "'Inter', sans-serif",
      color: "#e2e8f0",
      display: "flex",
      flexDirection: "column",
      backgroundImage: `radial-gradient(ellipse at 50% 0%, rgba(56,189,248,0.05) 0%, transparent 60%)`,
    }}>
      {/* Header */}
      <div style={{ padding: "20px 28px 0", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div>
          <div style={{ fontSize: 10, color: "#38bdf8", fontFamily: "'Fira Code', monospace", letterSpacing: 3, textTransform: "uppercase" }}>
            Physical Network Topology
          </div>
          <h1 style={{ margin: "4px 0 0", fontSize: 20, fontWeight: 800, color: "#f1f5f9", letterSpacing: -0.5 }}>
            Gas Pipeline Architecture
          </h1>
        </div>
        <div style={{ display: "flex", gap: 20, fontSize: 11, color: "rgba(255,255,255,0.35)" }}>
          {[
            ["●", "#4ade80", "Source node"],
            ["●", "#64748b", "Junction"],
            ["▲", "#f87171", "Demand node"],
            ["◎", "#a78bfa", "Compressor"],
            ["⋈", "#60a5fa", "Control valve"],
          ].map(([sym, col, lbl]) => (
            <div key={lbl} style={{ display: "flex", alignItems: "center", gap: 5 }}>
              <span style={{ color: col, fontSize: 13 }}>{sym}</span>
              <span>{lbl}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Main content */}
      <div style={{ display: "flex", flex: 1, padding: "16px 20px 20px", gap: 16 }}>
        {/* SVG diagram */}
        <div style={{
          flex: 1,
          background: "rgba(255,255,255,0.02)",
          border: "1px solid rgba(255,255,255,0.06)",
          borderRadius: 12,
          overflow: "hidden",
          position: "relative",
        }}>
          {/* Grid background */}
          <svg width="100%" height="100%" style={{ position: "absolute", top: 0, left: 0 }}>
            <defs>
              <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 40" fill="none" stroke="rgba(255,255,255,0.03)" strokeWidth="1" />
              </pattern>
            </defs>
            <rect width="100%" height="100%" fill="url(#grid)" />
          </svg>

          <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="100%"
            style={{ position: "relative", zIndex: 1 }}>

            {/* Flow direction arrows (defs) */}
            <defs>
              <marker id="arrowBlue" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
                <path d="M0,0 L0,6 L8,3 z" fill="rgba(56,189,248,0.5)" />
              </marker>
              <marker id="arrowYellow" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
                <path d="M0,0 L0,6 L8,3 z" fill="#f59e0b" />
              </marker>
              {/* Glow filter */}
              <filter id="glow">
                <feGaussianBlur stdDeviation="3" result="coloredBlur" />
                <feMerge><feMergeNode in="coloredBlur" /><feMergeNode in="SourceGraphic" /></feMerge>
              </filter>
            </defs>

            {/* ── Pipes ── */}
            {pipesOnly.map(e => {
              const a = NODES[e.from], b = NODES[e.to];
              const isSel = selected === e.id;
              return (
                <g key={e.id}>
                  {/* Highlight glow on selection */}
                  {isSel && <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke="#f59e0b" strokeWidth={10} opacity={0.15} strokeLinecap="round" />}
                  <PipeSegment from={a} to={b} selected={selected} onClick={sel(e.id)} id={e.id} />
                  {/* Flow arrows */}
                  <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke="transparent" strokeWidth={0}
                    markerMid={`url(#arrow${isSel ? "Yellow" : "Blue"})`}
                    style={{ pointerEvents: "none" }} />
                  <PipeLabel from={a} to={b} label={e.label} selected={isSel} />
                </g>
              );
            })}

            {/* ── Valve ── */}
            {(() => {
              const e = valveEdge;
              const a = NODES[e.from], b = NODES[e.to];
              const isSel = selected === e.id;
              return (
                <g>
                  {isSel && <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke="#f59e0b" strokeWidth={10} opacity={0.15} strokeLinecap="round" />}
                  <ValveSymbol from={a} to={b} selected={selected} onClick={sel(e.id)} />
                  <text x={(a.x+b.x)/2} y={a.y - 28}
                    textAnchor="middle" fontSize={9}
                    fill={isSel ? "#f59e0b" : "rgba(96,165,250,0.8)"}
                    fontFamily="'Fira Code', monospace"
                    style={{ pointerEvents: "none" }}>ValveLine</text>
                </g>
              );
            })()}

            {/* ── Compressor (on J1 node) ── */}
            <CompressorSymbol node={NODES.J1} selected={selected} onClick={sel("COMP")} />

            {/* ── Nodes ── */}
            {Object.entries(NODES).map(([id, node]) => {
              // Don't draw a plain circle for J1 since compressor is there
              if (id === "J1") return null;
              return (
                <NodeCircle key={id} node={node} id={id}
                  selected={selected} onClick={sel(id)} />
              );
            })}

            {/* ── J1 label (below compressor) ── */}
            <text x={NODES.J1.x} y={NODES.J1.y + 38}
              textAnchor="middle" fontSize={9}
              fill="rgba(167,139,250,0.5)"
              fontFamily="sans-serif"
              style={{ pointerEvents: "none" }}>node 2</text>

            {/* ── Pressure labels (simulated nominal values) ── */}
            {[
              ["S1", "~4.5 bar"],
              ["J3", "~5.1 bar"],
              ["J4", "~4.8 bar"],
              ["D1", "~5.0 bar"],
              ["D2", "~4.7 bar"],
            ].map(([id, val]) => (
              <text key={id}
                x={NODES[id].x + (id === "D1" || id === "D2" ? 0 : 0)}
                y={NODES[id].y + 24}
                textAnchor="middle" fontSize={9}
                fill="rgba(255,255,255,0.22)"
                fontFamily="'Fira Code', monospace"
                style={{ pointerEvents: "none" }}>{val}</text>
            ))}

            {/* ── Branch label ── */}
            <text x={370} y={190} textAnchor="middle" fontSize={9}
              fill="rgba(255,255,255,0.2)" fontFamily="sans-serif"
              style={{ pointerEvents: "none" }}>Upper branch</text>
            <text x={370} y={310} textAnchor="middle" fontSize={9}
              fill="rgba(255,255,255,0.2)" fontFamily="sans-serif"
              style={{ pointerEvents: "none" }}>Lower branch (valve-controlled)</text>

            {/* ── EKF residual indicator ── */}
            {["S1","J2","J3","J4","J5","D1","D2"].map(id => (
              <circle key={`ekf-${id}`}
                cx={NODES[id].x + 12} cy={NODES[id].y - 12}
                r={4}
                fill="rgba(245,158,11,0.5)"
                stroke="#f59e0b" strokeWidth={0.8}
                style={{ pointerEvents: "none" }}
              />
            ))}
            <text x={58} y={215} fontSize={8} fill="rgba(245,158,11,0.5)"
              fontFamily="'Fira Code', monospace"
              style={{ pointerEvents: "none" }}>● EKF</text>

          </svg>
        </div>

        {/* Info panel */}
        <div style={{
          width: 260,
          background: "rgba(255,255,255,0.02)",
          border: "1px solid rgba(255,255,255,0.06)",
          borderRadius: 12,
          padding: 18,
          display: "flex",
          flexDirection: "column",
        }}>
          {info ? (
            <>
              <div style={{
                width: 3, height: 20,
                background: info.color,
                borderRadius: 2,
                marginBottom: 10,
                boxShadow: `0 0 10px ${info.color}`,
              }} />
              <div style={{ color: info.color, fontFamily: "'Fira Code', monospace", fontSize: 11, fontWeight: 800, marginBottom: 8, lineHeight: 1.4 }}>
                {info.title}
              </div>
              <div style={{ color: "rgba(255,255,255,0.5)", fontSize: 11, lineHeight: 1.7, whiteSpace: "pre-line" }}>
                {info.body}
              </div>
            </>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: 16, flex: 1 }}>
              <div style={{ color: "rgba(255,255,255,0.2)", fontSize: 10, fontFamily: "'Fira Code', monospace", letterSpacing: 1 }}>
                CLICK TO INSPECT
              </div>
              {/* Quick stats */}
              {[
                ["Nodes", "8", "#4ade80"],
                ["Pipes", "7", "#38bdf8"],
                ["Compressor", "1", "#a78bfa"],
                ["Control valve", "1", "#60a5fa"],
                ["Demand nodes", "2", "#f87171"],
                ["EKF state size", "15", "#f59e0b"],
                ["PLC latency", "2 steps", "#94a3b8"],
              ].map(([lbl, val, col]) => (
                <div key={lbl} style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <span style={{ color: "rgba(255,255,255,0.35)", fontSize: 11 }}>{lbl}</span>
                  <span style={{ color: col, fontFamily: "'Fira Code', monospace", fontSize: 12, fontWeight: 700 }}>{val}</span>
                </div>
              ))}
              <div style={{ marginTop: "auto", borderTop: "1px solid rgba(255,255,255,0.06)", paddingTop: 14 }}>
                <div style={{ color: "rgba(255,255,255,0.2)", fontSize: 10, fontFamily: "'Fira Code', monospace", letterSpacing: 1, marginBottom: 8 }}>
                  PIPE PARAMS (uniform)
                </div>
                {[["Diameter", "0.8 m"], ["Length", "40 km"], ["Roughness", "20 μm"], ["Nodal Vol.", "6 m³"]].map(([k,v]) => (
                  <div key={k} style={{ display: "flex", justifyContent: "space-between", marginBottom: 5 }}>
                    <span style={{ color: "rgba(255,255,255,0.3)", fontSize: 10 }}>{k}</span>
                    <span style={{ color: "#38bdf8", fontFamily: "'Fira Code', monospace", fontSize: 10 }}>{v}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      <div style={{ textAlign: "center", paddingBottom: 10, color: "rgba(255,255,255,0.1)", fontSize: 10, fontFamily: "'Fira Code', monospace" }}>
        8 nodes · 7 edges · Darcy-Weisbach flow · EKF state dim = 15
      </div>
    </div>
  );
}
