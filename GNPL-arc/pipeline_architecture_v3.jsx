import { useState } from "react";

const W = 1340, H = 590;

// IGL South-West Delhi Zone: Rajokri CGS → Dwarka (Sec 1-23) → Palam → Mahipalpur → Aerocity/IGI
// 36 nodes: 2 CGS + 2 CS + 1 BUF + 10 JT + 8 DRS + 6 CNG + 7 D
// Ladder ring topology — N rail (y=200) + S rail (y=385) + 5 vertical rungs
// Reference: IGL Annual Reports, PNGRB T4S, iglonline.net/igl-pipeline-network

const NODES = {
  // --- SOURCES (CGS) ---
  CGS_RAJ: { x: 1215, y: 55,  type: "source",     label: "CGS·RAJ", sub: "Rajokri GAIL",  idx: 1  },
  CGS_DWK: { x: 110,  y: 55,  type: "source",      label: "CGS·DWK", sub: "Dwarka GAIL",   idx: 2  },
  // --- COMPRESSORS ---
  CS1:     { x: 1215, y: 138, type: "compressor",  label: "CS1",     sub: "Rajokri Bstr",  idx: 3  },
  CS2:     { x: 110,  y: 138, type: "compressor",  label: "CS2",     sub: "Dwarka Bstr",   idx: 4  },
  // --- HP BUFFER ---
  BUF:     { x: 720,  y: 62,  type: "storage",     label: "BUF",     sub: "HP Linepack",   idx: 5  },
  // --- HP RING JUNCTIONS (N rail, y=200) ---
  JT1:     { x: 1095, y: 200, type: "junction",    label: "JT1",     sub: "Rajokri E",     idx: 6  },
  JT2:     { x: 875,  y: 200, type: "junction",    label: "JT2",     sub: "Mahipalpur N",  idx: 7  },
  JT3:     { x: 665,  y: 200, type: "junction",    label: "JT3",     sub: "Central N",     idx: 8  },
  JT4:     { x: 455,  y: 200, type: "junction",    label: "JT4",     sub: "Dwarka Central",idx: 9  },
  JT5:     { x: 245,  y: 200, type: "junction",    label: "JT5",     sub: "Dwarka NW",     idx: 10 },
  // --- HP RING JUNCTIONS (S rail, y=385) ---
  JT6:     { x: 245,  y: 385, type: "junction",    label: "JT6",     sub: "Dwarka SW",     idx: 11 },
  JT7:     { x: 455,  y: 385, type: "junction",    label: "JT7",     sub: "Palam W",       idx: 12 },
  JT8:     { x: 665,  y: 385, type: "junction",    label: "JT8",     sub: "Palam Central", idx: 13 },
  JT9:     { x: 875,  y: 385, type: "junction",    label: "JT9",     sub: "Mahipalpur S",  idx: 14 },
  JT10:    { x: 1095, y: 385, type: "junction",    label: "JT10",    sub: "Aerocity/IGI",  idx: 15 },
  // --- DRS STATIONS ---
  DRS1:    { x: 110,  y: 295, type: "drs",         label: "DRS1",    sub: "4 barg",        idx: 16 },
  DRS2:    { x: 375,  y: 128, type: "drs",         label: "DRS2",    sub: "4 barg",        idx: 17 },
  DRS3:    { x: 580,  y: 128, type: "drs",         label: "DRS3",    sub: "4 barg",        idx: 18 },
  DRS4:    { x: 990,  y: 128, type: "drs",         label: "DRS4",    sub: "4 barg",        idx: 19 },
  DRS5:    { x: 375,  y: 460, type: "drs",         label: "DRS5",    sub: "4 barg",        idx: 20 },
  DRS6:    { x: 665,  y: 460, type: "drs",         label: "DRS6",    sub: "4 barg",        idx: 21 },
  DRS7:    { x: 1260, y: 385, type: "drs",         label: "DRS7",    sub: "4 barg",        idx: 22 },
  DRS8:    { x: 990,  y: 460, type: "drs",         label: "DRS8",    sub: "4 barg",        idx: 23 },
  // --- CNG STATIONS ---
  CNG1:    { x: 245,  y: 470, type: "cng",         label: "CNG1",    sub: "Dwarka Sec 4",  idx: 24 },
  CNG2:    { x: 455,  y: 295, type: "cng",         label: "CNG2",    sub: "Dwarka Sec 10", idx: 25 },
  CNG3:    { x: 875,  y: 295, type: "cng",         label: "CNG3",    sub: "Mahipalpur",    idx: 26 },
  CNG4:    { x: 665,  y: 295, type: "cng",         label: "CNG4",    sub: "Palam Airport", idx: 27 },
  CNG5:    { x: 590,  y: 460, type: "cng",         label: "CNG5",    sub: "IGI Airport",   idx: 28 },
  CNG6:    { x: 1175, y: 460, type: "cng",         label: "CNG6",    sub: "Aerocity",      idx: 29 },
  // --- DEMAND ZONES ---
  D1:      { x: 58,   y: 200, type: "demand",      label: "D1",      sub: "Dw Sec 1-4",   idx: 30 },
  D2:      { x: 58,   y: 385, type: "demand",      label: "D2",      sub: "Dw Sec 5-8",   idx: 31 },
  D3:      { x: 310,  y: 200, type: "demand",      label: "D3",      sub: "Dw Sec 9-13",  idx: 32 },
  D4:      { x: 375,  y: 535, type: "demand",      label: "D4",      sub: "Dw Sec 20-23", idx: 33 },
  D5:      { x: 665,  y: 535, type: "demand",      label: "D5",      sub: "Palam Resid.",  idx: 34 },
  D6:      { x: 1260, y: 460, type: "demand",      label: "D6",      sub: "Kapashera Ind.",idx: 35 },
  D7:      { x: 1260, y: 200, type: "demand",      label: "D7",      sub: "IGI Cargo",     idx: 36 },
};

