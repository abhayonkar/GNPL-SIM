import { useState } from "react";

// ── 20-node network topology (mirrors initNetwork.m exactly) ─────────────────
// nodeNames: S1 J1 CS1 J2 J3 J4 CS2 J5 J6 PRS1 J7 STO PRS2 S2 D1-D6
// edges (1-based MATLAB): E1:1→2 E2:2→3 E3:3→4 E4:4→5 E5:5→6 E6:6→7 E7:7→8
//   E8:4→9(valve) E9:9→10 E10:10→15 E11:10→16 E12:5→11 E13:14→11 E14:11→12(valve)
//   E15:12→8(valve) E16:8→13 E17:13→17 E18:13→18 E19:6→19 E20:11→20

const W = 1100, H = 520;

const NODES = {
  // Sources
  S1:   { x: 55,  y: 280, type: "source",     label: "S1",   sub: "Source",     idx: 1  },
  S2:   { x: 660, y: 160, type: "source",      label: "S2",   sub: "Source",     idx: 14 },
  // Main trunk junctions
  J1:   { x: 150, y: 280, type: "junction",    label: "J1",   sub: "Junction",   idx: 2  },
  J2:   { x: 360, y: 280, type: "junction",    label: "J2",   sub: "Branch",     idx: 4  },
  J3:   { x: 480, y: 280, type: "junction",    label: "J3",   sub: "Junction",   idx: 5  },
  J4:   { x: 605, y: 280, type: "junction",    label: "J4",   sub: "Junction",   idx: 6  },
  J5:   { x: 835, y: 280, type: "junction",    label: "J5",   sub: "Junction",   idx: 8  },
  // Compressors
  CS1:  { x: 250, y: 280, type: "compressor",  label: "CS1",  sub: "Compressor", idx: 3  },
  CS2:  { x: 715, y: 280, type: "compressor",  label: "CS2",  sub: "Compressor", idx: 7  },
  // Upper branch
  J6:   { x: 360, y: 410, type: "junction",    label: "J6",   sub: "Junction",   idx: 9  },
  J7:   { x: 540, y: 155, type: "junction",    label: "J7",   sub: "Junction",   idx: 11 },
  // PRS stations
  PRS1: { x: 480, y: 410, type: "prs",         label: "PRS1", sub: "30 bar",     idx: 10 },
  PRS2: { x: 945, y: 280, type: "prs",         label: "PRS2", sub: "25 bar",     idx: 13 },
  // Storage
  STO:  { x: 700, y: 80,  type: "storage",     label: "STO",  sub: "Cavern",     idx: 12 },
  // Demand nodes
  D1:   { x: 575, y: 475, type: "demand",      label: "D1",   sub: "Demand",     idx: 15 },
  D2:   { x: 575, y: 345, type: "demand",      label: "D2",   sub: "Demand",     idx: 16 },
  D3:   { x: 1030,y: 215, type: "demand",      label: "D3",   sub: "Demand",     idx: 17 },
  D4:   { x: 1030,y: 345, type: "demand",      label: "D4",   sub: "Demand",     idx: 18 },
  D5:   { x: 605, y: 65,  type: "demand",      label: "D5",   sub: "Demand",     idx: 19 },
  D6:   { x: 430, y: 65,  type: "demand",      label: "D6",   sub: "Demand",     idx: 20 },
};

