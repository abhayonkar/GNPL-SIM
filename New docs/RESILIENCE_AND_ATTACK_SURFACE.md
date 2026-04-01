% RESILIENCE_AND_ATTACK_SURFACE.md
% ========================================================
% Phase 7: Indian CGD Network — Resilience Topology Changes
% and Critical Attack Point Analysis (PNGRB T4S basis)
% ========================================================

# Indian CGD Network — Resilience Upgrade and Critical Attack Surface

## Part 1: Resilience Architecture Changes

### 1.1 Problem: Single Points of Failure in Original 20-Node Topology

The original 20-node topology has three structural vulnerabilities that
would interrupt supply if exploited:

| Vulnerability | Impact | PNGRB T4S Reference |
|---|---|---|
| CS2 failure (node 7) | D3, D4, D5, D6 lose supply entirely | T4S §6.3 N-1 requirement |
| J4→CS2→J5 is the only path to eastern distribution | No alternate route to J5 | T4S §5.2 redundancy |
| D1 has no isolation valve pre-PRS1 | Overpressure propagates to consumer | T4S §8.1 isolation |

### 1.2 Resilience Changes Made (Phase 7)

TWO new edges + ONE new valve added to simConfig.m:

#### E21: J4 → J7 Cross-Tie (DN100, 8 km)
```
Purpose  : Bypass CS2 during CS2 failure or attack
IS 3589  : DN100 (0.102 m ID), API 5L Gr.B
Condition: Activates when CS2_alarm coil = TRUE or cs_mode = 'CS1_only'
Effect   : Provides 40-60% of normal CS2 flow via alternate path
PNGRB    : Satisfies T4S §6.3 N-1 continuity requirement
```

#### E22: J3 → J5 Emergency Bypass (DN80, 12 km)
```
Purpose  : Direct feed to eastern distribution (J5) if J4/CS2 fully blocked
IS 3589  : DN80 (0.082 m ID), API 5L Gr.B
Condition: Activates only in extreme stress (emergency_bypass_enable = true)
Effect   : Maintains minimum 30% flow to D3/D4 during double contingency
PNGRB    : T4S §5.4 emergency supply provision
```

#### V_D1: Isolation Valve on E10 (D1 supply line)
```
Purpose  : Isolate D1 node on overpressure or sensor spoof detection
Register : Modbus addr 109 (extends existing 9-actuator map)
Condition: PLC closes V_D1 if p_D1 > 20 barg (prevents overpressure at DRS1)
PNGRB    : T4S Annexure III mandatory isolating valve before DRS
```

### 1.3 Updated Network Topology Diagram (ASCII)

```
S1─────E1──J1──E2──CS1──E3──J2──E4──J3──E5──J4──E6──CS2──E7──J5
                         │         │         │              │    │
                         E8        E12       E19      ┌─────E21  │
                         │         │         │        │    (new)  │
                         J6        J7        D5       │         E16
                         │         │    ┌────┘        │           │
                         E9        E14  │  S2──E13    │         PRS2──E17──D3
                         │         │   │              │           │
                        PRS1      STO  E22 (new)      └─────────E15──E18──D4
                         │         │   │  (J3→J5)
                        E10       E15  │
                         │         │  J5 (also fed by E22 emergency)
                        D1        J5
                        E11       E16
                        D2       PRS2
                              E17  E18
                              D3   D4
```

---

## Part 2: Critical Attack Points Analysis

### 2.1 Methodology

Criticality scoring per node/edge uses three factors:
- **C** = Consequence score (1–5): physical impact if compromised
- **A** = Attack accessibility (1–5): ease of Modbus-layer access
- **D** = Detection difficulty (1–5): how hard to detect via EKF+CUSUM

**Criticality = C × A × D** (max = 125)

### 2.2 Node Criticality Rankings

| Rank | Node | C | A | D | Score | Attack Type | Why Critical |
|------|------|---|---|---|-------|-------------|--------------|
| 1 | **CS1** (node 3) | 5 | 5 | 4 | 100 | A2: Compressor ratio spoof | Single compressor failure halts entire S1 trunk |
| 2 | **J7** (node 11) | 5 | 3 | 5 | 75 | A9: Stealthy FDI | Hub connecting S2, storage, and upper demand; FDI invisible to EKF |
| 3 | **PRS1** (node 10) | 4 | 4 | 4 | 64 | A5: Sensor spoof | DRS1 controls D1/D2 supply; SSV trip cascades to full supply loss |
| 4 | **J5** (node 8) | 4 | 3 | 5 | 60 | A9: FDI (triangle 4-5-8) | Eastern distribution hub; storage withdrawal trigger |
| 5 | **S1** (node 1) | 5 | 3 | 4 | 60 | A1: Source pressure manip | Primary source; manipulation forces CS1 over-compensation |
| 6 | **CS2** (node 7) | 4 | 4 | 4 | 64 | A2: CS2 ratio spoof | Without E21 cross-tie: isolates entire eastern grid |
| 7 | **STO** (node 12) | 3 | 3 | 5 | 45 | A3: Valve force | Storage valve E14/E15 forcing disrupts linepack |
| 8 | **PRS2** (node 13) | 4 | 3 | 3 | 36 | A5: Spoof D3 sensor | DRS2 feeds CNG stations (D4) and industrial MRS (D3) |
| 9 | **D1** (node 15) | 3 | 4 | 3 | 36 | A5: Bias spoof | CS1 PID feedback node; bias causes runaway compression |
| 10 | **J2** (node 4) | 3 | 3 | 3 | 27 | A9: FDI origin | Triangle FDI vertex; branch junction |

