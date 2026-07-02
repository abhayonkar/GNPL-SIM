import { useState } from "react";

const W = 1200, H = 530;

// Node positions are deliberately asymmetric so no two ring nodes
// share an x or y coordinate — all ring pipes become diagonals.
const NODES = {
  CGS1: { x: 572,  y: 38,   type: "source",     label: "CGS1", sub: "GSPL Kalol",   idx: 1  },
  CGS2: { x: 60,   y: 342,  type: "source",      label: "CGS2", sub: "GSPL Adalaj",  idx: 2  },
  CS1:  { x: 572,  y: 112,  type: "compressor",  label: "CS1",  sub: "Booster",      idx: 3  },
  STO:  { x: 1058, y: 78,   type: "storage",     label: "STO",  sub: "Kalol Cavern", idx: 4  },
  // Ring junctions — staggered so every ring pipe is diagonal
  JT1:  { x: 572,  y: 192,  type: "junction",    label: "JT1",  sub: "Ring N",       idx: 5  },
  JT2:  { x: 318,  y: 220,  type: "junction",    label: "JT2",  sub: "Ring NW",      idx: 6  },
  JT3:  { x: 855,  y: 178,  type: "junction",    label: "JT3",  sub: "Ring NE",      idx: 7  },
  JT4:  { x: 178,  y: 342,  type: "junction",    label: "JT4",  sub: "Ring W",       idx: 8  },
  JT5:  { x: 1022, y: 312,  type: "junction",    label: "JT5",  sub: "Ring E",       idx: 9  },
  JT6:  { x: 298,  y: 462,  type: "junction",    label: "JT6",  sub: "Ring SW",      idx: 10 },
  JT7:  { x: 870,  y: 452,  type: "junction",    label: "JT7",  sub: "Ring SE",      idx: 11 },
  JT8:  { x: 608,  y: 482,  type: "junction",    label: "JT8",  sub: "Ring S",       idx: 12 },
  // DRS stations — offset at natural angles, not perpendicular
  DRS1: { x: 192,  y: 232,  type: "drs",         label: "DRS1", sub: "14 barg",      idx: 13 },
  DRS2: { x: 465,  y: 118,  type: "drs",         label: "DRS2", sub: "16 barg",      idx: 14 },
  DRS3: { x: 988,  y: 198,  type: "drs",         label: "DRS3", sub: "14 barg",      idx: 15 },
  DRS4: { x: 172,  y: 478,  type: "drs",         label: "DRS4", sub: "14 barg",      idx: 16 },
  DRS5: { x: 1058, y: 468,  type: "drs",         label: "DRS5", sub: "20 barg",      idx: 17 },
  DRS6: { x: 608,  y: 342,  type: "drs",         label: "DRS6", sub: "14 barg",      idx: 18 },
  DRS7: { x: 448,  y: 475,  type: "drs",         label: "DRS7", sub: "14 barg",      idx: 19 },
  // CNG stations — tapped directly off HP ring
  CNG1: { x: 382,  y: 345,  type: "cng",         label: "CNG1", sub: "Akshardham",   idx: 20 },
  CNG2: { x: 775,  y: 345,  type: "cng",         label: "CNG2", sub: "Sector 16",    idx: 21 },
  CNG3: { x: 1158, y: 318,  type: "cng",         label: "CNG3", sub: "GIDC North",   idx: 22 },
  CNG4: { x: 840,  y: 515,  type: "cng",         label: "CNG4", sub: "GN South",     idx: 23 },
  // Demand zones
  D1:   { x: 58,   y: 232,  type: "demand",      label: "D1",   sub: "Sec 1-7",      idx: 24 },
  D2:   { x: 465,  y: 38,   type: "demand",      label: "D2",   sub: "Sec 8-14",     idx: 25 },
  D3:   { x: 1158, y: 178,  type: "demand",      label: "D3",   sub: "Sec 15-21",    idx: 26 },
  D4:   { x: 58,   y: 478,  type: "demand",      label: "D4",   sub: "Sec 22-24",    idx: 27 },
  D5:   { x: 378,  y: 515,  type: "demand",      label: "D5",   sub: "Sec 25-28",    idx: 28 },
  D6:   { x: 638,  y: 515,  type: "demand",      label: "D6",   sub: "Sachivalaya",  idx: 29 },
};