const EDGES = [
  { id: "E1",  from: "S1",   to: "J1",   type: "pipe"  },
  { id: "E2",  from: "J1",   to: "CS1",  type: "pipe"  },
  { id: "E3",  from: "CS1",  to: "J2",   type: "pipe"  },
  { id: "E4",  from: "J2",   to: "J3",   type: "pipe"  },
  { id: "E5",  from: "J3",   to: "J4",   type: "pipe"  },
  { id: "E6",  from: "J4",   to: "CS2",  type: "pipe"  },
  { id: "E7",  from: "CS2",  to: "J5",   type: "pipe"  },
  { id: "E8",  from: "J2",   to: "J6",   type: "valve" },   // upper branch valve
  { id: "E9",  from: "J6",   to: "PRS1", type: "pipe"  },
  { id: "E10", from: "PRS1", to: "D1",   type: "pipe"  },
  { id: "E11", from: "PRS1", to: "D2",   type: "pipe"  },
  { id: "E12", from: "J3",   to: "J7",   type: "pipe"  },
  { id: "E13", from: "S2",   to: "J7",   type: "pipe"  },
  { id: "E14", from: "J7",   to: "STO",  type: "valve" },   // inject valve
  { id: "E15", from: "STO",  to: "J5",   type: "valve" },   // withdraw valve
  { id: "E16", from: "J5",   to: "PRS2", type: "pipe"  },
  { id: "E17", from: "PRS2", to: "D3",   type: "pipe"  },
  { id: "E18", from: "PRS2", to: "D4",   type: "pipe"  },
  { id: "E19", from: "J4",   to: "D5",   type: "pipe"  },
  { id: "E20", from: "J7",   to: "D6",   type: "pipe"  },
];

const PIPE_PARAMS = { D: "0.8 m", L: "40 km", rough: "20 μm" };

const NOMINAL_PRESSURES = {
  S1: "50 bar", J1: "50 bar", CS1: "50 bar", J2: "50 bar",
  J3: "50 bar", J4: "50 bar", CS2: "50 bar", J5: "50 bar",
  J6: "48 bar", PRS1: "30 bar", J7: "50 bar", STO: "50 bar",
  PRS2: "25 bar", S2: "48 bar",
  D1: "30 bar", D2: "30 bar", D3: "25 bar",
  D4: "25 bar", D5: "45 bar", D6: "48 bar",
};