### 2.3 Edge Criticality Rankings

| Rank | Edge | C | A | D | Score | Attack Type | Explanation |
|------|------|---|---|---|-------|-------------|-------------|
| 1 | **E12** (J3→J7) | 5 | 4 | 4 | 80 | A8: Leak simulation | Upper trunk; only path from main grid to S2/J7/storage zone |
| 2 | **E7** (CS2→J5) | 5 | 4 | 4 | 80 | A3: Force valve (if added) | Only feed to eastern hub; loss = D3/D4/D5/D6 outage |
| 3 | **E15** (STO→J5) | 4 | 5 | 4 | 80 | A3: Force withdraw valve | Attacker forces storage drain during peak demand |
| 4 | **E3** (CS1→J2) | 5 | 3 | 4 | 60 | A8: Leak at E3 | Main trunk post-CS1; leak causes rapid pressure drop S1 side |
| 5 | **E10** (PRS1→D1) | 4 | 4 | 3 | 48 | A6: Flow meter spoof | CS1 PID feedback flow; spoof causes pump over-run |
| 6 | **E16** (J5→PRS2) | 4 | 3 | 4 | 48 | A8: Leak at E16 | Eastern distribution trunk; supplies 4 demand nodes |
| 7 | **E14** (J7→STO) | 3 | 5 | 4 | 60 | A3: Force inject | Drains main grid pressure into storage during low-demand |
| 8 | **E8** (J2→J6, valve) | 3 | 5 | 3 | 45 | A3: Force close E8 | Starves D1/D2 side branch if closed without CS1 rerouting |

### 2.4 Attack Path Scenarios (Top 5 High-Risk)

#### AP-1: CS2 Compressor Ratio Spoof + E7 Downstream Starvation
```
Attack: A2 on CS2 (ratio → 1.45, near trip)
Vector: FC16 write to Modbus reg 101 (cs2_ratio_cmd)
Effect: CS2 overdrives → J5 overpressure → PRS2 SSV trips → D3/D4 cutoff
CUSUM response: fires at ~45 s (pressure rises 2+ barg at J5)
EKF response: chi2_alarm at ~30 s (J5 innovation > 1 barg)
Resilience counter: E21 cross-tie does NOT help (J5 overpressure, not starvation)
Detection priority: HIGH — add J5 overpressure alarm in PLC
```

#### AP-2: Stealthy FDI Triangle J2-J3-J5 + Storage Drain
```
Attack: A9 FDI on nodes 4,5,8 simultaneously with A3 (force E15 open)
Vector: FC16 overwrites sensor_p for J2/J3/J5; FC5 forces coil 4 (sto_withdraw)
Effect: PLC sees "normal" pressures; storage drains silently; actual J5 pressure
        drops below 20 barg trigger but PLC coil never fires for real withdrawal
CUSUM response: minimal (FDI designed for zero EKF innovation)
Detection: ONLY via Weymouth residual cross-check (physics cross-validation)
Resilience: E22 emergency bypass can maintain J5 if physics divergence detected
```

#### AP-3: Source S1 Pressure Spike + CS1 Overcorrection Cascade
```
Attack: A1 — spoof S1 to 28 barg (above MAOP alarm)
Effect: MAOP alarm fires → PLC commands emergency_shutdown → CS1 stops
        → S1 side grid depressurises → J2, J3 fall below 18 barg
        → E8 opens (pressure-based logic) → PRS1 SSV trips (no inlet pressure)
        → D1/D2 lose supply
Cascade time: ~90 s from attack start to D1/D2 outage
CUSUM fires: ~15 s (S1 innovation spike)
Resilience: None directly. Add hysteresis on emergency_shutdown trigger
            (require sustained > 27 barg for 30 s before trip)
```

#### AP-4: Replay Attack During Morning Peak Demand Transition
```
Attack: A10 — record 60 s of off-peak stable registers; replay during morning peak
Effect: PLC receives "stable" low-demand readings while true demand rises
        → CS1/CS2 ratios held at off-peak levels → D1/D2/D3 under-pressured
        → PRS1/PRS2 open fully → demand nodes drop below 14 barg
Detect via: inter-arrival time distribution (frozen variance = replay signature)
CUSUM fires: ~120 s (slow pressure drift accumulates in innovation)
Resilience: E21 cross-tie provides partial compensation if CS2 short of flow
```