// dn field drives stroke width: DN250=4.0, DN200=3.5, DN150=2.8, DN100=2.0, DN80=1.5
const EDGES = [
  { id: "E1",  from: "CGS1", to: "CS1",  type: "pipe",  dn: "DN250" },
  { id: "E2",  from: "CS1",  to: "JT1",  type: "pipe",  dn: "DN250" },
  { id: "E3",  from: "JT1",  to: "JT2",  type: "pipe",  len: "9 km",  dn: "DN250" },
  { id: "E4",  from: "JT1",  to: "JT3",  type: "pipe",  len: "10 km", dn: "DN250" },
  { id: "E5",  from: "JT2",  to: "JT4",  type: "pipe",  len: "7 km",  dn: "DN200" },
  { id: "E6",  from: "JT3",  to: "JT5",  type: "pipe",  len: "8 km",  dn: "DN200" },
  { id: "E7",  from: "JT4",  to: "JT6",  type: "pipe",  len: "7 km",  dn: "DN200" },
  { id: "E8",  from: "JT5",  to: "JT7",  type: "pipe",  len: "7 km",  dn: "DN200" },
  { id: "E9",  from: "JT6",  to: "JT8",  type: "pipe",  len: "10 km", dn: "DN200" },
  { id: "E10", from: "JT7",  to: "JT8",  type: "pipe",  len: "10 km", dn: "DN200" },
  { id: "E11", from: "CGS2", to: "JT4",  type: "pipe",  len: "6 km",  dn: "DN150" },
  { id: "E12", from: "JT3",  to: "STO",  type: "valve" },
  { id: "E13", from: "STO",  to: "JT1",  type: "valve" },
  { id: "E14", from: "JT1",  to: "DRS6", type: "pipe",  len: "5 km",  dn: "DN150" },
  { id: "E15", from: "DRS6", to: "JT8",  type: "pipe",  len: "5 km",  dn: "DN150" },
  { id: "E16", from: "JT2",  to: "DRS1", type: "pipe",  len: "4 km",  dn: "DN100" },
  { id: "E17", from: "JT1",  to: "DRS2", type: "pipe",  len: "5 km",  dn: "DN100" },
  { id: "E18", from: "JT3",  to: "DRS3", type: "pipe",  len: "4 km",  dn: "DN100" },
  { id: "E19", from: "JT6",  to: "DRS4", type: "pipe",  len: "4 km",  dn: "DN100" },
  { id: "E20", from: "JT7",  to: "DRS5", type: "pipe",  len: "4 km",  dn: "DN150" },
  { id: "E21", from: "JT6",  to: "DRS7", type: "pipe",  len: "5 km",  dn: "DN100" },
  { id: "E22", from: "JT4",  to: "CNG1", type: "pipe",  len: "3 km",  dn: "DN100" },
  { id: "E23", from: "DRS6", to: "CNG2", type: "pipe",  len: "3 km",  dn: "DN100" },
  { id: "E24", from: "JT5",  to: "CNG3", type: "pipe",  len: "4 km",  dn: "DN100" },
  { id: "E25", from: "JT8",  to: "CNG4", type: "pipe",  len: "4 km",  dn: "DN80"  },
  { id: "E26", from: "DRS1", to: "D1",   type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E27", from: "DRS2", to: "D2",   type: "pipe",  len: "4 km",  dn: "DN80"  },
  { id: "E28", from: "DRS3", to: "D3",   type: "pipe",  len: "4 km",  dn: "DN80"  },
  { id: "E29", from: "DRS4", to: "D4",   type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E30", from: "DRS7", to: "D5",   type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E31", from: "DRS6", to: "D6",   type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E32", from: "JT2",  to: "JT6",  type: "pipe",  len: "8 km",  dn: "DN150" },
  { id: "E33", from: "JT3",  to: "JT7",  type: "pipe",  len: "8 km",  dn: "DN150" },
];

const NOMINAL_PRESSURES = {
  CGS1:"26 bar", CGS2:"24 bar", CS1:"26 bar", STO:"24 bar",
  JT1:"24 bar",  JT2:"23 bar",  JT3:"23 bar",
  JT4:"22 bar",  JT5:"22 bar",
  JT6:"21 bar",  JT7:"21 bar",  JT8:"20 bar",
  DRS1:"14 bar", DRS2:"16 bar", DRS3:"14 bar",
  DRS4:"14 bar", DRS5:"20 bar", DRS6:"14 bar", DRS7:"14 bar",
  CNG1:"22 bar", CNG2:"22 bar", CNG3:"22 bar", CNG4:"20 bar",
  D1:"14 bar", D2:"16 bar", D3:"14 bar",
  D4:"14 bar", D5:"14 bar", D6:"14 bar",
};

const INFO = {
  CGS1: { title: "CGS1 — GSPL Kalol Interconnect (North Entry)", color: "#15803d",
    body: "Primary City Gate Station at GSPL Kalol-Ahmedabad 18\" HT-2 transmission pipeline offtake (north entry, Gandhinagar boundary). Inlet ~55 barg, outlet 26 barg (PNGRB T4S MAOP). Equipment: turbine meter, GC chromatograph, slam-shut valve (28 barg trip), dual active/monitor regulators. Flow: 450,000 SCMD max. Gas: SG 0.62, GCV 8,200 kcal/SCM (Hazira-sourced ONGC/GAIL supply)." },
  CGS2: { title: "CGS2 — GSPL Adalaj Feed (SW Entry)", color: "#15803d",
    body: "Secondary City Gate Station on the GSPL Gandhinagar Lateral (SW entry). Provides redundancy to western ring arm via JT4 (E11). Reduces GSPL transmission pressure to 22-24 barg. Feeds JT4 during high-demand periods or CGS1 maintenance. Creep-relief valve at 27 barg." },
  CS1: { title: "CS1 — Ring Booster Station", color: "#6d28d9",
    body: "Reciprocating booster compressor at CGS1 outlet. Boosts from 20 barg (min CGS1 delivery) to 26 barg ring MAOP. Installed capacity 250 kW. Compression ratio range 1.02-1.30. Bypassed automatically when CGS1 outlet >= 24 barg. PID control maintains ring N pressure (JT1) at 24 barg setpoint." },
  STO: { title: "STO — Kalol Salt Cavern Storage", color: "#1d4ed8",
    body: "Underground salt cavern storage linked to NE ring (JT3). Bidirectional: inject via valve E12 when JT3 > 24 barg (surplus); withdraw via E13 when JT1 < 20 barg (deficit). Working capacity 2.5 MMSCM. Cavern pressure range 18-26 barg. Provides peak-shaving for winter demand surge (+35% seasonal factor)." },
  JT1: { title: "JT1 — North Hub Junction (Ring Apex)", color: "#475569",
    body: "Primary HP ring junction at CS1 outlet (north apex). Distributes flow to NW arm (E3->JT2), NE arm (E4->JT3), central branch to DRS6 (E14), and DRS2 spur (E17). 4 connected edges. Nominal 24 barg. Key SCADA telemetry point — RTU at this node." },
  JT2: { title: "JT2 — NW Ring Junction", color: "#475569",
    body: "North-west ring junction. Connected to JT1 (E3, 9 km DN250), JT4 (E5, 7 km DN200), DRS1 offtake (E16), and N-S cross-tie JT6 (E32, 8 km DN150). Pressure drop E3: 1.2 bar at peak demand." },
  JT3: { title: "JT3 — NE Ring Junction", color: "#475569",
    body: "North-east ring junction. Connects to storage injection valve E12 (->STO) and E-arm JT5 (E6, 8 km DN200). Feeds DRS3 spur (E18) and N-S cross-tie JT7 (E33, 8 km DN150). Highest-pressure node on E arm (23 barg nominal)." },
  JT4: { title: "JT4 — West Ring Junction", color: "#475569",
    body: "Western arm junction. Receives CGS2 secondary feed (E11, 6 km DN150). Feeds JT6 southward (E7) and CNG1 Akshardham (E22). Load-sharing point between CGS1 and CGS2. CGS2 valve opens when p_JT4 < 21 barg." },
  JT5: { title: "JT5 — East Ring Junction (GIDC Corridor)", color: "#475569",
    body: "Eastern ring junction serving the GIDC industrial corridor. Feeds CNG3 station (E24, 4 km DN100) and SE arm JT7 (E8, 7 km DN200). GIDC industrial demand peak: 80,000 SCMD. Pressure minimum 22 barg for CNG compression efficiency." },
  JT6: { title: "JT6 — SW Ring Junction", color: "#475569",
    body: "South-west ring junction. Feeds DRS4 (Sec 22-24, E19) and DRS7 (Sec 25-28, E21). Receives from JT4 (E7) and N-S cross-tie JT2 (E32). Low-pressure alarm at 20 barg triggers SCADA alert." },
  JT7: { title: "JT7 — SE Ring Junction", color: "#475569",
    body: "South-east ring junction feeding GIDC south industrial zone via DRS5 (E20). Connected to JT5 (E8), JT8 (E10), and N-S cross-tie JT3 (E33). DRS5 outlet held at 20 barg by PID for industrial priority supply." },
  JT8: { title: "JT8 — South Hub Junction (Ring Apex)", color: "#475569",
    body: "Southern ring apex. Receives from JT6 (E9) and JT7 (E10). Central branch from DRS6 (E15). Feeds CNG4 Gandhinagar South (E25). Ring balance node — typically 20 barg, 1-2 bar below north apex due to friction losses." },
  DRS1: { title: "DRS1 — Sectors 1-7 DRS (NW Zone)", color: "#c2410c",
    body: "District Regulating Station for Sectors 1-7 (Gandhinagar NW). Inlet 22-26 barg ring, outlet 14 barg MDPE. Capacity 30,000 SCMD. Dual-regulator (active+monitor), Joule-Thomson pre-heater, GPRS RTU. 22,000 PNG connections downstream." },
  DRS2: { title: "DRS2 — Sectors 8-14 DRS (North Zone)", color: "#c2410c",
    body: "DRS for north residential Sectors 8-14 including government housing. Outlet 16 barg (higher for commercial consumers). Feeds D2. 25,000 PNG connections. Mixed residential and commercial." },
  DRS3: { title: "DRS3 — Sectors 15-21 DRS (NE Zone)", color: "#c2410c",
    body: "DRS for north-east Sectors 15-21. Outlet 14 barg. Largest residential cluster in Gandhinagar east side. 18,000 PNG + 340 commercial. 28,000 SCMD daily. Emergency bypass valve." },
  DRS4: { title: "DRS4 — Sectors 22-24 DRS (SW Zone)", color: "#c2410c",
    body: "DRS for SW Sectors 22-24 (older residential near Sabarmati River). Outlet 14 barg. 12,000 PNG connections. Manual bypass valve. 18,000 SCMD daily." },
  DRS5: { title: "DRS5 — GIDC Industrial DRS (SE Zone)", color: "#c2410c",
    body: "High-flow DRS for GIDC Gandhinagar industrial estates (pharma, textile, chemical). Outlet 20 barg (industrial medium pressure). Capacity 120,000 SCMD. Coriolis mass flowmeter. Serves Cadila, Torrent, Sun Pharma plants." },
  DRS6: { title: "DRS6 — Central Gandhinagar DRS", color: "#c2410c",
    body: "Central district regulator on the N-S branch (E14-E15). Feeds CNG2 Sector 16 (E23) and Sachivalaya govt zone D6 (E31). Outlet 14 barg. Network pressure telemetry node — SCADA ring balance monitoring. Flow 40,000 SCMD." },
  DRS7: { title: "DRS7 — Sectors 25-28 DRS (South Zone)", color: "#c2410c",
    body: "South zone DRS for Sectors 25-28 near Gandhinagar-Ahmedabad boundary. Outlet 14 barg. Fastest-growing zone: 15,000 PNG connections, 400 new/month. Remote GPRS RTU. Feeds D5 (E30)." },
  CNG1: { title: "CNG1 — Akshardham Road CNG Station", color: "#0e7490",
    body: "CNG station on Akshardham Road. HP ring offtake from JT4 (22 barg inlet). Cascade compression to 250 barg cylinders (3-stage diaphragm, 5 SCMD/hr). 14 dispensers. 1,800 vehicles/day peak." },
  CNG2: { title: "CNG2 — Sector 16 CNG Station", color: "#0e7490",
    body: "Central city CNG station, Sector 16. Fed from DRS6 at 14 barg, boosted to 250 barg on-site. Busiest station in Gandhinagar GA: 2,400 vehicles/day, 20 dispensers. Serves BRTS buses." },
  CNG3: { title: "CNG3 — GIDC North CNG Station", color: "#0e7490",
    body: "CNG at GIDC north boundary. Direct HP ring offtake from JT5 (22 barg) for HCV compression. Capacity 5 SCMD/hr. 6 heavy-commercial-vehicle dispensers. Serves Gandhinagar industrial truck fleet." },
  CNG4: { title: "CNG4 — Gandhinagar South CNG", color: "#0e7490",
    body: "South Gandhinagar CNG near SH-8 junction. Fed from ring hub JT8 (20 barg). Serves commuter corridor to Ahmedabad. 12 dispensers, 24/7 operation. 1,400 vehicles/day average." },
  D1:  { title: "D1 — Sectors 1-7 Residential Zone", color: "#b91c1c",
    body: "NW residential demand via DRS1 (14 barg MDPE). 35,000 SCMD average. Seasonal peak factor 1.35 (winter). 22,000 PNG connections." },
  D2:  { title: "D2 — Sectors 8-14 Residential Zone", color: "#b91c1c",
    body: "North residential via DRS2 (16 barg). Govt employee housing + GNFC colony. 25,000 PNG connections. 32,000 SCMD average." },
  D3:  { title: "D3 — Sectors 15-21 Mixed Zone", color: "#b91c1c",
    body: "NE mixed-use via DRS3 — Gandhinagar commercial hub + IT Infocity. 18,000 PNG + 340 commercial. 28,000 SCMD. Highest commercial-to-residential ratio in GA." },
  D4:  { title: "D4 — Sectors 22-24 Residential", color: "#b91c1c",
    body: "SW older residential near Sabarmati riverbank via DRS4. 12,000 PNG connections. 18,000 SCMD daily." },
  D5:  { title: "D5 — Sectors 25-28 (Expansion Zone)", color: "#b91c1c",
    body: "Southern expansion sectors via DRS7. Fastest-growing zone: 15,000 PNG connections, 400 new/month. Greenfield PE100 MDPE distribution." },
  D6:  { title: "D6 — Sachivalaya Government Complex", color: "#b91c1c",
    body: "Gujarat state government complex via DRS6. High-priority uninterruptible supply. 5,000 SCMD. Secretariat, guest houses, canteens." },
  E12: { title: "Valve E12: JT3 -> STO (Injection)", color: "#1d4ed8",
    body: "Storage injection valve — opens when JT3 > 24 barg (surplus). Routes excess HP ring gas into Kalol cavern. Electro-pneumatic actuator, Modbus coil sto_inject_active. Max injection 50,000 SCMD." },
  E13: { title: "Valve E13: STO -> JT1 (Withdrawal)", color: "#1d4ed8",
    body: "Storage withdrawal valve — opens when JT1 < 20 barg (deficit). Bidirectional interlock: E12 and E13 cannot open simultaneously. Modbus coil sto_withdraw_active." },
};

function midpoint(a, b) { return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }; }

function dnToWidth(dn) {
  if (!dn) return 2.5;
  const map = { DN250: 4.0, DN200: 3.4, DN150: 2.5, DN100: 1.8, DN80: 1.3 };
  return map[dn] ?? 2.0;
}
function dnToColor(dn) {
  if (!dn) return "#94a3b8";
  if (dn === "DN250" || dn === "DN200") return "#64748b";
  if (dn === "DN150") return "#7c8fa8";
  return "#94a3b8";
}
function showLabel(dn) {
  return dn === "DN250" || dn === "DN200" || dn === "DN150";
}

function ValveSymbol({ from, to, id, selected, onClick }) {
  const mid = midpoint(from, to);
  const dx = to.x - from.x, dy = to.y - from.y;
  const deg = Math.atan2(dy, dx) * 180 / Math.PI;
  const isSel = selected === id;
  const col = isSel ? "#b45309" : "#1d4ed8";
  return (
    <g transform={`translate(${mid.x},${mid.y}) rotate(${deg})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <line x1={-30} y1={0} x2={30} y2={0} stroke={isSel ? "#b45309" : "#94a3b8"} strokeWidth={3.5} />
      <polygon points="-10,-8 10,-8 0,0" fill={col} opacity={0.9} />
      <polygon points="-10,8 10,8 0,0" fill={col} opacity={0.9} />
      <line x1={0} y1={-8} x2={0} y2={-16} stroke={col} strokeWidth={1.5} />
      <rect x={-5} y={-19} width={10} height={3} rx={1.5} fill={col} />
    </g>
  );
}

function CompressorSymbol({ node, id, selected, onClick }) {
  const isSel = selected === id;
  const col = isSel ? "#b45309" : "#6d28d9";
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <circle cx={0} cy={0} r={20}
        fill={isSel ? "rgba(180,83,9,0.12)" : "rgba(109,40,217,0.1)"}
        stroke={col} strokeWidth={2}
        style={{ filter: isSel ? `drop-shadow(0 0 6px ${col})` : "none", transition: "all 0.2s" }} />
      {[0,60,120,180,240,300].map(d => (
        <line key={d} x1={0} y1={0}
          x2={Math.cos(d*Math.PI/180)*14} y2={Math.sin(d*Math.PI/180)*14}
          stroke={col} strokeWidth={1.8} strokeLinecap="round" />
      ))}
      <circle cx={0} cy={0} r={3.5} fill={col} />
      <text x={0} y={-27} textAnchor="middle" fontSize={9} fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
    </g>
  );
}

function DRSSymbol({ node, id, selected, onClick }) {
  const isSel = selected === id;
  const col = isSel ? "#b45309" : "#c2410c";
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <rect x={-19} y={-13} width={38} height={26} rx={4}
        fill={isSel ? "rgba(180,83,9,0.12)" : "rgba(194,65,12,0.08)"}
        stroke={col} strokeWidth={1.8}
        style={{ filter: isSel ? `drop-shadow(0 0 5px ${col})` : "none", transition: "all 0.2s" }} />
      <polyline points="-12,-6 -3,-6 -3,6 12,6" fill="none" stroke={col} strokeWidth={1.6} strokeLinejoin="round" />
      <polygon points="10,3 14,6 10,9" fill={col} />
      <text x={0} y={-22} textAnchor="middle" fontSize={9} fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
      <text x={0} y={-12} textAnchor="middle" fontSize={7} fill={`${col}bb`} fontFamily="'Fira Code', monospace">{node.sub}</text>
    </g>
  );
}

function CNGSymbol({ node, id, selected, onClick }) {
  const isSel = selected === id;
  const col = isSel ? "#b45309" : "#0e7490";
  const pts = Array.from({ length: 6 }, (_, i) => {
    const a = (i * 60 - 30) * Math.PI / 180;
    return `${(15 * Math.cos(a)).toFixed(1)},${(15 * Math.sin(a)).toFixed(1)}`;
  }).join(" ");
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <polygon points={pts}
        fill={isSel ? "rgba(180,83,9,0.12)" : "rgba(14,116,144,0.08)"}
        stroke={col} strokeWidth={1.8}
        style={{ filter: isSel ? `drop-shadow(0 0 5px ${col})` : "none", transition: "all 0.2s" }} />
      <text x={0} y={2} textAnchor="middle" fontSize={6.5} fill={col} fontFamily="'Fira Code', monospace" fontWeight="800" style={{ pointerEvents: "none" }}>CNG</text>
      <text x={0} y={-24} textAnchor="middle" fontSize={9} fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
    </g>
  );
}

function StorageSymbol({ node, id, selected, onClick }) {
  const isSel = selected === id;
  const col = isSel ? "#b45309" : "#1d4ed8";
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <ellipse cx={0} cy={0} rx={20} ry={12}
        fill={isSel ? "rgba(180,83,9,0.12)" : "rgba(29,78,216,0.08)"}
        stroke={col} strokeWidth={2}
        style={{ filter: isSel ? `drop-shadow(0 0 5px ${col})` : "none", transition: "all 0.2s" }} />
      <rect x={-20} y={-12} width={40} height={18} fill={isSel ? "rgba(180,83,9,0.06)" : "rgba(29,78,216,0.05)"} stroke="none" />
      <ellipse cx={0} cy={6} rx={20} ry={12} fill="none" stroke={col} strokeWidth={2} />
      <text x={0} y={-20} textAnchor="middle" fontSize={9} fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
    </g>
  );
}

function NodeCircle({ node, id, selected, onClick }) {
  const isSel = selected === id;
  const isSource = node.type === "source";
  const isDemand = node.type === "demand";
  const col = isSource ? "#15803d" : isDemand ? "#b91c1c" : "#475569";
  const fillCol = isSel
    ? (isSource ? "rgba(21,128,61,0.15)" : isDemand ? "rgba(185,28,28,0.15)" : "rgba(71,85,105,0.15)")
    : (isSource ? "rgba(21,128,61,0.08)" : isDemand ? "rgba(185,28,28,0.08)" : "rgba(71,85,105,0.08)");
  const r = isDemand ? 11 : isSource ? 13 : 9;
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <circle cx={0} cy={0} r={r} fill={fillCol}
        stroke={isSel ? "#b45309" : col} strokeWidth={isSel ? 2.5 : 1.5}
        style={{ filter: isSel ? "drop-shadow(0 0 5px #b45309)" : "none", transition: "all 0.2s" }} />
      {isSource && (<><line x1={-5} y1={0} x2={5} y2={0} stroke={col} strokeWidth={1.8} /><line x1={0} y1={-5} x2={0} y2={5} stroke={col} strokeWidth={1.8} /></>)}
      {isDemand && <polygon points="0,-6 5,3 -5,3" fill={col} opacity={0.8} />}
      <text x={0} y={r + 13} textAnchor="middle" fontSize={10} fontWeight="800"
        fill={isSel ? "#b45309" : col} fontFamily="'Fira Code', monospace" style={{ pointerEvents: "none" }}>
        {node.label}
      </text>
    </g>
  );
}

export default function App() {
  const [selected, setSelected] = useState(null);
  const sel = (id) => () => setSelected(prev => prev === id ? null : id);
  const info = selected ? (INFO[selected] || null) : null;
  const specialTypes = new Set(["compressor","drs","cng","storage"]);
  const regularNodes = Object.entries(NODES).filter(([,n]) => !specialTypes.has(n.type));
  const pipes  = EDGES.filter(e => e.type === "pipe");
  const valves = EDGES.filter(e => e.type === "valve");

  return (
    <div style={{ minHeight: "100vh", background: "#f8fafc", fontFamily: "'Inter', sans-serif", color: "#1e293b", display: "flex", flexDirection: "column" }}>
      <div style={{ padding: "16px 24px 14px", display: "flex", alignItems: "center", justifyContent: "space-between", borderBottom: "1px solid #e2e8f0" }}>
        <div>
          <div style={{ fontSize: 10, color: "#c2410c", fontFamily: "'Fira Code', monospace", letterSpacing: 3, textTransform: "uppercase" }}>
            v2 · Realistic City Network · Gandhinagar GA
          </div>
          <h1 style={{ margin: "3px 0 0", fontSize: 18, fontWeight: 800, color: "#0f172a", letterSpacing: -0.5 }}>
            29-Node SGL/GSPL Pipeline · Sabarmati Gas Limited
          </h1>
          <div style={{ fontSize: 10, color: "#64748b", marginTop: 2 }}>
            PNGRB T4S · 26 barg MAOP · IS 3589 / API 5L Gr.B · Ref: Springer doi:10.1007/s42452-019-0755-2
          </div>
        </div>
        <div style={{ display: "flex", gap: 14, fontSize: 10, color: "#64748b", flexWrap: "wrap", maxWidth: 500 }}>
          {[
            ["●","#15803d","Source / CGS (2)"], ["●","#475569","Junction (8)"],   ["▲","#b91c1c","Demand Zone (6)"],
            ["◎","#6d28d9","Compressor (1)"],   ["▬","#c2410c","DRS Station (7)"],["⬡","#0e7490","CNG Station (4)"],
            ["⌀","#1d4ed8","Storage (1)"],      ["⋈","#1d4ed8","Valve (2)"],
          ].map(([sym,col,lbl]) => (
            <div key={lbl} style={{ display: "flex", alignItems: "center", gap: 4 }}>
              <span style={{ color: col, fontSize: 12 }}>{sym}</span><span>{lbl}</span>
            </div>
          ))}
        </div>
      </div>

      <div style={{ display: "flex", flex: 1, padding: "12px 16px 16px", gap: 14, minHeight: 520 }}>
        <div style={{ flex: 1, background: "#fff", border: "1px solid #e2e8f0", borderRadius: 12, overflow: "hidden", position: "relative", boxShadow: "0 1px 4px rgba(0,0,0,0.06)" }}>
          <svg width="100%" height="100%" style={{ position: "absolute", top: 0, left: 0, pointerEvents: "none" }}>
            <defs>
              <pattern id="gridv2" width="40" height="40" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 40" fill="none" stroke="rgba(0,0,0,0.03)" strokeWidth="1" />
              </pattern>
            </defs>
            <rect width="100%" height="100%" fill="url(#gridv2)" />
          </svg>

          <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="100%" style={{ position: "relative", zIndex: 1 }}>

            {/* Organic region labels — no bounding boxes, just text like v1 */}
            <text x={240} y={300} textAnchor="middle" fontSize={8.5} fill="#94a3b8" fontFamily="sans-serif">west arm</text>
            <text x={945} y={315} textAnchor="middle" fontSize={8.5} fill="#94a3b8" fontFamily="sans-serif">east arm · GIDC</text>
            <text x={524} y={275} textAnchor="middle" fontSize={8.5} fill="#94a3b8" fontFamily="sans-serif">central spur  E14/E15</text>
            <text x={830} y={125} textAnchor="middle" fontSize={8.5} fill="#94a3b8" fontFamily="sans-serif">storage loop</text>
            <text x={514} y={72}  textAnchor="middle" fontSize={8.5} fill="#94a3b8" fontFamily="sans-serif">Kalol trunk</text>

            {/* Pipes — thickness and colour reflect DN size */}
            {pipes.map(e => {
              const a = NODES[e.from], b = NODES[e.to];
              if (!a || !b) return null;
              const isSel = selected === e.id;
              const w  = isSel ? dnToWidth(e.dn) + 1.5 : dnToWidth(e.dn);
              const sc = isSel ? "#b45309" : dnToColor(e.dn);
              const mx = (a.x + b.x) / 2;
              const my = (a.y + b.y) / 2;
              const offX = Math.abs(a.y - b.y) > 30 ? 10 : 0;
              const offY = Math.abs(a.y - b.y) > 30 ?  0 : -9;
              return (
                <g key={e.id}>
                  {isSel && <line x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="#b45309" strokeWidth={w+6} opacity={0.08} strokeLinecap="round" />}
                  <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke={sc} strokeWidth={w} strokeLinecap="round"
                    style={{ cursor: "pointer", transition: "stroke 0.2s" }}
                    onClick={sel(e.id)} />
                  {(isSel || showLabel(e.dn)) && (
                    <text x={mx + offX} y={my + offY} textAnchor="middle" fontSize={7.5}
                      fill={isSel ? "#b45309" : "#b0bec5"}
                      fontFamily="'Fira Code', monospace" style={{ pointerEvents: "none" }}>{e.id}</text>
                  )}
                </g>
              );
            })}

            {/* Valve edges */}
            {valves.map(e => {
              const a = NODES[e.from], b = NODES[e.to];
              if (!a || !b) return null;
              const isSel = selected === e.id;
              return (
                <g key={e.id}>
                  {isSel && <line x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="#b45309" strokeWidth={9} opacity={0.08} strokeLinecap="round" />}
                  <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke={isSel ? "#b45309" : "#7c8fa8"}
                    strokeWidth={2.8} strokeLinecap="round" strokeDasharray="6 3"
                    style={{ cursor: "pointer" }} onClick={sel(e.id)} />
                  <ValveSymbol from={a} to={b} id={e.id} selected={selected} onClick={sel(e.id)} />
                  <text x={(a.x+b.x)/2+14} y={(a.y+b.y)/2}
                    textAnchor="middle" fontSize={8}
                    fill={isSel ? "#b45309" : "#1d4ed8"}
                    fontFamily="'Fira Code', monospace"
                    style={{ pointerEvents: "none" }}>{e.id}</text>
                </g>
              );
            })}

            {/* Special equipment */}
            <CompressorSymbol node={NODES.CS1} id="CS1" selected={selected} onClick={sel("CS1")} />
            <StorageSymbol    node={NODES.STO} id="STO" selected={selected} onClick={sel("STO")} />
            {Object.entries(NODES).filter(([,n]) => n.type === "drs").map(([id,n]) => (
              <DRSSymbol key={id} node={n} id={id} selected={selected} onClick={sel(id)} />
            ))}
            {Object.entries(NODES).filter(([,n]) => n.type === "cng").map(([id,n]) => (
              <CNGSymbol key={id} node={n} id={id} selected={selected} onClick={sel(id)} />
            ))}

            {/* Regular nodes */}
            {regularNodes.map(([id, node]) => (
              <NodeCircle key={id} node={node} id={id} selected={selected} onClick={sel(id)} />
            ))}

            {/* Pressure labels */}
            {Object.entries(NOMINAL_PRESSURES).map(([id, val]) => {
              const n = NODES[id];
              if (!n) return null;
              const isSp = specialTypes.has(n.type);
              const yOff = isSp ? 22 : n.type === "demand" ? -4 : 22;
              return (
                <text key={`p-${id}`} x={n.x} y={n.y + yOff}
                  textAnchor="middle" fontSize={7.5} fill="#94a3b8"
                  fontFamily="'Fira Code', monospace" style={{ pointerEvents: "none" }}>{val}</text>
              );
            })}

            {/* SCADA RTU indicator dots */}
            {["JT1","JT4","JT5","JT8","DRS5","DRS6"].map(id => {
              const n = NODES[id];
              if (!n) return null;
              return (
                <circle key={`rtu-${id}`} cx={n.x+14} cy={n.y-14} r={3.5}
                  fill="rgba(194,65,12,0.4)" stroke="#c2410c" strokeWidth={0.8}
                  style={{ pointerEvents: "none" }} />
              );
            })}
            <text x={572} y={145} fontSize={7.5} fill="#c2410c" fontFamily="'Fira Code', monospace" style={{ pointerEvents: "none" }}>● SCADA RTU</text>
          </svg>
        </div>

        {/* Info panel */}
        <div style={{ width: 278, background: "#fff", border: "1px solid #e2e8f0", borderRadius: 12, padding: 16, display: "flex", flexDirection: "column", boxShadow: "0 1px 4px rgba(0,0,0,0.06)" }}>
          {info ? (
            <>
              <div style={{ width: 3, height: 18, background: info.color, borderRadius: 2, marginBottom: 10 }} />
              <div style={{ color: info.color, fontFamily: "'Fira Code', monospace", fontSize: 11, fontWeight: 800, marginBottom: 8, lineHeight: 1.4 }}>{info.title}</div>
              <div style={{ color: "#475569", fontSize: 11, lineHeight: 1.7 }}>{info.body}</div>
            </>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: 9, flex: 1 }}>
              <div style={{ color: "#94a3b8", fontSize: 9, fontFamily: "'Fira Code', monospace", letterSpacing: 1 }}>CLICK NODE / EDGE TO INSPECT</div>
              {[
                ["City",         "Gandhinagar, Gujarat",    "#c2410c"],
                ["Operator",     "Sabarmati Gas Ltd (SGL)", "#c2410c"],
                ["Backbone",     "GSPL 18\" HT-2 pipeline", "#0369a1"],
                ["Nodes",        "29  (ring topology)",     "#15803d"],
                ["Edges",        "33 pipes + 2 valves",     "#0369a1"],
                ["HP Ring",      "22-26 barg  API 5L Gr.B", "#b45309"],
                ["DRS stations", "7  (14-20 barg outlet)",  "#c2410c"],
                ["CNG stations", "4  (250 barg cascade)",   "#0e7490"],
                ["Demand zones", "6  (14-16 barg MDPE)",    "#b91c1c"],
                ["Coverage",     "~649 km²  city area",     "#475569"],
                ["Gas supply",   "ONGC/GAIL, SG 0.62",      "#475569"],
                ["SCADA RTU",    "6 nodes  GPRS telemetry", "#c2410c"],
              ].map(([lbl, val, col]) => (
                <div key={lbl} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", borderBottom: "1px solid #f8fafc", paddingBottom: 4 }}>
                  <span style={{ color: "#64748b", fontSize: 10 }}>{lbl}</span>
                  <span style={{ color: col, fontFamily: "'Fira Code', monospace", fontSize: 10, fontWeight: 700 }}>{val}</span>
                </div>
              ))}
              <div style={{ marginTop: "auto", borderTop: "1px solid #f1f5f9", paddingTop: 10 }}>
                <div style={{ color: "#94a3b8", fontSize: 9, fontFamily: "'Fira Code', monospace", letterSpacing: 1, marginBottom: 6 }}>PIPE PARAMS (ring main)</div>
                {[
                  ["DN250 (main)", "9.53 mm wall   4.0 px"],
                  ["DN200 (ring)", "7.92 mm wall   3.4 px"],
                  ["DN150 (spur)", "5.74 mm wall   2.5 px"],
                  ["DN80-100",     "dist spurs      1.5 px"],
                  ["Material",     "API 5L Gr.B / IS 3589"],
                  ["MAOP",         "26 barg (PNGRB T4S)"],
                ].map(([k,v]) => (
                  <div key={k} style={{ display: "flex", justifyContent: "space-between", marginBottom: 3 }}>
                    <span style={{ color: "#94a3b8", fontSize: 9 }}>{k}</span>
                    <span style={{ color: "#0369a1", fontFamily: "'Fira Code', monospace", fontSize: 9 }}>{v}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      <div style={{ textAlign: "center", paddingBottom: 8, color: "#94a3b8", fontSize: 10, fontFamily: "'Fira Code', monospace" }}>
        29 nodes · 35 edges · HP ring · DRS cascade 26→14 barg · pipe width ∝ DN · Ref: doi:10.1007/s42452-019-0755-2
      </div>
    </div>
  );
}