const INFO = {
  S1:   { title: "Source S1",           color: "#4ade80",  body: "Primary gas source. Pressure driven by generateSourceProfile.m — AR(1) random walk + multi-frequency oscillations. Init: 50 bar. Attack A1 manipulates this node." },
  S2:   { title: "Source S2",           color: "#4ade80",  body: "Secondary gas source (node 14). Feeds J7 via edge E13. Init: 48 bar. Provides redundancy for the eastern distribution network." },
  J1:   { title: "Junction J1",         color: "#64748b",  body: "Pre-compressor junction (node 2). Connects source S1 to CS1 inlet via E1→E2. Nodal volume 6 m³ (lumped capacitance model)." },
  CS1:  { title: "Compressor CS1",      color: "#a78bfa",  body: "Primary compressor (node 3). CS1 PID maintains p_D1 at 30 bar setpoint. Head: H = 800 − 0.8ṁ − 0.002ṁ². Efficiency: η = 0.82 − 0.002ṁ. Ratio range 1.05–1.80. cs1_alarm fires at ratio ≥ 1.75." },
  J2:   { title: "Junction J2 — Branch", color: "#64748b", body: "Main branch junction (node 4). Splits flow into: main trunk E4→J3, and side branch via valve E8→J6→PRS1. Incidence matrix B(20×20) governs mass balance." },
  J3:   { title: "Junction J3",          color: "#64748b", body: "Mid-network junction (node 5). Receives flow from J2 via E4 and connects to J7 via E12 (upper diagonal branch toward second source). Attack A8 targets edge E12 (pipeline leak)." },
  J4:   { title: "Junction J4",          color: "#64748b", body: "Junction before CS2 (node 6). Also feeds demand D5 via E19 (vertical bypass). Connects to CS2 via E6." },
  CS2:  { title: "Compressor CS2",       color: "#a78bfa", body: "Secondary compressor (node 7). CS2 PID maintains p_D3 at 25 bar setpoint. Head: H = 500 − 0.5ṁ − 0.001ṁ². Ratio range 1.02–1.60. cs2_alarm fires at ratio ≥ 1.55." },
  J5:   { title: "Junction J5",          color: "#64748b", body: "Eastern distribution junction (node 8). Receives output from CS2 (E7) and optionally from storage cavern STO via valve E15. Feeds PRS2 via E16." },
  J6:   { title: "Junction J6",          color: "#64748b", body: "Side branch junction (node 9). Fed from J2 via valve E8. Feeds PRS1 via E9. Opens when p_J6 < 28 bar, closes when p_J6 > 55 bar." },
  PRS1: { title: "PRS1 — 30 bar",        color: "#34d399", body: "Pressure Regulating Station (node 10). Downstream setpoint 30 bar. First-order throttle response τ = 5s, deadband ±0.5 bar. Feeds D1 (E10) and D2 (E11). prs1_active coil set when p_PRS1 > setpoint." },
  J7:   { title: "Junction J7",          color: "#64748b", body: "Upper mid-network junction (node 11). Receives flow from J3 (E12) and second source S2 (E13). Connects to storage STO via valve E14 and to demand D6 via E20." },
  STO:  { title: "Storage Cavern STO",   color: "#60a5fa", body: "Underground storage node (node 12). Bidirectional: inject (E14) when p_J7 > 52 bar, withdraw (E15) when p_J5 < 46 bar. Inventory tracked as fraction 0–1. Creates a loop in the network topology." },
  PRS2: { title: "PRS2 — 25 bar",        color: "#34d399", body: "Pressure Regulating Station (node 13). Downstream setpoint 25 bar. Feeds D3 (E17) and D4 (E18). Behaviour same as PRS1: first-order τ = 5s." },
  D1:   { title: "Demand D1",            color: "#f87171", body: "Primary delivery node (node 15). CS1 PID target: 30 bar. EKF tracks this node for CS1 control feedback. Attack A5 spoofs the pressure sensor at this node." },
  D2:   { title: "Demand D2",            color: "#f87171", body: "Secondary delivery via PRS1 (node 16). Receives flow from PRS1 via E11." },
  D3:   { title: "Demand D3",            color: "#f87171", body: "Eastern delivery node (node 17). CS2 PID target: 25 bar. Attack A6 spoofs flow meter on feeding edges." },
  D4:   { title: "Demand D4",            color: "#f87171", body: "Eastern delivery node (node 18). Receives flow from PRS2 via E18." },
  D5:   { title: "Demand D5",            color: "#f87171", body: "Direct bypass demand (node 19). Receives flow from J4 via E19 without PRS throttling." },
  D6:   { title: "Demand D6",            color: "#f87171", body: "Upper network demand (node 20). Receives flow from J7 via E20. Attack A4 manipulates demand at this type of node." },
  E8:   { title: "Valve E8: J2 → J6",   color: "#60a5fa", body: "Side branch isolation valve. Controlled by PLC: open (1000) when p_J6 < 28 bar, close (0) when p_J6 > 55 bar. Command delivered via Modbus register 102. Attack A3 can force this valve closed." },
  E14:  { title: "Valve E14: J7 → STO (inject)", color: "#60a5fa", body: "Storage injection valve. Opens when p_J7 > 52 bar. Coil 3 (sto_inject_active) set when active. Part of the storage loop E14→STO→E15." },
  E15:  { title: "Valve E15: STO → J5 (withdraw)", color: "#60a5fa", body: "Storage withdrawal valve. Opens when p_J5 < 46 bar. Coil 4 (sto_withdraw_active) set when active. Closes the network loop STO→J5." },
};