const EDGES = [
  // Source feeds
  { id: "E1",  from: "CGS_RAJ", to: "CS1",  type: "pipe"  },
  { id: "E2",  from: "CS1",     to: "JT1",  type: "pipe"  },
  { id: "E3",  from: "CGS_DWK", to: "CS2",  type: "pipe"  },
  { id: "E4",  from: "CS2",     to: "JT5",  type: "pipe"  },
  // Buffer vessel (HP line pack, bidirectional valve)
  { id: "E5",  from: "JT3",  to: "BUF",  type: "valve" },
  { id: "E6",  from: "BUF",  to: "JT2",  type: "valve" },
  // North rail (E7-E10)
  { id: "E7",  from: "JT1",  to: "JT2",  type: "pipe",  len: "7 km",  dn: "DN250" },
  { id: "E8",  from: "JT2",  to: "JT3",  type: "pipe",  len: "7 km",  dn: "DN250" },
  { id: "E9",  from: "JT3",  to: "JT4",  type: "pipe",  len: "7 km",  dn: "DN200" },
  { id: "E10", from: "JT4",  to: "JT5",  type: "pipe",  len: "7 km",  dn: "DN200" },
  // South rail (E11-E14)
  { id: "E11", from: "JT6",  to: "JT7",  type: "pipe",  len: "7 km",  dn: "DN200" },
  { id: "E12", from: "JT7",  to: "JT8",  type: "pipe",  len: "7 km",  dn: "DN200" },
  { id: "E13", from: "JT8",  to: "JT9",  type: "pipe",  len: "7 km",  dn: "DN200" },
  { id: "E14", from: "JT9",  to: "JT10", type: "pipe",  len: "7 km",  dn: "DN200" },
  // Vertical rungs (E15-E19)
  { id: "E15", from: "JT5",  to: "JT6",  type: "pipe",  len: "6 km",  dn: "DN200" },
  { id: "E16", from: "JT4",  to: "JT7",  type: "pipe",  len: "6 km",  dn: "DN200" },
  { id: "E17", from: "JT3",  to: "JT8",  type: "pipe",  len: "6 km",  dn: "DN200" },
  { id: "E18", from: "JT2",  to: "JT9",  type: "pipe",  len: "6 km",  dn: "DN150" },
  { id: "E19", from: "JT1",  to: "JT10", type: "pipe",  len: "6 km",  dn: "DN150" },
  // DRS offtakes (E20-E27)
  { id: "E20", from: "JT5",  to: "DRS1", type: "pipe",  len: "4 km",  dn: "DN100" },
  { id: "E21", from: "JT4",  to: "DRS2", type: "pipe",  len: "3 km",  dn: "DN100" },
  { id: "E22", from: "JT3",  to: "DRS3", type: "pipe",  len: "3 km",  dn: "DN100" },
  { id: "E23", from: "JT2",  to: "DRS4", type: "pipe",  len: "4 km",  dn: "DN100" },
  { id: "E24", from: "JT7",  to: "DRS5", type: "pipe",  len: "3 km",  dn: "DN100" },
  { id: "E25", from: "JT8",  to: "DRS6", type: "pipe",  len: "3 km",  dn: "DN100" },
  { id: "E26", from: "JT10", to: "DRS7", type: "pipe",  len: "4 km",  dn: "DN100" },
  { id: "E27", from: "JT9",  to: "DRS8", type: "pipe",  len: "3 km",  dn: "DN100" },
  // CNG taps — direct HP ring feed (E28-E33)
  { id: "E28", from: "JT6",  to: "CNG1", type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E29", from: "JT4",  to: "CNG2", type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E30", from: "JT2",  to: "CNG3", type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E31", from: "JT3",  to: "CNG4", type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E32", from: "JT8",  to: "CNG5", type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E33", from: "JT10", to: "CNG6", type: "pipe",  len: "4 km",  dn: "DN80"  },
  // Demand zones (E34-E40)
  { id: "E34", from: "DRS1", to: "D1",   type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E35", from: "DRS1", to: "D2",   type: "pipe",  len: "4 km",  dn: "DN80"  },
  { id: "E36", from: "DRS2", to: "D3",   type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E37", from: "DRS5", to: "D4",   type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E38", from: "DRS6", to: "D5",   type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E39", from: "DRS7", to: "D6",   type: "pipe",  len: "3 km",  dn: "DN80"  },
  { id: "E40", from: "DRS4", to: "D7",   type: "pipe",  len: "4 km",  dn: "DN80"  },
];

const NOMINAL_PRESSURES = {
  CGS_RAJ:"19 bar", CGS_DWK:"19 bar", CS1:"19 bar", CS2:"19 bar", BUF:"18 bar",
  JT1:"18 bar", JT2:"18 bar", JT3:"17 bar", JT4:"17 bar", JT5:"17 bar",
  JT6:"16 bar", JT7:"16 bar", JT8:"16 bar", JT9:"16 bar", JT10:"15 bar",
  DRS1:"4 bar",  DRS2:"4 bar",  DRS3:"4 bar",  DRS4:"4 bar",
  DRS5:"4 bar",  DRS6:"4 bar",  DRS7:"4 bar",  DRS8:"4 bar",
  CNG1:"17 bar", CNG2:"17 bar", CNG3:"18 bar", CNG4:"17 bar", CNG5:"16 bar", CNG6:"15 bar",
  D1:"4 bar",  D2:"4 bar",  D3:"4 bar",  D4:"4 bar",
  D5:"4 bar",  D6:"4 bar",  D7:"4 bar",
};

const INFO = {
  CGS_RAJ: { title: "CGS·RAJ — Rajokri City Gate Station", color: "#15803d",
    body: "Primary IGL City Gate Station at Rajokri village, fed from GAIL HVJ (Hazira-Vijaipur-Jagdishpur) 30\" pipeline. IGL's largest CGS feeding South-West Delhi. Inlet: 50+ barg, outlet: 19 barg (IGL steel ring MAOP). Equipment: ultrasonic metering (Daniel 3410), GC, custody transfer fiscal metering, slam-shut at 21 barg. Capacity: 1.2 MMSCMD. Real location: ~800 m west of NH-48 / Rajokri flyover." },
  CGS_DWK: { title: "CGS·DWK — Dwarka City Gate Station", color: "#15803d",
    body: "Secondary CGS at Dwarka Expressway boundary feeding the western Dwarka sector loop. Reduces GAIL pipeline pressure to 19 barg for IGL steel ring. Provides N-W zone redundancy — IGL operates with N-1 CGS security standard. Feeds Dwarka NW junction JT5 via CS2 booster." },
  CS1: { title: "CS1 — Rajokri Booster Station", color: "#6d28d9",
    body: "Compressor station at Rajokri CGS outlet. Maintains ring N-E rail (JT1) at 18–19 barg against demand pressure drops. Motor: 400 kW. Reciprocating 2-stage. Bypass line: opens when CGS_RAJ outlet ≥ 18 barg. PID setpoint: p_JT1 = 18 barg." },
  CS2: { title: "CS2 — Dwarka Booster Station", color: "#6d28d9",
    body: "Booster at Dwarka CGS outlet. Maintains NW ring pressure (JT5) at 17 barg. Motor: 250 kW. Activated during peak morning demand (07:00–10:00) when Dwarka domestic cooking load spikes. PLC_A controls CS2 — same PLC as NW zone DRS." },
  BUF: { title: "BUF — HP Line Pack Buffer Vessel", color: "#1d4ed8",
    body: "High-pressure buffer vessel at central ring N rail (connected JT3↔JT2). Acts as hourly line-pack storage — absorbs demand transients without pressure swings. Volume: 300 m³ vessel at 18 barg. No underground cavern in urban Delhi — above-ground vessel is standard IGL practice. Valve E5: fill from JT3; Valve E6: discharge to JT2." },
  JT1: { title: "JT1 — Rajokri East Ring Junction", color: "#475569",
    body: "Entry junction from CS1 (Rajokri booster) into the HP steel ring. Distributes east-to-west along N rail (E7) and S-ward via rung E19 to JT10 (Aerocity). 19 barg nominal. Highest-pressure node in the network. IGL's priority supply point for Mahipalpur and Aerocity zones." },
  JT2: { title: "JT2 — Mahipalpur North Junction", color: "#475569",
    body: "Mahipalpur-north junction on N rail. Connected to DRS4 (E23, Mahipalpur N DRS), CNG3 (E30, Mahipalpur CNG), and BUF withdrawal valve E6. Feeds central rung JT9 (E18) to S rail. Pressure: 18 barg nominal. Also provides feed to D7 via DRS4." },
  JT3: { title: "JT3 — Central North Junction", color: "#475569",
    body: "Central junction on N rail feeding DRS3 (Dwarka Sec 13-17) and CNG4 (Palam Airport CNG). Buffer fill valve E5 branches here. Connects N rail bidirectionally (JT2↔JT4). Rung E17→JT8 carries bulk Palam zone flow. 17 barg nominal under peak demand." },
  JT4: { title: "JT4 — Dwarka Central Junction", color: "#475569",
    body: "Central Dwarka N-rail junction. Feeds DRS2 (Sec 7-12), CNG2 (Dwarka Sec 10 CNG), and rung JT7 (E16). High demand node — Dwarka is Delhi's largest planned township (50+ sectors, 2M+ residents). PLC_A monitors JT4 for Dwarka zone pressure control." },
  JT5: { title: "JT5 — Dwarka NW Junction", color: "#475569",
    body: "Westernmost junction (Dwarka NW, entry from CS2). Feeds DRS1 (E20, Dwarka Sec 1-6 DRS) and rung E15→JT6. N-rail terminus — flow from CS2 (Dwarka booster) and bidirectional from JT4. Pressure: 17 barg nominal, 16 barg min under peak demand." },
  JT6: { title: "JT6 — Dwarka SW Ring Junction", color: "#475569",
    body: "SW-rail junction. Entry point for CNG1 (Dwarka Sec 4 CNG station, E28). Feeds south-bound E11 toward Palam zone. Rung from JT5 (E15). Pressure: 16 barg. IGL sectionalizing valve on E15 allows SW Dwarka isolation for maintenance." },
  JT7: { title: "JT7 — Palam West Junction", color: "#475569",
    body: "Palam-west junction on S rail. Feeds DRS5 (Dwarka Sec 18-23 DRS, E24). Receives flow from JT6 (E11) and cross-rung JT4 (E16). 16 barg nominal. Palam residential demand peak: 08:00–10:00 cooking hour." },
  JT8: { title: "JT8 — Palam Central Junction", color: "#475569",
    body: "Central Palam junction. Feeds DRS6 (Palam S DRS, E25) and CNG5 (IGI Airport CNG, E32). Cross-rung from JT3 (E17). S-rail bidirectional: flow from JT7 and back-feed from JT9. Key node for airport supply security." },
  JT9: { title: "JT9 — Mahipalpur South Junction", color: "#475569",
    body: "Mahipalpur south junction. Feeds DRS8 (Kapashera DRS, E27) and receives cross-rung flow from JT2 (E18). S-rail eastbound to Aerocity (E14→JT10). 16 barg nominal. Kapashera industrial cluster demand: 40,000 SCMD peak." },
  JT10: { title: "JT10 — Aerocity / IGI Junction", color: "#475569",
    body: "Easternmost S-rail junction, Aerocity and IGI Airport perimeter. Feeds DRS7 (Aerocity commercial, E26) and CNG6 (Aerocity CNG, E33). Receives from JT9 (E14) and rung from JT1 (E19). 15 barg nominal — lowest ring pressure (friction losses from both Rajokri and Dwarka feeds). Emergency feed from JT1 rung maintains minimum 14 barg." },
  DRS1: { title: "DRS1 — Dwarka Sectors 1-6 DRS", color: "#c2410c",
    body: "District Regulating Station serving Dwarka Sectors 1-6 (West zone). Inlet: 17 barg HP ring (JT5), outlet: 4 barg medium pressure MDPE network. Capacity: 60,000 SCMD. 30,000 PNG domestic connections. Also feeds D1 and D2 residential zones. IGL standard DRS: slam-shut ±10% setpoint, pilot-operated regulator, SSV and ESD." },
  DRS2: { title: "DRS2 — Dwarka Sectors 7-12 DRS", color: "#c2410c",
    body: "DRS for Dwarka Sectors 7-12 (Central). Outlet: 4 barg. Feeds D3 residential zone. 25,000 PNG connections. Located near Dwarka Sector 10 metro station. High commercial demand: malls, hospitals." },
  DRS3: { title: "DRS3 — Dwarka Sectors 13-17 DRS", color: "#c2410c",
    body: "DRS for Dwarka Sectors 13-17 (South-Central). Outlet: 4 barg. Feeds Sec 13-17 residential and Dwarka sub-city commercial zones. 22,000 PNG connections. 35,000 SCMD average daily." },
  DRS4: { title: "DRS4 — Mahipalpur North DRS", color: "#c2410c",
    body: "DRS for Mahipalpur north area including hotel cluster along NH-48. Outlet: 4 barg. Feeds D7 (IGI cargo, hotel strip). High commercial fraction: Radisson, Crowne Plaza, Centaur — all on PNG. Demand: 15,000 SCMD." },
  DRS5: { title: "DRS5 — Dwarka Sectors 18-23 DRS", color: "#c2410c",
    body: "DRS for south Dwarka Sectors 18-23. Outlet: 4 barg. Feeds D4 zone. 18,000 PNG connections in newer sectors. High apartment-complex concentration — IGL installed bulk metering systems here. 28,000 SCMD." },
  DRS6: { title: "DRS6 — Palam South DRS", color: "#c2410c",
    body: "DRS for Palam village and Palam south residential. Outlet: 4 barg. Feeds D5 zone and IGI Airport perimeter services. 12,000 PNG connections. Also serves Palam dairy and food-processing units. 20,000 SCMD." },
  DRS7: { title: "DRS7 — Aerocity Commercial DRS", color: "#c2410c",
    body: "DRS for Delhi Aerocity commercial development (hotels, offices, retail). Outlet: 4 barg. Feeds D6 Kapashera. High-value commercial supply: JW Marriott, Novotel, Pullman — uninterruptible supply class. 10,000 SCMD, high seasonal variation with airport traffic." },
  DRS8: { title: "DRS8 — Kapashera Industrial DRS", color: "#c2410c",
    body: "DRS for Kapashera industrial area (electronics assembly, warehousing). Outlet: 4 barg. Connected from JT9. 40,000 SCMD industrial demand. Auto-ESD at 5.5 barg (over-pressure) and 3.5 barg (under-pressure). Coriolis meter for large-industrial billing." },
  CNG1: { title: "CNG1 — Dwarka Sector 4 CNG Station", color: "#0e7490",
    body: "IGL CNG station, Dwarka Sector 4 (at Sector 4-Sector 5 boundary). Direct HP ring offtake from JT6 (16 barg). 24 dispensers, 2,200 vehicles/day. Also serves Delhi Metro feeder buses (Route 763, 764). 5 SCMD/hr capacity." },
  CNG2: { title: "CNG2 — Dwarka Sector 10 CNG Station", color: "#0e7490",
    body: "Busy IGL CNG station near Dwarka Sector 10 metro station. HP ring offtake from JT4 (17 barg). Peak hour: 1,000 vehicles in morning rush. 20 dispensers. IGL's telemetry-equipped 'smart CNG' station with online pressure reporting to SCADA." },
  CNG3: { title: "CNG3 — Mahipalpur CNG Station", color: "#0e7490",
    body: "Mahipalpur CNG station serving NH-48 taxi/cab fleet (Uber/Ola aggregator partners). HP ring offtake from JT2 (18 barg) — highest CNG inlet pressure in zone. 3,000 vehicles/day. 24 dispensers, 24/7." },
  CNG4: { title: "CNG4 — Palam Airport Road CNG", color: "#0e7490",
    body: "CNG station on Palam airport road. HP ring offtake from JT3 (17 barg). Primarily serves airport taxi fleet and DIMTS buses. 1,800 vehicles/day. Critical supply point for Delhi airport connectivity corridor." },
  CNG5: { title: "CNG5 — IGI Airport Internal CNG", color: "#0e7490",
    body: "CNG station inside IGI Airport perimeter (Terminal 3 logistics area). Serves airside GSE (ground support equipment) CNG vehicles, GMR fleet buses. HP ring offtake from JT8 (16 barg). Restricted access. 800 vehicles/day." },
  CNG6: { title: "CNG6 — Aerocity CNG Station", color: "#0e7490",
    body: "IGL CNG station at Delhi Aerocity hospitality cluster. Offtake from JT10 (15 barg — lowest inlet pressure in zone). On-site compressor inlet booster compensates for lower ring pressure. 1,400 vehicles/day. Airport bus fleet primary customer." },
  D1: { title: "D1 — Dwarka Sectors 1-4 Residential", color: "#b91c1c",
    body: "Dense residential demand zone, Dwarka Sectors 1-4. Served by DRS1. 18,000 PNG connections. Predominantly DDA flats (4-6 floor). Daily demand: 25,000 SCMD. Peak cooking hours: 07:30-09:30, 19:00-21:00. IGL meter-reading: quarterly physical inspection." },
  D2: { title: "D2 — Dwarka Sectors 5-8 Residential", color: "#b91c1c",
    body: "Residential demand zone, Dwarka Sectors 5-8 including Sector 6 market and Sector 7 community centre. Served by DRS1. 20,000 PNG connections. Daily demand: 28,000 SCMD. Includes 12 RWA bulk metering groups." },
  D3: { title: "D3 — Dwarka Sectors 9-13 Residential", color: "#b91c1c",
    body: "Mixed residential-commercial zone. Served by DRS2. Includes Dwarka Sector 10 market complex, private hospitals. 25,000 PNG + 200 commercial. Daily demand: 35,000 SCMD." },
  D4: { title: "D4 — Dwarka Sectors 20-23 Residential", color: "#b91c1c",
    body: "South Dwarka residential expansion. Served by DRS5. 18,000 PNG connections. Newer construction — higher per-capita gas consumption (piped-only homes, no LPG backup). 30,000 SCMD." },
  D5: { title: "D5 — Palam Residential Zone", color: "#b91c1c",
    body: "Palam village and Palam south urban residential. Served by DRS6. 12,000 PNG connections. Mixed old-village houses and planned colony. 20,000 SCMD. Low-income area — IGL connection deposit subsidy applied." },
  D6: { title: "D6 — Kapashera Industrial Zone", color: "#b91c1c",
    body: "Kapashera electronics assembly and warehouse industrial cluster. Served by DRS7. 15 large industrial consumers + 8,000 PNG residential. Peak industrial demand: 40,000 SCMD. Coriolis metered, online telemetry." },
  D7: { title: "D7 — IGI Cargo & Hotel Strip", color: "#b91c1c",
    body: "IGI Airport cargo village and NH-48 hotel corridor. Served by DRS4. 150 commercial consumers (hotels, restaurants, offices). Daily demand: 15,000 SCMD, high seasonal peak (cricket season, G20 type events). Uninterruptible class supply." },
  E5: { title: "Valve E5: JT3 → BUF (Line-Pack Fill)", color: "#1d4ed8",
    body: "Buffer vessel fill valve — opens when JT3 > 17 barg (ring surplus). Routes excess ring gas into HP buffer vessel for short-term storage. Electro-pneumatic actuated, Modbus coil buf_fill_active." },
  E6: { title: "Valve E6: BUF → JT2 (Line-Pack Discharge)", color: "#1d4ed8",
    body: "Buffer vessel discharge valve — opens when JT2 < 16 barg (ring deficit). Releases stored gas back into ring at Mahipalpur N junction. Interlock: E5 and E6 cannot both be open. Coil buf_discharge_active." },
};

function midpoint(a, b) { return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }; }

function ValveSymbol({ from, to, id, selected, onClick }) {
  const mid = midpoint(from, to);
  const dx = to.x - from.x, dy = to.y - from.y;
  const deg = Math.atan2(dy, dx) * 180 / Math.PI;
  const col = selected === id ? "#b45309" : "#1d4ed8";
  return (
    <g transform={`translate(${mid.x},${mid.y}) rotate(${deg})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <line x1={-28} y1={0} x2={28} y2={0} stroke={selected === id ? "#b45309" : "#94a3b8"} strokeWidth={3.5} />
      <polygon points="-9,-7 9,-7 0,0" fill={col} opacity={0.9} />
      <polygon points="-9,7 9,7 0,0" fill={col} opacity={0.9} />
      <line x1={0} y1={-7} x2={0} y2={-15} stroke={col} strokeWidth={1.5} />
      <rect x={-4} y={-18} width={8} height={3} rx={1.5} fill={col} />
    </g>
  );
}

function CompressorSymbol({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const col = isSelected ? "#b45309" : "#6d28d9";
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <circle cx={0} cy={0} r={19} fill={isSelected ? "rgba(180,83,9,0.12)" : "rgba(109,40,217,0.1)"} stroke={col} strokeWidth={2}
        style={{ filter: isSelected ? `drop-shadow(0 0 6px ${col})` : "none", transition: "all 0.2s" }} />
      {[0,60,120,180,240,300].map(deg => (
        <line key={deg} x1={0} y1={0} x2={Math.cos(deg*Math.PI/180)*13} y2={Math.sin(deg*Math.PI/180)*13} stroke={col} strokeWidth={1.8} strokeLinecap="round" />
      ))}
      <circle cx={0} cy={0} r={3} fill={col} />
      <text x={0} y={-26} textAnchor="middle" fontSize={8.5} fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
    </g>
  );
}

function DRSSymbol({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const col = isSelected ? "#b45309" : "#c2410c";
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <rect x={-18} y={-12} width={36} height={24} rx={4}
        fill={isSelected ? "rgba(180,83,9,0.12)" : "rgba(194,65,12,0.10)"}
        stroke={col} strokeWidth={1.8}
        style={{ filter: isSelected ? `drop-shadow(0 0 5px ${col})` : "none", transition: "all 0.2s" }} />
      <polyline points="-11,-5 -3,-5 -3,5 11,5" fill="none" stroke={col} strokeWidth={1.5} strokeLinejoin="round" />
      <polygon points="9,2 13,5 9,8" fill={col} />
      <text x={0} y={-21} textAnchor="middle" fontSize={8.5} fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
      <text x={0} y={-11} textAnchor="middle" fontSize={6.5} fill={`${col}bb`} fontFamily="'Fira Code', monospace">{node.sub}</text>
    </g>
  );
}

function CNGSymbol({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const col = isSelected ? "#b45309" : "#0e7490";
  const pts = Array.from({ length: 6 }, (_, i) => {
    const a = (i * 60 - 30) * Math.PI / 180;
    return `${(14 * Math.cos(a)).toFixed(1)},${(14 * Math.sin(a)).toFixed(1)}`;
  }).join(" ");
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <polygon points={pts}
        fill={isSelected ? "rgba(180,83,9,0.12)" : "rgba(14,116,144,0.10)"}
        stroke={col} strokeWidth={1.8}
        style={{ filter: isSelected ? `drop-shadow(0 0 5px ${col})` : "none", transition: "all 0.2s" }} />
      <text x={0} y={2} textAnchor="middle" fontSize={6} fill={col} fontFamily="'Fira Code', monospace" fontWeight="800" style={{ pointerEvents: "none" }}>CNG</text>
      <text x={0} y={-22} textAnchor="middle" fontSize={8.5} fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
    </g>
  );
}

function StorageSymbol({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const col = isSelected ? "#b45309" : "#1d4ed8";
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <ellipse cx={0} cy={0} rx={18} ry={11} fill={isSelected ? "rgba(180,83,9,0.12)" : "rgba(29,78,216,0.10)"} stroke={col} strokeWidth={2}
        style={{ filter: isSelected ? `drop-shadow(0 0 5px ${col})` : "none", transition: "all 0.2s" }} />
      <rect x={-18} y={-11} width={36} height={16} fill={isSelected ? "rgba(180,83,9,0.06)" : "rgba(29,78,216,0.06)"} stroke="none" />
      <ellipse cx={0} cy={5} rx={18} ry={11} fill="none" stroke={col} strokeWidth={2} />
      <text x={0} y={-19} textAnchor="middle" fontSize={8.5} fill={col} fontFamily="'Fira Code', monospace" fontWeight="700">{node.label}</text>
    </g>
  );
}

function NodeCircle({ node, id, selected, onClick }) {
  const isSelected = selected === id;
  const isSource = node.type === "source";
  const isDemand = node.type === "demand";
  const col = isSource ? "#15803d" : isDemand ? "#b91c1c" : "#475569";
  const fillCol = isSelected
    ? (isSource ? "rgba(21,128,61,0.15)" : isDemand ? "rgba(185,28,28,0.15)" : "rgba(71,85,105,0.15)")
    : (isSource ? "rgba(21,128,61,0.08)" : isDemand ? "rgba(185,28,28,0.08)" : "rgba(71,85,105,0.08)");
  const r = isDemand ? 10 : isSource ? 12 : 8;
  return (
    <g transform={`translate(${node.x},${node.y})`} onClick={onClick} style={{ cursor: "pointer" }}>
      <circle cx={0} cy={0} r={r} fill={fillCol} stroke={isSelected ? "#b45309" : col} strokeWidth={isSelected ? 2.5 : 1.5}
        style={{ filter: isSelected ? "drop-shadow(0 0 5px #b45309)" : "none", transition: "all 0.2s" }} />
      {isSource && (<><line x1={-5} y1={0} x2={5} y2={0} stroke={col} strokeWidth={1.8} /><line x1={0} y1={-5} x2={0} y2={5} stroke={col} strokeWidth={1.8} /></>)}
      {isDemand && <polygon points="0,-5 5,3 -5,3" fill={col} opacity={0.8} />}
      <text x={0} y={r+12} textAnchor="middle" fontSize={9} fontWeight="800"
        fill={isSelected ? "#b45309" : col} fontFamily="'Fira Code', monospace" style={{ pointerEvents: "none" }}>{node.label}</text>
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
          <div style={{ fontSize: 10, color: "#0369a1", fontFamily: "'Fira Code', monospace", letterSpacing: 3, textTransform: "uppercase" }}>
            v3 · Realistic City Network · IGL Delhi South-West Zone
          </div>
          <h1 style={{ margin: "3px 0 0", fontSize: 18, fontWeight: 800, color: "#0f172a", letterSpacing: -0.5 }}>
            36-Node IGL Steel Ladder-Ring · Rajokri → Dwarka → Aerocity
          </h1>
          <div style={{ fontSize: 10, color: "#64748b", marginTop: 2 }}>
            PNGRB T4S · 19 barg MAOP · IS 3589 steel · Source: iglonline.net/igl-pipeline-network + IGL Annual Reports
          </div>
        </div>
        <div style={{ display: "flex", gap: 12, fontSize: 10, color: "#64748b", flexWrap: "wrap", maxWidth: 520 }}>
          {[
            ["●","#15803d","Source / CGS (2)"],["●","#475569","Junction (10)"],["▲","#b91c1c","Demand Zone (7)"],
            ["◎","#6d28d9","Compressor (2)"],["▬","#c2410c","DRS Station (8)"],["⬡","#0e7490","CNG Station (6)"],
            ["⌀","#1d4ed8","HP Buffer (1)"],["⋈","#1d4ed8","Valve (2)"],
          ].map(([sym,col,lbl]) => (
            <div key={lbl} style={{ display: "flex", alignItems: "center", gap: 4 }}>
              <span style={{ color: col, fontSize: 12 }}>{sym}</span><span>{lbl}</span>
            </div>
          ))}
        </div>
      </div>

      <div style={{ display: "flex", flex: 1, padding: "12px 16px 16px", gap: 14, minHeight: 560 }}>
        <div style={{ flex: 1, background: "#fff", border: "1px solid #e2e8f0", borderRadius: 12, overflow: "hidden", position: "relative", boxShadow: "0 1px 4px rgba(0,0,0,0.06)" }}>
          <svg width="100%" height="100%" style={{ position: "absolute", top: 0, left: 0, pointerEvents: "none" }}>
            <defs>
              <pattern id="gridv3" width="40" height="40" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 40" fill="none" stroke="rgba(0,0,0,0.03)" strokeWidth="1" />
              </pattern>
            </defs>
            <rect width="100%" height="100%" fill="url(#gridv3)" />
          </svg>

          <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="100%" style={{ position: "relative", zIndex: 1 }}>

            {/* Geographic zone backgrounds */}
            <rect x={52} y={155} width={475} height={400} rx={10} fill="rgba(59,130,246,0.03)" stroke="rgba(59,130,246,0.09)" strokeWidth={1} strokeDasharray="5 3" />
            <text x={290} y={170} textAnchor="middle" fontSize={8} fill="rgba(59,130,246,0.45)" fontFamily="sans-serif">Dwarka Zone · Sectors 1-23 · ~2M residents</text>
            <rect x={790} y={155} width={235} height={400} rx={10} fill="rgba(234,179,8,0.03)" stroke="rgba(234,179,8,0.09)" strokeWidth={1} strokeDasharray="5 3" />
            <text x={907} y={170} textAnchor="middle" fontSize={8} fill="rgba(180,120,0,0.5)" fontFamily="sans-serif">Mahipalpur Zone</text>
            <rect x={1030} y={155} width={295} height={400} rx={10} fill="rgba(249,115,22,0.03)" stroke="rgba(249,115,22,0.09)" strokeWidth={1} strokeDasharray="5 3" />
            <text x={1178} y={170} textAnchor="middle" fontSize={8} fill="rgba(180,70,0,0.5)" fontFamily="sans-serif">Aerocity / IGI Airport Zone</text>
            <rect x={527} y={340} width={260} height={215} rx={10} fill="rgba(34,197,94,0.03)" stroke="rgba(34,197,94,0.09)" strokeWidth={1} strokeDasharray="5 3" />
            <text x={657} y={356} textAnchor="middle" fontSize={8} fill="rgba(21,128,61,0.5)" fontFamily="sans-serif">Palam / Airport S Zone</text>
            {/* HP Ring outline */}
            <rect x={90} y={165} width={1235} height={255} rx={12} fill="rgba(180,83,9,0.012)" stroke="rgba(180,83,9,0.07)" strokeWidth={1.5} strokeDasharray="8 4" />
            <text x={182} y={180} fontSize={7.5} fill="rgba(180,83,9,0.4)" fontFamily="'Fira Code', monospace">HP RING · 15-19 barg · IS 3589 steel · Ladder topology</text>

            {/* Rail labels */}
            <text x={660} y={192} textAnchor="middle" fontSize={7.5} fill="#94a3b8" fontFamily="sans-serif">N rail</text>
            <text x={660} y={400} textAnchor="middle" fontSize={7.5} fill="#94a3b8" fontFamily="sans-serif">S rail</text>

            {/* Pipe edges */}
            {pipes.map(e => {
              const a = NODES[e.from], b = NODES[e.to];
              if (!a || !b) return null;
              const isSel = selected === e.id;
              return (
                <g key={e.id}>
                  {isSel && <line x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="#b45309" strokeWidth={9} opacity={0.10} strokeLinecap="round" />}
                  <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke={isSel ? "#b45309" : "#94a3b8"}
                    strokeWidth={isSel ? 4.5 : 2.5} strokeLinecap="round"
                    style={{ cursor: "pointer", transition: "all 0.2s" }}
                    onClick={sel(e.id)} />
                  <text x={(a.x+b.x)/2 + (Math.abs(a.y-b.y)>40 ? 10 : 0)}
                    y={(a.y+b.y)/2 + (Math.abs(a.y-b.y)>40 ? 0 : -7)}
                    textAnchor="middle" fontSize={7.5}
                    fill={isSel ? "#b45309" : "#cbd5e1"}
                    fontFamily="'Fira Code', monospace"
                    style={{ pointerEvents: "none" }}>{e.id}</text>
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
                  {isSel && <line x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="#b45309" strokeWidth={9} opacity={0.10} strokeLinecap="round" />}
                  <line x1={a.x} y1={a.y} x2={b.x} y2={b.y}
                    stroke={isSel ? "#b45309" : "#94a3b8"}
                    strokeWidth={3} strokeLinecap="round" strokeDasharray="6 3"
                    style={{ cursor: "pointer" }} onClick={sel(e.id)} />
                  <ValveSymbol from={a} to={b} id={e.id} selected={selected} onClick={sel(e.id)} />
                  <text x={(a.x+b.x)/2+12} y={(a.y+b.y)/2-4}
                    textAnchor="middle" fontSize={7.5}
                    fill={isSel ? "#b45309" : "#1d4ed8"}
                    fontFamily="'Fira Code', monospace"
                    style={{ pointerEvents: "none" }}>{e.id}</text>
                </g>
              );
            })}

            {/* Special symbols */}
            <CompressorSymbol node={NODES.CS1}     id="CS1"     selected={selected} onClick={sel("CS1")} />
            <CompressorSymbol node={NODES.CS2}     id="CS2"     selected={selected} onClick={sel("CS2")} />
            <StorageSymbol    node={NODES.BUF}     id="BUF"     selected={selected} onClick={sel("BUF")} />
            {Object.entries(NODES).filter(([,n]) => n.type === "drs").map(([id,n]) => (
              <DRSSymbol key={id} node={n} id={id} selected={selected} onClick={sel(id)} />
            ))}
            {Object.entries(NODES).filter(([,n]) => n.type === "cng").map(([id,n]) => (
              <CNGSymbol key={id} node={n} id={id} selected={selected} onClick={sel(id)} />
            ))}
            {regularNodes.map(([id, node]) => (
              <NodeCircle key={id} node={node} id={id} selected={selected} onClick={sel(id)} />
            ))}

            {/* Pressure labels */}
            {Object.entries(NOMINAL_PRESSURES).map(([id, val]) => {
              const n = NODES[id];
              if (!n) return null;
              const isSpecial = specialTypes.has(n.type);
              const yOff = isSpecial ? 20 : n.type === "demand" ? -4 : 20;
              return (
                <text key={`p-${id}`} x={n.x} y={n.y + yOff}
                  textAnchor="middle" fontSize={7} fill="#94a3b8"
                  fontFamily="'Fira Code', monospace"
                  style={{ pointerEvents: "none" }}>{val}</text>
              );
            })}

            {/* SCADA telemetry dots */}
            {["JT1","JT3","JT5","JT8","JT10","DRS1","DRS6"].map(id => {
              const n = NODES[id];
              if (!n) return null;
              return (
                <circle key={`rtu-${id}`} cx={n.x+13} cy={n.y-13} r={3}
                  fill="rgba(3,105,161,0.4)" stroke="#0369a1" strokeWidth={0.8}
                  style={{ pointerEvents: "none" }} />
              );
            })}
            <text x={1095} y={150} fontSize={7.5} fill="#0369a1" fontFamily="'Fira Code', monospace" style={{ pointerEvents: "none" }}>● SCADA/EFM</text>
          </svg>
        </div>

        {/* Info panel */}
        <div style={{ width: 280, background: "#fff", border: "1px solid #e2e8f0", borderRadius: 12, padding: 16, display: "flex", flexDirection: "column", boxShadow: "0 1px 4px rgba(0,0,0,0.06)" }}>
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
                ["City","Delhi South-West Zone","#0369a1"],
                ["Operator","IGL (Indraprastha Gas)","#0369a1"],
                ["Topology","Ladder-ring (5×2 grid)","#475569"],
                ["Nodes","36 (2 CGS + 10 JT + 22)","#15803d"],
                ["Edges","38 pipes + 2 valves","#0369a1"],
                ["HP Ring","15–19 barg (IS 3589 steel)","#b45309"],
                ["DRS stations","8 (4 barg MDPE outlet)","#c2410c"],
                ["CNG stations","6 (250 barg cascade)","#0e7490"],
                ["Demand zones","7 (4 barg distribution)","#b91c1c"],
                ["Coverage","~300 km² (SW Delhi)","#475569"],
                ["PNG connections","~200,000 in zone","#475569"],
                ["SCADA nodes","7 (IGL EFM telemetry)","#0369a1"],
              ].map(([lbl, val, col]) => (
                <div key={lbl} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", borderBottom: "1px solid #f8fafc", paddingBottom: 4 }}>
                  <span style={{ color: "#64748b", fontSize: 10 }}>{lbl}</span>
                  <span style={{ color: col, fontFamily: "'Fira Code', monospace", fontSize: 10, fontWeight: 700 }}>{val}</span>
                </div>
              ))}
              <div style={{ marginTop: "auto", borderTop: "1px solid #f1f5f9", paddingTop: 10 }}>
                <div style={{ color: "#94a3b8", fontSize: 9, fontFamily: "'Fira Code', monospace", letterSpacing: 1, marginBottom: 6 }}>PIPE PARAMS (IGL standard)</div>
                {[["DN250 (main rail)","7.11 mm wall"],["DN200 (rungs)","5.74 mm wall"],["DN80-100 (spurs)","3.76 mm wall"],["Material","IS 3589 Gr.FE490"],["Roughness","15 μm (newer pipe)"],["MAOP","19 barg (IGL Delhi)"]].map(([k,v]) => (
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
        36 nodes · 40 edges · ladder-ring topology · IGL SW Delhi (Rajokri CGS → Aerocity) · PNGRB authorized GA
      </div>
    </div>
  );
}