#### AP-5: Pipeline Leak at E12 + Masking via Flow Meter Spoof (A6+A8 combined)
```
Attack: A8 (leak at E12) + A6 (spoof E12 flow meter to show normal reading)
Effect: Real leak drains J3/J7 pressure; spoofed flow shows normal transit flow
        → PLC/EKF sees normal flow on E12; actual J7 pressure drops
        → Storage coil sto_inject_active fires when J7 < 20 barg (delayed)
        → Storage drains attempting to compensate; both stresses compound
Detect via: Kirchhoff mass-balance residual at J3 (sum of flows ≠ 0)
CUSUM fires: ~180 s (slow J7 pressure drift)
Resilience: E21 cross-tie (J4→J7) helps maintain J7 pressure from CS1 side
```

### 2.5 Attack Surface After Resilience Upgrade

| Scenario | Before E21/E22 | After E21/E22 | Residual Risk |
|---|---|---|---|
| CS2 failure | D3-D6 outage (100%) | D3-D6 partial supply via E21 (60%) | Reduced 40% |
| AP-1 (CS2 ratio spoof) | D3-D6 outage | Overpressure contained by PRS2 SSV | Still possible |
| AP-2 (FDI + storage drain) | Full eastern grid failure | E22 provides minimum supply | Reduced 70% |
| AP-3 (S1 spike cascade) | D1/D2 outage | No change (E21 feeds eastern, not D1) | Unchanged |
| AP-4 (replay + peak demand) | Under-pressure across grid | E21 provides partial CS2 bypass | Reduced 30% |
| AP-5 (leak + spoof) | J7 pressure collapse | E21 feeds J7 from J4 side | Reduced 60% |

### 2.6 New Attack Vectors Introduced by Resilience Edges

**WARNING: E21 and E22 are NEW attack surfaces.**

| New Attack | Vector | Risk |
|---|---|---|
| Force E21 open during off-peak | Backflows from J7 to J4, disrupts CS1 PID | Medium |
| Force E21 closed during CS2 failure | Prevents intended bypass → outage | High |
| Force E22 open during normal ops | Short-circuits CS2 → pressure equalisation | Medium |
| Spoof pressure at J7 to trigger false E21 activation | Disrupts normal trunk flow | Medium |

**Mitigation in PLC_PRG:** E21 and E22 must be under PLC interlocked control, not exposed as free-writable Modbus registers. Map to read-only coils in the Modbus register map.

---

## Part 3: Implementation Notes for MATLAB

### 3.1 Changes to updateFlow.m

The compatibility wrapper must support:
1. Check `cfg.crosstie_enable` → if true, add E21 flow contribution
2. Check `cfg.emergency_bypass_enable` → if true, add E22 flow contribution
3. `v_d1_cmd` controls the E10 valve position (multiplied into q(10))

```matlab
% In updateFlow_v7.m (compatibility wrapper):
% After standard Darcy-Weisbach q calculation:

if isfield(cfg, 'crosstie_enable') && cfg.crosstie_enable
    D21 = cfg.resilience_edge_D(1);  L21 = cfg.resilience_edge_L(1);
    dp21 = p(6)^2 - p(11)^2;        % J4→J7
    K21  = sqrt(16*0.015*L21/(pi^2*D21^5));
    q21  = sign(dp21)*sqrt(abs(dp21))/K21;
    % Add to J4 (node 6) outflow and J7 (node 11) inflow in mass balance
    % Note: does NOT go through the standard B matrix — handled as injection
    state.q_crosstie = q21;
end

if isfield(cfg, 'v_d1_cmd')
    q(10) = q(10) * cfg.v_d1_cmd;   % isolate D1 supply
end
```

### 3.2 Changes to updateControlLogic.m

Add to the valve interlock section:

```matlab
% Close D1 isolation valve if D1 overpressure detected
if length(xhatP) >= 15 && xhatP(15) > 20.0
    cfg.v_d1_cmd = 0;
    logEvent('WARNING','updateControlLogic','D1 isolation valve CLOSED — overpressure',k,dt);
end

% Activate E21 cross-tie if CS2 alarm active
if plc.act_cs2_alarm
    cfg.crosstie_enable = true;
    logEvent('WARNING','updateControlLogic','E21 cross-tie ACTIVATED — CS2 alarm',k,dt);
end
```

### 3.3 Modbus Register Map Extension (v7)

Two new actuator registers required:

| Address | Signal | Scaling | Description |
|---------|--------|---------|-------------|
| 109 | `v_d1_cmd` | 1000 (1=open) | D1 isolation valve |
| 110 | `crosstie_E21_cmd` | 1000 (1=open) | E21 cross-tie valve |
| 111 | `bypass_E22_cmd` | 1000 (1=open) | E22 emergency bypass |

Update CODESYS PLC_PRG to include three new INT variables at addresses 109–111.
Update gateway.py ACTUATOR_MAP to include these three registers.
Update data_logger.py HEADER to include the three new actuator columns.