function midpoint(a, b) {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

function ValveSymbol({ from, to, id, selected, onClick }) {
  const mid = midpoint(from, to);
  const dx = to.x - from.x, dy = to.y - from.y;
  const deg = Math.atan2(dy, dx) * 180 / Math.PI;
  const isSelected = selected === id;
  const col = isSelected ? "#f59e0b" : "#60a5fa";
  return (
    <g transform={`translate(${mid.x},${mid.y}) rotate(${deg})`}
       onClick={onClick} style={{ cursor: "pointer" }}>
      <line x1={-30} y1={0} x2={30} y2={0} stroke={isSelected ? "#f59e0b" : "#334155"} strokeWidth={3.5} />
      <polygon points="-10,-8 10,-8 0,0"  fill={col} opacity={0.9} />
      <polygon points="-10, 8 10, 8 0,0"  fill={col} opacity={0.9} />
      <line x1={0} y1={-8} x2={0} y2={-16} stroke={col} strokeWidth={1.5} />
      <rect x={-5} y={-19} width={10} height={3} rx={1.5} fill={col} />
      <rect x={-12} y={-10} width={24} height={20} rx={2}
        fill="none" stroke={col} strokeWidth={1.2} opacity={0.4} />
    </g>
  );
}

function CompressorSymbol({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const col = isSelected ? "#f59e0b" : "#a78bfa";
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <circle cx={0} cy={0} r={20}
        fill={isSelected ? "rgba(245,158,11,0.15)" : "rgba(167,139,250,0.12)"}
        stroke={col} strokeWidth={2}
        style={{ filter: isSelected ? `drop-shadow(0 0 8px ${col})` : "none", transition: "all 0.2s" }} />
      {[0,60,120,180,240,300].map(deg => (
        <line key={deg} x1={0} y1={0}
          x2={Math.cos(deg*Math.PI/180)*14} y2={Math.sin(deg*Math.PI/180)*14}
          stroke={col} strokeWidth={1.8} strokeLinecap="round" />
      ))}
      <circle cx={0} cy={0} r={3.5} fill={col} />
      <text x={0} y={-27} textAnchor="middle" fontSize={9}
        fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
    </g>
  );
}

function PRSSymbol({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const col = isSelected ? "#f59e0b" : "#34d399";
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <rect x={-16} y={-12} width={32} height={24} rx={4}
        fill={isSelected ? "rgba(245,158,11,0.15)" : "rgba(52,211,153,0.12)"}
        stroke={col} strokeWidth={1.8}
        style={{ filter: isSelected ? `drop-shadow(0 0 6px ${col})` : "none", transition: "all 0.2s" }} />
      <line x1={-8} y1={0} x2={8} y2={0} stroke={col} strokeWidth={1.5} />
      <line x1={0} y1={-5} x2={0} y2={5} stroke={col} strokeWidth={1.5} />
      <text x={0} y={-20} textAnchor="middle" fontSize={9}
        fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
      <text x={0} y={-11} textAnchor="middle" fontSize={7.5}
        fill={`${col}99`} fontFamily="'Fira Code', monospace">{node.sub}</text>
    </g>
  );
}

function StorageSymbol({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const col = isSelected ? "#f59e0b" : "#60a5fa";
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <ellipse cx={0} cy={0} rx={20} ry={12}
        fill={isSelected ? "rgba(245,158,11,0.15)" : "rgba(96,165,250,0.12)"}
        stroke={col} strokeWidth={2}
        style={{ filter: isSelected ? `drop-shadow(0 0 6px ${col})` : "none", transition: "all 0.2s" }} />
      <rect x={-20} y={-12} width={40} height={18}
        fill={isSelected ? "rgba(245,158,11,0.08)" : "rgba(96,165,250,0.08)"}
        stroke="none" />
      <ellipse cx={0} cy={6} rx={20} ry={12}
        fill="none" stroke={col} strokeWidth={2} />
      <text x={0} y={-20} textAnchor="middle" fontSize={9}
        fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
    </g>
  );
}

function NodeCircle({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const isSource  = node.type === "source";
  const isDemand  = node.type === "demand";
  const col = isSource ? "#4ade80" : isDemand ? "#f87171" : "#64748b";
  const fillCol = isSelected
    ? (isSource ? "rgba(74,222,128,0.2)" : isDemand ? "rgba(248,113,113,0.2)" : "rgba(100,116,139,0.2)")
    : (isSource ? "rgba(74,222,128,0.08)" : isDemand ? "rgba(248,113,113,0.08)" : "rgba(100,116,139,0.08)");
  const r = isDemand ? 11 : isSource ? 13 : 9;

  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <circle cx={0} cy={0} r={r}
        fill={fillCol}
        stroke={isSelected ? "#f59e0b" : col}
        strokeWidth={isSelected ? 2.5 : 1.5}
        style={{ filter: isSelected ? "drop-shadow(0 0 7px #f59e0b)" : "none", transition: "all 0.2s" }} />
      {isSource && (
        <>
          <line x1={-5} y1={0} x2={5} y2={0} stroke={col} strokeWidth={1.8} />
          <line x1={0} y1={-5} x2={0} y2={5} stroke={col} strokeWidth={1.8} />
        </>
      )}
      {isDemand && (
        <polygon points="0,-6 5,3 -5,3" fill={col} opacity={0.8} />
      )}
      <text x={0} y={r + 13} textAnchor="middle" fontSize={10} fontWeight="800"
        fill={isSelected ? "#f59e0b" : col}
        fontFamily="'Fira Code', monospace"
        style={{ pointerEvents: "none" }}>
        {node.label}
      </text>
    </g>
  );
}

export default function App() {
  const [selected, setSelected] = useState(null);
  const sel = (id) => () => setSelected(prev => prev === id ? null : id);
  const info = selected ? (INFO[selected] || null) : null;

  const specialTypes = new Set(["compressor","prs","storage"]);
  const regularNodes = Object.entries(NODES).filter(([,n]) => !specialTypes.has(n.type));
  const pipes  = EDGES.filter(e => e.type === "pipe");
  const valves = EDGES.filter(e => e.type === "valve");

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
      <div style={{ padding: "18px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div>
          <div style={{ fontSize: 10, color: "#38bdf8", fontFamily: "'Fira Code', monospace", letterSpacing: 3, textTransform: "uppercase" }}>
            Physical Network Topology
          </div>
          <h1 style={{ margin: "3px 0 0", fontSize: 19, fontWeight: 800, color: "#f1f5f9", letterSpacing: -0.5 }}>
            20-Node Gas Transmission Pipeline
          </h1>
        </div>
        <div style={{ display: "flex", gap: 16, fontSize: 10, color: "rgba(255,255,255,0.35)", flexWrap: "wrap", maxWidth: 480 }}>
          {[
            ["●", "#4ade80", "Source (2)"],
            ["●", "#64748b", "Junction (7)"],
            ["▲", "#f87171", "Demand (6)"],
            ["◎", "#a78bfa", "Compressor (2)"],
            ["▬", "#34d399", "PRS (2)"],
            ["⌀", "#60a5fa", "Storage (1)"],
            ["⋈", "#60a5fa", "Valve (3)"],
          ].map(([sym, col, lbl]) => (
            <div key={lbl} style={{ display: "flex", alignItems: "center", gap: 4 }}>
              <span style={{ color: col, fontSize: 12 }}>{sym}</span>
              <span>{lbl}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Main */}
      <div style={{ display: "flex", flex: 1, padding: "12px 16px 16px", gap: 14, minHeight: 560 }}>
        {/* SVG */}
        <div style={{
          flex: 1,
          background: "rgba(255,255,255,0.015)",
          border: "1px solid rgba(255,255,255,0.06)",
          borderRadius: 12,
          overflow: "hidden",
          position: "relative",
        }}>
          {/* Grid */}
          <svg width="100%" height="100%" style={{ position: "absolute", top: 0, left: 0, pointerEvents: "none" }}>
            <defs>
              <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 40" fill="none" stroke="rgba(255,255,255,0.025)" strokeWidth="1" />
              </pattern>
            </defs>
            <rect width="100%" height="100%" fill="url(#grid)" />
          </svg>

          <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="100%"
            style={{ position: "relative", zIndex: 1 }}>

            <defs>
              <marker id="arrowBlue" markerWidth="7" markerHeight="7" refX="5" refY="2.5" orient="auto">
                <path d="M0,0 L0,5 L7,2.5 z" fill="rgba(56,189,248,0.4)" />
              </marker>
              <marker id="arrowYellow" markerWidth="7" markerHeight="7" refX="5" refY="2.5" orient="auto">
                <path d="M0,0 L0,5 L7,2.5 z" fill="#f59e0b" />
              </marker>
              <marker id="arrowGreen" markerWidth="7" markerHeight="7" refX="5" refY="2.5" orient="auto">
                <path d="M0,0 L0,5 L7,2.5 z" fill="rgba(74,222,128,0.5)" />
              </marker>
              <filter id="glow">
                <feGaussianBlur stdDeviation="2.5" result="coloredBlur" />
                <feMerge><feMergeNode in="coloredBlur" /><feMergeNode in="SourceGraphic" /></feMerge>
              </filter>
            </defs>

            {/* Branch zone labels */}
            <text x={420} y={235} textAnchor="middle" fontSize={8.5}
              fill="rgba(255,255,255,0.14)" fontFamily="sans-serif">main trunk</text>
            <text x={420} y={385} textAnchor="middle" fontSize={8.5}
              fill="rgba(255,255,255,0.14)" fontFamily="sans-serif">side branch (valve)</text>
            <text x={590} y={115} textAnchor="middle" fontSize={8.5}
              fill="rgba(255,255,255,0.14)" fontFamily="sans-serif">storage loop</text>

            {/* ── Pipe edges ── */}
            {pipes.map(e => {
              const a = NODES[e.from], b = NODES[e.to];
              const isSel = selected === e.id;
              return (
                <g key={e.id}>
                  {isSel && <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke="#f59e0b" strokeWidth={9} opacity={0.12} strokeLinecap="round" />}
                  <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke={isSel ? "#f59e0b" : "#2d3f55"}
                    strokeWidth={isSel ? 4.5 : 3.5}
                    strokeLinecap="round"
                    style={{ cursor: "pointer", transition: "all 0.2s" }}
                    onClick={sel(e.id)} />
                  {/* Edge label */}
                  <text
                    x={(a.x + b.x) / 2 + (Math.abs(a.y - b.y) > 20 ? 12 : 0)}
                    y={(a.y + b.y) / 2 + (Math.abs(a.y - b.y) > 20 ? 0 : -10)}
                    textAnchor="middle" fontSize={9}
                    fill={isSel ? "#f59e0b" : "rgba(100,116,139,0.65)"}
                    fontFamily="'Fira Code', monospace"
                    style={{ pointerEvents: "none" }}>{e.id}</text>
                </g>
              );
            })}

            {/* ── Valve edges ── */}
            {valves.map(e => {
              const a = NODES[e.from], b = NODES[e.to];
              const isSel = selected === e.id;
              return (
                <g key={e.id}>
                  {isSel && <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke="#f59e0b" strokeWidth={9} opacity={0.12} strokeLinecap="round" />}
                  <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke={isSel ? "#f59e0b" : "#2d3f55"}
                    strokeWidth={3.5} strokeLinecap="round"
                    strokeDasharray="6 3"
                    style={{ cursor: "pointer" }}
                    onClick={sel(e.id)} />
                  <ValveSymbol from={a} to={b} id={e.id} selected={selected} onClick={sel(e.id)} />
                  <text
                    x={(a.x + b.x) / 2 + (e.id === "E8" ? -18 : 16)}
                    y={(a.y + b.y) / 2 + (e.id === "E8" ? 0 : 0)}
                    textAnchor="middle" fontSize={9}
                    fill={isSel ? "#f59e0b" : "rgba(96,165,250,0.7)"}
                    fontFamily="'Fira Code', monospace"
                    style={{ pointerEvents: "none" }}>{e.id}</text>
                </g>
              );
            })}

            {/* ── Special equipment ── */}
            <CompressorSymbol node={NODES.CS1} id="CS1" selected={selected} onClick={sel("CS1")} />
            <CompressorSymbol node={NODES.CS2} id="CS2" selected={selected} onClick={sel("CS2")} />
            <PRSSymbol node={NODES.PRS1} id="PRS1" selected={selected} onClick={sel("PRS1")} />
            <PRSSymbol node={NODES.PRS2} id="PRS2" selected={selected} onClick={sel("PRS2")} />
            <StorageSymbol node={NODES.STO} id="STO" selected={selected} onClick={sel("STO")} />

            {/* ── Regular nodes ── */}
            {regularNodes.map(([id, node]) => (
              <NodeCircle key={id} node={node} id={id} selected={selected} onClick={sel(id)} />
            ))}

            {/* ── Nominal pressure labels ── */}
            {Object.entries(NOMINAL_PRESSURES).map(([id, val]) => {
              const n = NODES[id];
              if (!n) return null;
              const isSpecial = specialTypes.has(n.type);
              return (
                <text key={`p-${id}`}
                  x={n.x}
                  y={n.y + (isSpecial ? 22 : n.type === "demand" ? -4 : 22)}
                  textAnchor="middle" fontSize={8}
                  fill="rgba(255,255,255,0.18)"
                  fontFamily="'Fira Code', monospace"
                  style={{ pointerEvents: "none" }}>{val}</text>
              );
            })}

            {/* ── EKF indicators ── */}
            {["S1","J2","J3","J4","J5","PRS1","PRS2","D1","D3"].map(id => {
              const n = NODES[id];
              return (
                <circle key={`ekf-${id}`}
                  cx={n.x + 14} cy={n.y - 14}
                  r={3.5}
                  fill="rgba(245,158,11,0.45)"
                  stroke="#f59e0b" strokeWidth={0.8}
                  style={{ pointerEvents: "none" }} />
              );
            })}
            <text x={55} y={230} fontSize={7.5} fill="rgba(245,158,11,0.45)"
              fontFamily="'Fira Code', monospace"
              style={{ pointerEvents: "none" }}>● EKF-40</text>
          </svg>
        </div>

        {/* Info panel */}
        <div style={{
          width: 270,
          background: "rgba(255,255,255,0.02)",
          border: "1px solid rgba(255,255,255,0.06)",
          borderRadius: 12,
          padding: 16,
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
        }}>
          {info ? (
            <>
              <div style={{ width: 3, height: 18, background: info.color, borderRadius: 2, marginBottom: 10, boxShadow: `0 0 8px ${info.color}` }} />
              <div style={{ color: info.color, fontFamily: "'Fira Code', monospace", fontSize: 11, fontWeight: 800, marginBottom: 8, lineHeight: 1.4 }}>
                {info.title}
              </div>
              <div style={{ color: "rgba(255,255,255,0.48)", fontSize: 11, lineHeight: 1.7 }}>
                {info.body}
              </div>
            </>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: 12, flex: 1 }}>
              <div style={{ color: "rgba(255,255,255,0.18)", fontSize: 9, fontFamily: "'Fira Code', monospace", letterSpacing: 1 }}>
                CLICK NODE / EDGE TO INSPECT
              </div>
              {[
                ["Nodes",          "20",       "#4ade80"],
                ["Edges",          "20",       "#38bdf8"],
                ["Sources",        "2",        "#4ade80"],
                ["Compressors",    "CS1 + CS2","#a78bfa"],
                ["PRS stations",   "PRS1 + PRS2","#34d399"],
                ["Storage",        "1 cavern", "#60a5fa"],
                ["Control valves", "E8 E14 E15","#60a5fa"],
                ["Demand nodes",   "D1–D6",    "#f87171"],
                ["EKF state dim",  "40 (20p+20q)","#f59e0b"],
                ["Modbus regs",    "70 + 7 coils","#22d3ee"],
                ["Attack labels",  "A1–A10",   "#f87171"],
              ].map(([lbl, val, col]) => (
                <div key={lbl} style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <span style={{ color: "rgba(255,255,255,0.32)", fontSize: 10 }}>{lbl}</span>
                  <span style={{ color: col, fontFamily: "'Fira Code', monospace", fontSize: 10, fontWeight: 700 }}>{val}</span>
                </div>
              ))}
              <div style={{ marginTop: "auto", borderTop: "1px solid rgba(255,255,255,0.06)", paddingTop: 12 }}>
                <div style={{ color: "rgba(255,255,255,0.18)", fontSize: 9, fontFamily: "'Fira Code', monospace", letterSpacing: 1, marginBottom: 8 }}>
                  PIPE PARAMS (nominal)
                </div>
                {[["Diameter","0.8 m"],["Length","40 km (main)"],["Roughness","20 μm"],["Nodal Vol.","6 m³"],["Init pressure","50 bar"],["Speed of sound","350 m/s"]].map(([k,v]) => (
                  <div key={k} style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                    <span style={{ color: "rgba(255,255,255,0.28)", fontSize: 9 }}>{k}</span>
                    <span style={{ color: "#38bdf8", fontFamily: "'Fira Code', monospace", fontSize: 9 }}>{v}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      <div style={{ textAlign: "center", paddingBottom: 8, color: "rgba(255,255,255,0.1)", fontSize: 10, fontFamily: "'Fira Code', monospace" }}>
        20 nodes · 20 edges · 3 valve edges (E8/E14/E15) · Darcy-Weisbach + Peng-Robinson EOS · EKF state dim = 40
      </div>
    </div>
  );
}
