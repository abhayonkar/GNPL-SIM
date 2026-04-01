# Gas Pipeline Cyber-Physical Simulator
## Architectural Specifications Document
### Indian City Gas Distribution (CGD) Network — PNGRB T4S Compliant

**Version:** 2.0 (Indian Standard Edition)  
**Standards:** PNGRB T4S (2008, amended 2024) · IS 3589 · IS 1239 · ASME B31.8 · IEC 62443  
**Regulatory Authority:** Petroleum and Natural Gas Regulatory Board (PNGRB), Ministry of Petroleum and Natural Gas, Government of India  
**Date:** March 2026

---

## Table of Contents

1. [What This System Is — A Simple Overview](#1-what-this-system-is)
2. [The Physical Network — 20 Nodes and 20 Pipes](#2-the-physical-network)
3. [Component-by-Component Explanation](#3-component-by-component-explanation)
   - 3.1 [Source Nodes — Where Gas Enters](#31-source-nodes)
   - 3.2 [Junction Nodes — Where Pipes Meet](#32-junction-nodes)
   - 3.3 [Compressor Stations — Pressure Boosters](#33-compressor-stations)
   - 3.4 [Pressure Regulating Stations (PRS) — Pressure Reducers](#34-pressure-regulating-stations)
   - 3.5 [Storage Cavern — The Buffer Tank](#35-storage-cavern)
   - 3.6 [Control Valves — The On/Off Switches](#36-control-valves)
   - 3.7 [Demand Nodes — Where Gas is Delivered](#37-demand-nodes)
4. [How Gas Flows Through the Network](#4-how-gas-flows-through-the-network)
5. [The Software Architecture — How It All Works](#5-the-software-architecture)
6. [The SCADA and Control System](#6-the-scada-and-control-system)
7. [The Communication Stack — How Computers Talk to Each Other](#7-the-communication-stack)
8. [Indian CGD Parameters — Full Specification Table](#8-indian-cgd-parameters)
9. [What Happens When Components Fail or Are Attacked](#9-failure-and-fault-scenarios)
10. [The Dataset It Produces](#10-the-dataset-it-produces)
11. [Standards and Regulatory Compliance](#11-standards-and-regulatory-compliance)

---

## 1. What This System Is — A Simple Overview

This is a **software simulator** of a real Indian City Gas Distribution (CGD) pipeline network. Think of it as a very detailed computer model of the kind of gas pipeline that supplies Piped Natural Gas (PNG) to homes and businesses in Indian cities like Mumbai (served by MGL), Delhi (served by IGL), or Pune (served by MGL/MNGL).

The simulator has three purposes working together:

**Purpose 1 — Physics Simulation (MATLAB)**  
It calculates what happens inside the pipes: how gas pressure changes, how fast gas flows, what temperature it reaches, how a compressor behaves when it boosts pressure. This runs 10 times per second (10 Hz), continuously, like a real SCADA system.

**Purpose 2 — Protocol Simulation (CODESYS SoftPLC + Python)**  
It mimics the way a real Programmable Logic Controller (PLC) communicates with the control room. A PLC is the small computer that sits at each gas station and reads sensor values, then sends them over the network. This creates real-world communication artefacts — tiny timing jitter, quantisation noise from integer conversion — that you cannot get from pure software.

**Purpose 3 — Attack Simulation and Dataset Generation**  
It deliberately introduces 10 types of cyber attacks (drawn from the MITRE ATT&CK for ICS framework) and records everything — both the gas physics and the communication protocol — with labels marking exactly when each attack happened. The result is a labelled dataset for training anomaly detection and intrusion detection AI models.

The entire network is calibrated to **Indian CGD operating conditions** under PNGRB Technical Standards (T4S), not the European GasLib parameters it was originally based on.

---

## 2. The Physical Network

### 2.1 Overview

The network has **20 nodes** (locations) and **20 edges** (pipe segments or connections between locations). It is modelled as a **partially meshed loop network** — meaning there are multiple paths gas can take from source to destination, providing redundancy, just like real Indian CGD steel grid networks.

```
Network Summary
───────────────────────────────────────────────────────────────────
Total Nodes          : 20
Total Edges          : 20 (17 pipes + 3 control valves)
Source Nodes         : 2  (S1 — City Gate Station 1, S2 — City Gate Station 2)
Compressor Stations  : 2  (CS1, CS2 — pressure booster stations)
Pressure Regulating  : 2  (PRS1, PRS2 — DRS-equivalent stations)
  Stations (PRS)
Storage Node         : 1  (STO — underground buffer storage)
Junction Nodes       : 7  (J1, J2, J3, J4, J5, J6, J7)
Demand Nodes         : 6  (D1, D2, D3, D4, D5, D6)
Control Valves       : 3  (E8 on J2→J6, E14 on J7→STO, E15 on STO→J5)
───────────────────────────────────────────────────────────────────
```

### 2.2 Node List with Indian CGD Context

| Node ID | MATLAB Index | Type | Indian CGD Equivalent | Nominal Pressure (barg) |
|---------|-------------|------|-----------------------|------------------------|
| S1 | 1 | Source | City Gate Station (CGS) 1 — entry from transmission line | 24–26 |
| J1 | 2 | Junction | Steel grid junction before booster | 23–25 |
| CS1 | 3 | Compressor | Booster compressor station | 23–25 (inlet) |
| J2 | 4 | Junction | Branch junction — splits trunk and side branch | 23–25 |
| J3 | 5 | Junction | Mid-grid junction | 22–24 |
| J4 | 6 | Junction | Junction before second booster | 21–23 |
| CS2 | 7 | Compressor | Second booster compressor station | 21–23 (inlet) |
| J5 | 8 | Junction | Eastern distribution hub | 20–22 |
| J6 | 9 | Junction | Side branch junction | 20–22 |
| PRS1 | 10 | PRS | District Regulating Station (DRS) 1 — reduces to medium pressure | 18 (outlet) |
| J7 | 11 | Junction | Upper grid junction — connects to second CGS and storage | 22–24 |
| STO | 12 | Storage | Underground buffer storage (gas holder / high-pressure vessel) | 20–24 |
| PRS2 | 13 | PRS | District Regulating Station (DRS) 2 | 14 (outlet) |
| S2 | 14 | Source | City Gate Station (CGS) 2 — second entry point | 22–24 |
| D1 | 15 | Demand | Industrial/commercial consumer via PRS1 | 18 |
| D2 | 16 | Demand | Industrial/commercial consumer via PRS1 | 18 |
| D3 | 17 | Demand | Industrial/commercial consumer via PRS2 | 14 |
| D4 | 18 | Demand | Industrial/commercial consumer via PRS2 | 14 |
| D5 | 19 | Demand | High-pressure direct consumer (industrial) | 20–21 |
| D6 | 20 | Demand | Medium-pressure consumer via J7 | 21–22 |

### 2.3 Edge (Pipe) List

| Edge ID | From → To | Type | Physical Meaning |
|---------|-----------|------|-----------------|
| E1 | S1 → J1 | Pipe | CGS1 outlet header to first grid junction |
| E2 | J1 → CS1 | Pipe | Inlet pipe to Booster Station 1 |
| E3 | CS1 → J2 | Pipe | Boosted gas outlet from CS1 |
| E4 | J2 → J3 | Pipe | Main trunk line — westward |
| E5 | J3 → J4 | Pipe | Continuation of main trunk |
| E6 | J4 → CS2 | Pipe | Inlet pipe to Booster Station 2 |
| E7 | CS2 → J5 | Pipe | Boosted gas outlet from CS2 |
| **E8** | **J2 → J6** | **Valve** | **Side branch isolation valve — key control point** |
| E9 | J6 → PRS1 | Pipe | Pipe from branch junction to DRS1 |
| E10 | PRS1 → D1 | Pipe | Distribution to Consumer Zone 1 |
| E11 | PRS1 → D2 | Pipe | Distribution to Consumer Zone 2 |
| E12 | J3 → J7 | Pipe | Diagonal cross-link to upper grid |
| E13 | S2 → J7 | Pipe | CGS2 outlet header to upper grid junction |
| **E14** | **J7 → STO** | **Valve** | **Storage injection valve — fills storage when pressure is high** |
| **E15** | **STO → J5** | **Valve** | **Storage withdrawal valve — releases gas when pressure is low** |
| E16 | J5 → PRS2 | Pipe | Pipe from eastern hub to DRS2 |
| E17 | PRS2 → D3 | Pipe | Distribution to Consumer Zone 3 |
| E18 | PRS2 → D4 | Pipe | Distribution to Consumer Zone 4 |
| E19 | J4 → D5 | Pipe | Direct high-pressure supply to large industrial consumer |
| E20 | J7 → D6 | Pipe | Supply to medium-pressure consumer near upper grid |

---

## 3. Component-by-Component Explanation

---

### 3.1 Source Nodes — Where Gas Enters

**Nodes: S1 (Node 1) and S2 (Node 14)**

#### What They Are

In a real Indian CGD network, a **Source node** represents a **City Gate Station (CGS)**. This is the point where natural gas arrives from the national high-pressure transmission pipeline (operated by GAIL, GSPL, or another transporter) and is received by the CGD operator (like IGL or MGL) after filtration, pressure regulation, metering, and odourisation.

The gas arriving at CGS typically comes from the national grid at 50–100 barg. The CGS reduces this to 24–26 barg for onward distribution through the steel grid. In this simulator, **we model the gas as already at the CGS outlet pressure** — i.e., the CGS pressure regulation has already happened, and the Sources inject gas at 24–26 barg into our 20-node steel grid network.

#### What They Do in the Simulator

- **S1** is the primary source. Its pressure follows a realistic daily profile — higher during the night (low demand) and lower during the day (high demand). This is generated by `generateSourceProfile.m` using an AR(1) statistical model (autoregressive random walk) with daily oscillations to mimic real gas demand cycles.
- **S2** is the secondary source (at Node 14). It feeds the upper part of the grid via edge E13. It provides supply redundancy — if S1 has reduced supply, S2 can compensate.

#### Indian CGD Parameters

| Parameter | Value | Standard |
|-----------|-------|----------|
| Nominal operating pressure | 24–26 barg | PNGRB T4S, CGD pressure cascade |
| Minimum delivery pressure | 20 barg | Ensure minimum supply to all DRS stations |
| Maximum design pressure | 26 barg | PNGRB T4S — steel grid primary network limit |
| Gas composition | Methane >90%, with ethane, propane, CO₂ traces | GAIL/ONGC domestic supply spec |
| Specific gravity | 0.57 | Indian natural gas (lighter than European gas at 0.60) |
| Odourant | THT (Tetrahydrothiophene) at 20 mg/m³ | PNGRB T4S odourisation requirement |

#### What Happens if a Source Fails or is Attacked

| Scenario | Effect on Network |
|----------|-------------------|
| **S1 fully shuts down** | CS1 starved of inlet gas. CS1 ratio rises as it tries to maintain pressure against falling inlet. J2 and J3 pressures drop. PRS1 may close (insufficient inlet). D1 and D2 go undersupplied. S2 tries to compensate via J7 → J3 (reverse flow via E12 possible). |
| **S1 pressure drops partially (50%)** | Compressor CS1 runs at higher ratio to compensate. Alarms trigger when CS1 ratio exceeds 1.50. Downstream pressures sag. EKF detects residual mismatch — potential anomaly signal. |
| **Attack A1 — S1 pressure spoofed high** | Sensor shows 26 barg but actual physics is 18 barg. Control logic sees no problem. Compressors not alerted. Demand nodes go undersupplied silently. CUSUM alarm may trigger on Weymouth residual mismatch. |
| **S2 fully shuts down** | J7 loses one supply path. STO may be needed to compensate (withdrawal triggered). D6 pressure drops. If J7 pressure falls below 20 barg, PRS2 setpoint may not be maintainable. |

---

### 3.2 Junction Nodes — Where Pipes Meet

**Nodes: J1, J2, J3, J4, J5, J6, J7**

#### What They Are

A junction is simply a pipe intersection — a T-piece, elbow cluster, or manifold in the real pipeline where two or more pipe segments meet. In Indian CGD, these would typically be underground sectionalising valve assemblies or above-ground scraper stations.

Junctions do not add or remove gas from the network by themselves. They are governed by **Kirchhoff's Current Law for gas flow** — the total mass of gas flowing into a junction must equal the total mass flowing out at every instant in time. This is also called the **mass balance constraint** and is enforced by the MATLAB physics engine via the incidence matrix B (a 20×20 matrix).

#### How Pressure Changes at a Junction

At each junction, the gas pressure changes slightly because of the friction loss in the pipe that just delivered the gas (Darcy-Weisbach equation), and the fact that the junction itself has a small physical volume (6 m³ in the model, representing a real manifold volume). The simulator tracks pressure change at each junction using:

```
dP/dt = (c² / V) × (net mass flow in) + acoustic noise term

where:
  c  = speed of sound in gas ≈ 350 m/s at Indian CGD conditions
  V  = nodal volume = 6 m³ (lumped capacitance model)
  dP/dt = rate of pressure change in bar per second
```

This means: if more gas flows in than flows out, pressure rises. If more flows out than in, pressure falls. The compressors and PRS stations are controlled to prevent either extreme.

#### Key Junctions and Their Roles

**J2 (Node 4) — The Branch Junction**  
This is the most important junction in the network. It receives high-pressure gas from CS1 (via E3) and has two onward paths:
- The **main trunk** (via E4 → J3 → J4 → CS2) for the eastern distribution network
- The **side branch** (via valve E8 → J6 → PRS1) for DRS1 and its consumers D1 and D2

The valve E8 controls which path gets gas. In normal operation, E8 is open and both paths are active.

**J7 (Node 11) — The Upper Grid Hub**  
J7 receives gas from two directions: from J3 via the diagonal E12, and from S2 via E13. It distributes to D6 (via E20) and can inject gas into storage STO (via valve E14). When J7 pressure is higher than normal, the excess is stored. When J7 pressure falls, storage releases gas back to J5 via E15.

#### What Happens if a Junction Has a Problem

| Scenario | Effect on Network |
|----------|-------------------|
| **Junction isolation (sectionalising valve closed around junction)** | Gas cannot pass through. The network splits into two independent sub-networks. Upstream pressure builds; downstream pressure falls. Compressor ratios increase. Emergency shutdown may trigger. |
| **Pipe leak at junction (Attack A8 — pipeline leak simulation)** | Mass flow balance violated at the junction. EKF detects a residual — the measured flow into J3 does not match the predicted flow based on upstream/downstream pressures. CUSUM raises alarm. |
| **Sensor failure at junction** | Control system loses visibility of that junction's pressure. EKF estimation continues using other correlated measurements, but uncertainty grows. False alarms may occur as EKF residuals widen. |

---

### 3.3 Compressor Stations — Pressure Boosters

**Nodes: CS1 (Node 3) and CS2 (Node 7)**

#### What They Are in Indian CGD

In a real Indian CGD network, booster compressor stations are used when gas has to travel long distances within the steel grid and pressure has dropped too much for proper distribution. Companies like IGL and MGL use electrically driven centrifugal or reciprocating compressors at strategic points in the steel grid.

In this simulator, **CS1** and **CS2** are centrifugal compressor stations modelled with realistic engineering behaviour: a head-flow curve, a power-efficiency curve, and a ratio alarm that protects against surge.

#### How a Compressor Works Here — Step by Step

Gas enters the compressor at inlet pressure P_in. The compressor impeller spins at high speed and imparts kinetic energy to the gas. This kinetic energy is converted to pressure energy in the diffuser section. The gas exits at outlet pressure P_out, which is higher than P_in. The ratio P_out / P_in is called the **compression ratio**.

The amount of pressure boost the compressor can provide depends on how much gas is flowing through it — this relationship is called the **head-flow curve**:

```
CS1 Head Curve (Indian CGD adapted):
  H (m) = 800 − 0.8 × ṁ − 0.002 × ṁ²
  (head is approximately 800 m at zero flow, falling as flow increases)

CS2 Head Curve:
  H (m) = 500 − 0.5 × ṁ − 0.001 × ṁ²
  (CS2 is smaller than CS1, handles lower flow)

where ṁ is mass flow in kg/s
```

In Indian CGD terms: CS1 produces a pressure boost of approximately 1.1–1.5× (ratio 1.1 to 1.5). At normal flows, CS1 inlet pressure is ~22 barg and outlet is ~24–26 barg.

#### Efficiency and Power

The compressor also consumes electrical power. The efficiency (fraction of input power that becomes gas pressure energy) is:

```
CS1 Efficiency:  η = 0.82 − 0.002 × ṁ
CS2 Efficiency:  η = 0.78 − 0.002 × ṁ
```

A typical Indian CGD booster station uses 500–2000 kW of electrical power. The simulator tracks this as a monitored quantity logged to the dataset.

#### Control — How the Compressor is Automatically Controlled

Each compressor is connected to a **PID controller** (Proportional-Integral-Derivative — the standard feedback control algorithm used everywhere in process industry):

- **CS1 PID:** Measures pressure at delivery node D1 (target: **18 barg**). If D1 pressure is below 18 barg, the PID increases CS1 compression ratio. If above 18 barg, it reduces ratio. This is exactly how a real booster station's capacity control works.
- **CS2 PID:** Measures pressure at delivery node D3 (target: **14 barg**). Same logic.

The compressor ratio setpoint is communicated to the PLC via Modbus holding register address 100 (CS1) and 101 (CS2), scaled as integer × 1000 (so ratio 1.35 is stored as integer 1350).

#### Alarm Thresholds

| Alarm | CS1 | CS2 | Action |
|-------|-----|-----|--------|
| High ratio alarm | Ratio ≥ 1.50 | Ratio ≥ 1.45 | Coil cs1_alarm / cs2_alarm set to TRUE. Logged to dataset. |
| Emergency trip | Ratio ≥ 1.60 (sustained) | Ratio ≥ 1.55 (sustained) | Emergency shutdown coil activated. Compressor stops. |

*Note: These ratios are lower than the European GasLib original (1.75/1.55) because Indian CGD booster stations operate at lower differential pressure — a CGS already reduces from 100 barg to 26 barg before the gas enters the steel grid, so the booster only needs to compensate for line losses of 3–5 bar.*

#### What Happens if a Compressor Fails or is Attacked

| Scenario | Effect on Network |
|----------|-------------------|
| **CS1 trips (emergency shutdown)** | Downstream pressure from CS1 immediately falls. J2, J3, J4 pressures drop. PRS1 outlet may fall below setpoint — D1 and D2 go undersupplied. CS2 must work harder. EKF residual at D1 spikes. CUSUM alarm fires within ~30 seconds. |
| **CS2 trips** | J5 pressure drops. PRS2 cannot maintain 14 barg output. D3 and D4 undersupplied. STO withdrawal may be triggered automatically if J5 falls below 20 barg. |
| **CS1 ratio manipulated by attacker (Attack A2)** | Attacker writes a falsely high ratio command to Modbus register 100. CS1 over-compresses: J2 pressure rises above 26 barg. Safety relief may activate. Physical damage risk in real system. CUSUM alarm on pressure-exceeding-design-limit. |
| **CS1 bypassed (valve bypass opened)** | Gas flows around the compressor. No pressure boost. Equivalent to CS1 trip but with no alarm — stealthy attack. |
| **Efficiency degradation (partial failure)** | Compressor still runs but provides less boost per kW consumed. Power draw increases. Pressure targets not met. EKF residual grows slowly over days — detectable as trend anomaly. |

---

### 3.4 Pressure Regulating Stations (PRS) — Pressure Reducers

**Nodes: PRS1 (Node 10) and PRS2 (Node 13)**

#### What They Are in Indian CGD

In a real Indian CGD network, a **Pressure Regulating Station** is called a **District Regulating Station (DRS)**. A DRS receives gas at steel grid pressure (14–26 barg) and reduces it to medium pressure (1–4 barg) for onward distribution through PE (polyethylene) pipelines to Service Regulators, which then supply domestic consumers.

However, in this simulator, the PRS nodes represent **intermediate pressure regulation points** within the steel grid itself — they reduce the steel grid pressure from ~22–24 barg to a lower pressure suitable for industrial and large commercial consumers who connect directly to the steel grid at regulated pressure.

- **PRS1** sits on the side branch (J2 → J6 → PRS1) and supplies industrial consumers D1 and D2 at a setpoint of **18 barg**. This represents a large industrial MRS (Metering and Regulating Station) type connection.
- **PRS2** sits downstream of CS2 (J5 → PRS2) and supplies consumers D3 and D4 at **14 barg**. This represents the minimum delivery pressure to DRS inlets as per PNGRB T4S.

#### How a PRS Works — Step by Step

A PRS is essentially an automatic pressure control valve with a spring-loaded diaphragm actuator. When inlet pressure is higher than the setpoint:
1. The diaphragm actuator pushes against the valve stem.
2. The valve partially closes.
3. Gas is throttled — its flow is restricted, creating a pressure drop.
4. The downstream pressure stabilises at the setpoint.

When inlet pressure falls below setpoint (e.g., during low-supply periods):
1. The valve opens fully.
2. It can no longer maintain the setpoint — this is called **pressure droop**.
3. Downstream pressure falls with inlet pressure.

In the simulator, this is modelled as a **first-order lag response** with time constant τ = 5 seconds and a deadband of ±0.3 bar:

```
PRS throttle position changes at rate: (target_position − actual_position) / τ

τ = 5 seconds (typical pneumatic actuator response time)
Deadband = ±0.3 bar (valve does not move for small deviations — prevents hunting)
```

#### SCADA Monitoring

The PRS stations are monitored via Modbus coils:
- **Coil 5 (prs1_active):** Set TRUE when PRS1 is actively regulating (outlet > setpoint). Indicates PRS1 is receiving adequate inlet pressure.
- **Coil 6 (prs2_active):** Same for PRS2.
- **Registers 105–106:** PRS setpoint commands (bar × 100 as integer). The control system can remotely adjust setpoints via FC06 Modbus write.

#### Indian CGD Parameters for PRS

| Parameter | PRS1 (DRS1-equivalent) | PRS2 (DRS2-equivalent) |
|-----------|------------------------|------------------------|
| Inlet pressure (normal) | 20–24 barg | 20–22 barg |
| Outlet setpoint | **18 barg** | **14 barg** |
| Minimum inlet for regulation | 19 barg | 15 barg |
| Flow range | 0–500 SCMD | 0–800 SCMD |
| Response time constant τ | 5 seconds | 5 seconds |
| Deadband | ±0.3 bar | ±0.3 bar |
| Slam-shut valve trip | <12 barg outlet or >26 barg inlet | <10 barg outlet or >26 barg inlet |

*These values reflect PNGRB T4S requirements: the slam-shut valve (SSV) is a mandatory safety device at all DRS stations that automatically closes if outlet pressure falls below a minimum safe value or inlet pressure exceeds the design limit.*

#### What Happens if a PRS Fails or is Attacked

| Scenario | Effect on Network |
|----------|-------------------|
| **PRS1 valve stuck open** | Gas flows at full inlet pressure to D1 and D2. If inlet is 22 barg, D1 receives 22 barg instead of 18 barg. Over-pressure risk to downstream equipment. SCADA prs1_active coil remains TRUE but outlet pressure exceeds setpoint — detectable as positive pressure residual. |
| **PRS1 valve stuck closed** | No gas delivered to D1 and D2. Those demand nodes starved. CS1 inlet/outlet flow imbalance. EKF detects zero flow on E10 and E11 while predicting non-zero. CUSUM alarm on flow residual. |
| **PRS2 setpoint manipulated (Attack — FC06 write)** | Attacker changes Modbus register 106 from 1400 (14 bar) to 800 (8 bar). PRS2 chokes down too much. D3 and D4 undersupplied severely. CS2 alarm may not fire (problem is in PRS, not compressor). Stealthy attack detectable via protocol-layer feature: unusual FC06 write to register 106. |
| **PRS inlet pressure too low** | PRS cannot maintain setpoint. Outlet droop proportional to shortfall. EKF residual grows. CUSUM may eventually alarm. Control logic tries to increase upstream compressor ratios to compensate. |

---

### 3.5 Storage Cavern — The Buffer Tank

**Node: STO (Node 12)**

#### What It Is in Indian CGD Context

In large-scale Indian CGD operations, gas storage is used to handle peak demand (e.g., morning cooking hours, winter heating peaks). In practice, IGL and MGL use **line pack** (the gas stored in the pressure of the pipe itself) as short-term buffer, and access to GAIL's underground storage at Konkan (Maharashtra) as strategic reserve. For a localised CGD steel grid, operators use **high-pressure gas holders** or **line pack management** as the buffer.

In this simulator, **STO** represents a **high-pressure buffer storage vessel** — a large steel pressure vessel or a small underground cavern connected to the grid at two points: the injection valve E14 (to fill storage) and the withdrawal valve E15 (to release gas). It can store gas at pressures between 16 and 28 barg and tracks a **fill fraction** (inventory) between 0 and 1.

#### How Storage Works — The Logic

The storage operates **automatically** based on network pressure conditions:

**Injection Mode** (filling storage):
- Condition: Pressure at J7 > **24 barg** (more gas arriving than being consumed — excess needs somewhere to go)
- Action: Valve E14 opens. Gas flows from J7 into STO. J7 pressure stabilises.
- Modbus Coil 3 (sto_inject_active) set to TRUE.
- Injection flow rate calculated by Weymouth equation using pressure differential J7 → STO.

**Withdrawal Mode** (releasing stored gas):
- Condition: Pressure at J5 < **20 barg** (demand exceeds supply — gas from storage needed)
- Action: Valve E15 opens. Gas flows from STO into J5, boosting pressure.
- Modbus Coil 4 (sto_withdraw_active) set to TRUE.
- Withdrawal rate limited by STO inventory (cannot exceed what's stored).

**Neutral Mode** (neither injecting nor withdrawing):
- Condition: J7 pressure 20–24 barg and J5 pressure 20–24 barg.
- Both valves closed. STO inventory held constant.

This logic creates a **storage loop** in the network topology: J7 → E14 → STO → E15 → J5. When both valves are open simultaneously (an abnormal condition), gas could circulate through this loop — this is prevented by logic that ensures only one valve can be fully open at a time.

#### Indian CGD Storage Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Storage capacity | 5,000 SCMD equivalent | Represents ~6 hours of peak demand |
| Operating pressure range | 16–28 barg | Within steel grid design pressure |
| Injection trigger | J7 pressure > 24 barg | Protects network from over-pressure |
| Withdrawal trigger | J5 pressure < 20 barg | Ensures minimum delivery pressure |
| Max injection rate | 200 SCMD | Limited by valve size |
| Max withdrawal rate | 300 SCMD | Higher to ensure emergency coverage |
| Inventory tracking | Fill fraction 0.0 to 1.0 | 0 = empty, 1 = full |

#### What Happens if Storage Fails or is Attacked

| Scenario | Effect on Network |
|----------|-------------------|
| **Storage empty, high demand occurs** | Withdrawal valve opens but no gas comes out. J5 pressure continues to fall. CS2 alarm triggers. PRS2 cannot maintain setpoint. D3 and D4 undersupplied. Emergency shutdown may activate. |
| **Storage injection valve E14 stuck open** | Gas continuously drains from J7 into storage regardless of network pressure. J7 pressure falls. D6 supply weakens. S2 source outlet depleted faster. Detectable as continuous flow on E14 when network pressure is normal. |
| **Storage withdrawal valve E15 stuck open** | Gas continuously flows from STO to J5 regardless of network pressure. J5 pressure rises above normal. CS2 may throttle back. STO inventory depletes unexpectedly. CUSUM alarm on J5 pressure being abnormally high without corresponding high demand. |
| **Attack — manipulate both STO valves** | Opens E14 and E15 simultaneously. Gas circulates J7 → STO → J5 without serving consumers. Network pressure oscillates. Kirchhoff residual at J5 and J7 both anomalous. Physics-layer EKF detects unusual flow patterns. |
| **STO inventory reaches zero during withdrawal** | Withdrawal valve automatically closes (inventory guard). If J5 pressure still low, emergency shutdown activates after timeout. |

---

### 3.6 Control Valves — The On/Off Switches

**Valves: E8 (J2 → J6), E14 (J7 → STO), E15 (STO → J5)**

#### What They Are

Control valves are motorised on/off valves — in real Indian CGD networks, these are typically **ball valves** or **gate valves** with electric or pneumatic actuators. They are controlled remotely via the SCADA system through the PLC.

In the simulator, valves are modelled as **binary** (fully open or fully closed) for simplicity. In a real system, they may be **proportional** (0–100% open), but the binary model captures the essential switching behaviour.

Each valve has:
- A **physical position** (open or closed) affecting gas flow in the MATLAB physics model
- A **command register** in the PLC Modbus map (addresses 102, 103, 104)
- A **status coil** indicating current state

#### Valve E8 — Side Branch Isolation

**Location:** Between J2 and J6. Controls whether gas can flow from the main trunk into the side branch that feeds PRS1 → D1 and D2.

**Opening logic:** Opens when J6 pressure falls below **20 barg** (D1/D2 consumers need gas)  
**Closing logic:** Closes when J6 pressure exceeds **26 barg** (over-pressure protection)  
**Modbus register:** Address 102 (value 1000 = open, 0 = closed)

When E8 is closed: D1 and D2 are completely cut off from supply. PRS1 cannot regulate. This is used for **planned maintenance isolation** of the side branch.

#### Valve E14 — Storage Injection

**Location:** Between J7 and STO. Controls filling of storage.  
**Modbus coil:** Coil 3 (sto_inject_active)

#### Valve E15 — Storage Withdrawal

**Location:** Between STO and J5. Controls release from storage.  
**Modbus coil:** Coil 4 (sto_withdraw_active)

#### What Happens if Valves Fail or are Attacked

| Scenario | Effect |
|----------|--------|
| **E8 forced closed by attacker (Attack A3)** | D1 and D2 immediately lose supply. Customers affected. No physical alarm unless pressure sensors at D1/D2 are monitored — attack is stealthy at the protocol level but visible in physics residuals. |
| **E8 cannot open (mechanical failure)** | Side branch isolated. Same effect as intentional closure but without a command record — harder to diagnose. |
| **E14 stuck open** | Continuous gas loss from J7 into STO. Detectable by flow meter on E14 showing constant injection even when J7 pressure is normal. |
| **E15 stuck open** | Continuous supply from STO to J5, depleting storage. Detectable by abnormally high J5 flow without corresponding demand. |
| **Valve command replay attack (Attack A7 — latency)** | Attacker replays old valve commands. Valve toggles to a previous state. Network topology effectively changes without operators knowing. Physics residuals spike as pressure distribution changes. |

---

### 3.7 Demand Nodes — Where Gas is Delivered

**Nodes: D1 (15), D2 (16), D3 (17), D4 (18), D5 (19), D6 (20)**

#### What They Are

Demand nodes represent the **withdrawal points** from the steel grid — the locations where gas leaves the grid and is consumed or further distributed. In real Indian CGD:

| Node | Indian CGD Equivalent | Typical Consumer Type |
|------|----------------------|----------------------|
| D1 | Large industrial MRS, fed by PRS1 | Steel plant, cement factory, ceramic kiln |
| D2 | Commercial MRS, fed by PRS1 | Hotel, hospital, commercial complex |
| D3 | Large industrial MRS, fed by PRS2 | Glass factory, chemical plant |
| D4 | CNG mother station, fed by PRS2 | CNG filling station receiving high-pressure gas |
| D5 | Direct high-pressure industrial tap | Very large industrial plant with own pressure regulation |
| D6 | Medium-pressure commercial zone | Small industrial cluster, institutional campus |

#### How Demand is Modelled

Each demand node has a **withdrawal flow profile** — the rate at which gas is drawn out of the network. This follows a **diurnal pattern** (daily cycle):
- High demand: 6–10 AM (morning peak), 6–9 PM (evening peak) — cooking, industrial shifts
- Low demand: 2–5 AM (overnight minimum)
- The profile also includes random noise to mimic real-world variation

The demand node is modelled as a **pressure sink** — it withdraws gas at a specified rate, and this withdrawal causes a pressure drop at that node. The compressor PID controllers respond by boosting pressure to compensate.

#### What Happens if a Demand Node Has Issues

| Scenario | Effect |
|----------|--------|
| **Sudden demand spike at D3** | CS2 PID detects D3 pressure falling. Increases CS2 ratio. If demand spike is too large, CS2 reaches alarm threshold. PRS2 may not maintain 14 barg. Emergency shutdown possible. |
| **Demand drops to zero at D1 (industrial shutdown)** | Gas backs up. J6 and PRS1 pressures rise. PRS1 partly closes (throttles). E8 may close if J6 exceeds 26 barg. |
| **Attack A4 — demand manipulation (false demand signal)** | Attacker spoofs demand readings. Control system thinks demand is higher than reality. CS1/CS2 over-compress. Network over-pressurises. Relief valves (simulated) activate. |
| **Attack A5 — pressure sensor spoof at D1** | Attacker falsifies D1 pressure reading to show 18 barg when actual is 12 barg. CS1 PID sees no problem and does not act. Real consumers undersupplied. Detectable only via physics residual: Weymouth prediction vs. sensor reading mismatch. |
| **Attack A6 — flow meter spoof at D3 feed** | Attacker falsifies flow measurement on E17 (PRS2 → D3). CS2 PID uses wrong feedback. Control becomes unstable or fails to compensate real demand. |

---

## 4. How Gas Flows Through the Network

### 4.1 Normal Operating Flow Path — Step by Step

Here is the journey of gas from entry point to consumer under normal, attack-free conditions:

```
STEP 1 — Gas enters at City Gate Stations
  S1 (CGS 1): Gas arrives from GAIL transmission line at ~50+ barg.
  CGS reduces to 24–26 barg and injects into steel grid.
  
  S2 (CGS 2): Second entry point, also at 24–26 barg.
  Provides geographic redundancy and supply diversity.

STEP 2 — Gas travels from S1 through pre-booster junction
  S1 → E1 → J1: Gas travels ~1 km of DN200 pipe.
  Pressure loss: ~0.1–0.2 bar from Darcy-Weisbach friction.
  J1 pressure: 23.8–25.8 barg.

STEP 3 — First Booster Station CS1 pressurises the gas
  J1 → E2 → CS1: Gas enters CS1 inlet at 23.5–25.5 barg.
  CS1 compresses gas to 24–26 barg outlet (ratio 1.1–1.2).
  CS1 → E3 → J2: Boosted gas arrives at the branch junction.

STEP 4 — J2 splits flow into main trunk AND side branch
  Main trunk: J2 → E4 → J3 → E5 → J4 → E6 → CS2
    (continuing eastward through the grid)
  Side branch: J2 → E8 (valve) → J6 → E9 → PRS1
    (diverting to DRS1 station for D1 and D2 consumers)

STEP 5 — PRS1 regulates pressure for side branch consumers
  PRS1 receives gas at 21–23 barg (after line losses in E8+E9).
  PRS1 reduces pressure to 18 barg setpoint.
  PRS1 → E10 → D1: Industrial consumers at 18 barg.
  PRS1 → E11 → D2: Commercial consumers at 18 barg.

STEP 6 — Second Booster CS2 and upper grid junction J7
  Simultaneously:
  - Main trunk gas: J4 → E6 → CS2 → E7 → J5
    CS2 boosts from 20 barg to 22 barg (ratio 1.1).
  - S2 injects: S2 → E13 → J7 at 22–24 barg.
  - Cross-link: J3 → E12 → J7 (diagonal supply to upper grid).
  J7 is the upper grid hub receiving gas from two or three paths.

STEP 7 — Storage may inject or withdraw at J7/J5
  If J7 pressure > 24 barg: E14 opens, gas stored in STO.
  If J5 pressure < 20 barg: E15 opens, STO supplements J5.
  
STEP 8 — Direct high-pressure industrial tap at D5
  J4 → E19 → D5: Large industrial consumer taps directly 
  from J4 at 20–22 barg without PRS regulation.
  Consumer has own pressure regulation on-site.

STEP 9 — Eastern distribution via PRS2
  J5 → E16 → PRS2: CS2 outlet at 20–22 barg.
  PRS2 reduces to 14 barg setpoint.
  PRS2 → E17 → D3: Industrial consumers at 14 barg.
  PRS2 → E18 → D4: CNG mother station at 14 barg.

STEP 10 — Upper grid direct supply at D6
  J7 → E20 → D6: Medium-pressure consumer at 21–22 barg.
  No PRS needed — J7 operates at appropriate pressure for D6.
```

### 4.2 Mass Balance at Every Junction (Kirchhoff's Law)

At every junction, at every moment in time, the following must hold:

```
Sum of all flows INTO the junction = Sum of all flows OUT of the junction

Example at J2:
  Flows in:  q_E3 (from CS1)
  Flows out: q_E4 (to J3) + q_E8 (to J6, if valve open)
  
  Balance: q_E3 = q_E4 + q_E8

Any violation of this balance means either:
  (a) A pipe is leaking, or
  (b) A sensor is lying (False Data Injection attack), or
  (c) A measurement error exists.

The EKF (Extended Kalman Filter) continuously checks these balances
and generates residuals when violations occur.
```

---

## 5. The Software Architecture

### 5.1 The 10 Software Modules

The simulator is organised into 10 software modules, each responsible for a specific part of the simulation. Think of each module as a department in a company — they all work together but each has a clear job.

```
┌─────────────────────────────────────────────────────┐
│              main_simulation.m                       │
│         (The Entry Point — starts everything)        │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│              config/simConfig.m                      │
│   (All parameters in one place — the rulebook)       │
└────────────────────┬────────────────────────────────┘
                     │ cfg struct passed to all modules
          ┌──────────┼──────────────────────┐
          ▼          ▼                      ▼
   [INIT PHASE]  [LOOP PHASE]          [EXPORT PHASE]
```

### 5.2 Module Descriptions

**MODULE 1 — config/**  
File: `simConfig.m`  
*The Single Source of Truth.* All 20-node network parameters, all Indian CGD pressure values, all pipe dimensions, all compressor curves, all timing parameters are defined here. Every other module reads from this `cfg` structure. Changing one number here changes it everywhere. This is critical for reproducibility.

**MODULE 2 — network/**  
Files: `initNetwork.m`, `updateFlow.m`, `updatePressure.m`, `updateTemperature.m`  
*The Physics Engine.* This module calculates what happens inside the pipes using the **Darcy-Weisbach equation** for friction pressure loss and mass-balance equations for junction pressures. It also calculates gas temperature changes (cooling as gas expands — the Joule-Thomson effect, important in high-pressure CGD).

The Darcy-Weisbach equation used here:

```
ΔP = f × (L/D) × (ρ × v²) / 2

where:
  ΔP = pressure drop along the pipe (Pa)
  f  = Darcy friction factor (calculated from pipe roughness ε and Reynolds number)
  L  = pipe length (m)  — Indian CGD: 500 m to 15 km per segment
  D  = pipe diameter (m) — Indian CGD: 0.05 to 0.30 m (DN50 to DN300)
  ρ  = gas density (kg/m³) — varies with pressure via Peng-Robinson EOS
  v  = gas velocity (m/s)
```

**MODULE 3 — equipment/**  
Files: `initCompressor.m`, `updateCompressor.m`, `initPRS.m`, `updatePRS.m`, `updateStorage.m`, `initValve.m`, `updateDensity.m`  
*All the Equipment.* Compressor head curves, PRS throttle response, storage injection/withdrawal logic, and the **Peng-Robinson Equation of State (PR-EOS)** for gas density calculation. PR-EOS is the industry standard for natural gas density at pipeline pressures.

**MODULE 4 — scada/**  
Files: `initEKF.m`, `updateEKF.m`, `initPLC.m`, `updatePLC.m`  
*The Measurement and Estimation System.* The **Extended Kalman Filter (EKF)** is a mathematical algorithm that estimates the true state of the gas network from noisy sensor measurements. It continuously predicts what the pressure and flow should be (based on physics), then corrects this prediction using the actual sensor readings. The residual (difference between prediction and measurement) is the anomaly detection signal.

The EKF has **40 state variables**: 20 nodal pressures + 20 edge flows. It runs at every simulation step (every 0.1 seconds at 10 Hz).

**MODULE 5 — control/**  
File: `updateControlLogic.m`  
*The Control Room Brain.* This is where the PID controllers for CS1 and CS2 run, valve interlock logic is enforced, emergency shutdown sequences are triggered, and safety limits are checked. It reads EKF-estimated states and PLC measurements, then sends commands back to the compressors and valves via the Modbus registers.

**MODULE 6 — attacks/**  
Files: `initAttackSchedule.m`, `applyAttackEffects.m`, `applySensorSpoof.m`, `detectIncidents.m`  
*The Cyber Threat Module.* This module implements 10 cyber attack scenarios (A1 through A10) mapped to MITRE ATT&CK for ICS tactics. Some attacks modify physics (e.g., manipulate source pressure), some corrupt sensor readings (False Data Injection), and some manipulate protocol-layer communications (e.g., Modbus replay attacks). The `detectIncidents.m` function implements CUSUM (Cumulative Sum) statistical process control to detect anomalies.

**MODULE 7 — profiling/**  
File: `generateSourceProfile.m`  
*The Demand Realism Module.* Generates realistic daily pressure and demand profiles for both S1 and S2 source nodes using statistical time-series modelling (AR(1) process with diurnal seasonal components). This ensures the training dataset captures real variation in gas supply and demand, not just flat constant values.

**MODULE 8 — logging/**  
Files: `initLogs.m`, `updateLogs.m`, `logEvent.m`, `initLogger.m`, `closeLogger.m`  
*The Data Recorder.* Pre-allocates large arrays for efficient logging of all 20-node variables at 10 Hz. Every time step, pressure, flow, temperature, density, compressor metrics, PRS status, storage inventory, EKF residuals, attack labels, and PLC snapshots are recorded. Also maintains an event log for alarms and incidents.

**MODULE 9 — export/**  
Files: `exportDataset.m`, `exportResults.m`  
*The Dataset Writer.* Converts the in-memory log arrays into CSV files. Produces the physics dataset (one row per simulation step, ~114 columns) and the protocol dataset (150 columns including raw Modbus integer register values).

**MODULE 10 — middleware/**  
Files: `gateway.py`, `data_logger.py`, `diagnostic.py`, `sendToGateway.m`, `receiveFromGateway.m`, `initGatewayState.m`, `config.yaml`  
*The Communication Bridge.* Handles all communication between MATLAB and the CODESYS SoftPLC. The Python gateway receives physics state from MATLAB via UDP, scales it to integer Modbus registers, writes to the PLC via Modbus TCP, reads back actuator commands, and sends them back to MATLAB. This creates real-world protocol artefacts in the dataset.

---

## 6. The SCADA and Control System

### 6.1 The Extended Kalman Filter (EKF)

The EKF is the mathematical core of the SCADA estimation system. Its job is to answer the question: *"Given noisy sensor readings, what is the most likely true state of the gas network right now?"*

**Why this matters for IDS:** When an attacker falsifies a sensor reading (False Data Injection), the EKF's prediction (based on physics) disagrees with the corrupted sensor reading. This disagreement — called the **innovation residual** — is the primary anomaly signal.

```
EKF State Vector (40 dimensions):
  x = [p_S1, p_J1, p_CS1, ..., p_D6,   ← 20 nodal pressures (barg)
       q_E1, q_E2, ..., q_E20]           ← 20 edge flows (SCMD)

EKF Prediction Step (physics model):
  x_predicted = f(x_previous, control_inputs, Indian_CGD_equations)

EKF Update Step (measurement correction):
  residual = measurement_actual − measurement_predicted
  x_corrected = x_predicted + K × residual

where K = Kalman Gain (optimal weighting between model and measurement)

Anomaly signal: Large residuals → physics and sensor disagree → investigate
```

The EKF is monitored at 9 critical nodes: S1, J2, J3, J4, J5, PRS1, PRS2, D1, D3. These are the nodes where pressure is most sensitive to attacks.

### 6.2 The CUSUM Alarm System

CUSUM (Cumulative Sum) is a statistical method for detecting when a process has shifted away from its normal behaviour. Unlike simple threshold alarms (which only trigger when a single reading is too high or too low), CUSUM accumulates small deviations over time and alarms when the accumulated deviation exceeds a threshold. This makes it effective for **slow and stealthy attacks** that stay below point-in-time thresholds.

```
CUSUM for pressure anomaly at node i:
  S_high(t) = max(0, S_high(t-1) + (residual(t) − k))
  S_low(t)  = min(0, S_low(t-1) + (residual(t) + k))
  
  Alarm if S_high(t) > h  OR  |S_low(t)| > h
  
where:
  k = slack (allowance for normal variation)
  h = alarm threshold
```

For the Indian CGD simulator, CUSUM parameters are set based on normal operating variance of pressure residuals (typically ±0.3 bar) and the minimum detectable shift (1.0 bar over 30 seconds or more).

---

## 7. The Communication Stack — How Computers Talk to Each Other

### 7.1 The Three-Layer Communication Architecture

```
┌─────────────────────────────────────┐
│   LAYER 1: MATLAB Physics Engine    │
│   (Runs on: any PC with MATLAB)     │
│   Rate: 10 Hz (every 100 ms)        │
│   Output: 61 float64 values (UDP)   │
└──────────────┬──────────────────────┘
               │ UDP port 5005
               │ (488 bytes per packet: 61 × float64)
               ▼
┌─────────────────────────────────────┐
│   LAYER 2: Python Gateway           │
│   File: gateway.py                  │
│   Converts float64 → INT registers  │
│   Writes to PLC via Modbus FC16     │
│   Reads from PLC via Modbus FC3/FC1 │
│   Sends INT back to MATLAB via UDP  │
└──────────────┬──────────────────────┘
               │ Modbus TCP port 1502
               │ (Standard industrial protocol)
               ▼
┌─────────────────────────────────────┐
│   LAYER 3: CODESYS SoftPLC          │
│   Address: 127.0.0.1:1502, Unit=1   │
│   70 Holding Registers (INT)         │
│   7 Coils (Bool)                    │
│   Runs PID control logic            │
└─────────────────────────────────────┘
```

### 7.2 What Each Communication Step Does

**MATLAB → Python (UDP, every 100 ms):**  
MATLAB sends 61 engineering values: 20 nodal pressures (in barg), 20 edge flows (in SCMD), 20 temperatures (in K), and 1 demand scalar. Python receives these as 64-bit floating point numbers.

**Python → PLC (Modbus TCP FC16, Write Multiple Registers):**  
Python scales the float values to integers using the Indian CGD register map below, then writes them to 61 holding registers in the CODESYS PLC in a single FC16 (Function Code 16) write transaction. The PLC stores these as INT16 values.

**PLC → Python (Modbus TCP FC3/FC1, Read Registers/Coils):**  
Python reads back 9 actuator command registers (addresses 100–108) and 7 status coils. These are the PLC's outputs — its decisions about compressor ratios, valve positions, and alarm states.

**Python → MATLAB (UDP, every 100 ms):**  
Python sends the actuator commands back to MATLAB so the physics simulation can update accordingly (e.g., if the PLC has changed CS1 ratio to 1.3, MATLAB applies that ratio in the next physics step).

### 7.3 Modbus Register Map — Indian CGD Edition

All register values use integer scaling to fit into INT16 format (range: −32768 to +32767).

**Sensor Input Registers (MATLAB → PLC, via Python)**

| Register Address | Signal | Scaling | Example: 22.5 barg → |
|-----------------|--------|---------|----------------------|
| 0–19 | Nodal pressures p_S1 to p_D6 | bar × 100 → INT | 22.5 bar → 2250 |
| 20–39 | Edge flows q_E1 to q_E20 | SCMD × 10 → INT | 150.3 SCMD → 1503 |
| 40–59 | Node temperatures T_S1 to T_D6 | K × 10 → INT | 308.15 K → 3082 |
| 60 | Demand scalar | × 1000 → INT | 0.85 → 850 |
| 61–99 | RESERVED | — | — |

**Actuator Output Registers (PLC → Python → MATLAB)**

| Register Address | Signal | Scaling | Example: Ratio 1.35 → |
|-----------------|--------|---------|----------------------|
| 100 | CS1 compression ratio command | ratio × 1000 → INT | 1.35 → 1350 |
| 101 | CS2 compression ratio command | ratio × 1000 → INT | 1.25 → 1250 |
| 102 | Valve E8 command | 1000 = open, 0 = closed | open → 1000 |
| 103 | Valve E14 command (STO inject) | 1000 = open, 0 = closed | closed → 0 |
| 104 | Valve E15 command (STO withdraw) | 1000 = open, 0 = closed | closed → 0 |
| 105 | PRS1 setpoint command | bar × 100 → INT | 18 bar → 1800 |
| 106 | PRS2 setpoint command | bar × 100 → INT | 14 bar → 1400 |
| 107 | CS1 power draw | kW × 10 → INT | 850 kW → 8500 |
| 108 | CS2 power draw | kW × 10 → INT | 620 kW → 6200 |

**Status Coils (PLC → Python → MATLAB)**

| Coil Address | Signal | Normal State | Alarm State |
|-------------|--------|-------------|-------------|
| Coil 0 | emergency_shutdown | FALSE | TRUE — all equipment stops |
| Coil 1 | cs1_alarm | FALSE | TRUE — CS1 ratio ≥ 1.50 |
| Coil 2 | cs2_alarm | FALSE | TRUE — CS2 ratio ≥ 1.45 |
| Coil 3 | sto_inject_active | FALSE | TRUE — storage being filled |
| Coil 4 | sto_withdraw_active | FALSE | TRUE — storage releasing gas |
| Coil 5 | prs1_active | TRUE (normal) | FALSE — PRS1 inlet too low |
| Coil 6 | prs2_active | TRUE (normal) | FALSE — PRS2 inlet too low |

### 7.4 Protocol Authenticity — Why CODESYS Matters

A pure software simulation could simply write values directly from MATLAB to a Python dictionary. But this would produce a dataset that is **physically inauthentic** in two important ways:

1. **Timing jitter is absent.** In a real Modbus TCP polling cycle, there is always variation of ±2–8 milliseconds in when registers are sampled vs. when they are reported. This jitter is a feature of real SCADA data — its absence in synthetic data is detectable by trained ML models.

2. **Quantisation noise is absent.** Converting 22.543 barg to integer 2254 and back to 22.54 barg introduces a quantisation error of 0.003 barg. This noise is predictable and physical — its absence in synthetic data is unrealistic.

By routing all data through a real CODESYS SoftPLC on a real Modbus TCP connection, both timing jitter and quantisation noise are naturally introduced. The protocol-layer dataset (150-column CSV) captures both — making it a more credible training dataset for industrial IDS systems.

---

## 8. Indian CGD Parameters — Full Specification Table

### 8.1 Physical Parameters (Replacing European GasLib Values)

| Parameter | Previous Value (GasLib / European) | **Indian CGD Value (PNGRB T4S)** | Standard Reference |
|-----------|-----------------------------------|-----------------------------------|--------------------|
| Steel grid inlet pressure | 40–100 bar | **24–26 barg** | PNGRB T4S, CGD pressure cascade |
| Steel grid outlet pressure | 10–60 bar | **14–18 barg** | PNGRB T4S minimum DRS delivery |
| Maximum design pressure | 100 bar | **26 barg** | PNGRB T4S primary network limit |
| Specific gravity of gas | 0.60 | **0.57** | GAIL/ONGC domestic supply spec |
| Gas compressibility Z-factor | 0.88 at 60 bar | **0.95 at 20 bar, 35°C** | Peng-Robinson EOS |
| Operating temperature range | 5–50°C | **20–45°C** (no sub-zero in Indian conditions) | BIS IS 15663 |
| Main trunk pipe diameter | DN500–600 mm | **DN150–300 mm** | IS 3589, IS 1239 Part 1 |
| Branch pipe diameter | DN200–300 mm | **DN50–150 mm** | IS 1239 Part 1 |
| Pipe material | Generic European steel | **API 5L Grade B / IS 3589 Grade 410** | PNGRB T4S Annexure I |
| Pipe roughness ε | 0.01–0.05 mm | **0.045 mm** (commercial steel, new pipe) | IS 3589 |
| Typical pipe segment length | 1–50 km | **0.5–15 km** (urban CGD grid segments) | IGL/MGL network geometry |
| Nodal volume (junction model) | 6 m³ | **6 m³** (no change — physically reasonable for manifold) | Lumped capacitance model |
| Speed of sound in gas | 350 m/s | **340 m/s** (Indian NG at 20 bar, 35°C) | PR-EOS derived |

### 8.2 Compressor Parameters (Indian CGD Booster Stations)

| Parameter | CS1 (Primary Booster) | CS2 (Secondary Booster) | Notes |
|-----------|----------------------|------------------------|-------|
| Inlet pressure (normal) | 23–25 barg | 20–22 barg | After line losses from upstream |
| Outlet pressure (normal) | 24–26 barg | 21–23 barg | Boosted for distribution |
| Compression ratio range | 1.05–1.50 | 1.05–1.45 | Lower than European because CGS already reduces pressure |
| High ratio alarm threshold | **1.50** | **1.45** | Adapted for Indian operating range |
| Emergency trip threshold | **1.60** | **1.55** | Safety limit |
| Head curve | H = 800 − 0.8ṁ − 0.002ṁ² | H = 500 − 0.5ṁ − 0.001ṁ² | Engineering head in metres |
| Efficiency | η = 0.82 − 0.002ṁ | η = 0.78 − 0.002ṁ | Centrifugal compressor curve |
| PID control target | D1 pressure = **18 barg** | D3 pressure = **14 barg** | Adapted from 30/25 bar to 18/14 bar |
| Typical power draw | 500–1500 kW | 400–1200 kW | Electric motor drive, common in Indian CGD |

### 8.3 Pressure Regulating Station Parameters

| Parameter | PRS1 (DRS1-equivalent) | PRS2 (DRS2-equivalent) |
|-----------|------------------------|------------------------|
| Inlet pressure | 21–24 barg | 20–22 barg |
| Outlet setpoint | **18 barg** | **14 barg** |
| Min inlet for regulation | 19 barg | 15 barg |
| Response time constant τ | 5 s | 5 s |
| Deadband | ±0.3 bar | ±0.3 bar |
| Slam-shut valve (SSV) trip — low | <12 barg outlet | <10 barg outlet |
| SSV trip — high | >26 barg inlet | >26 barg inlet |
| Creep relief valve | Opens at 19.5 barg (PRS1 outlet) | Opens at 14.5 barg (PRS2 outlet) |

### 8.4 Register Scaling Summary (Indian CGD Edition)

| Signal Type | Physical Unit | Scaling Factor | INT Range | Accuracy Resolution |
|------------|--------------|----------------|-----------|---------------------|
| Pressure | barg | × 100 | 1400–2600 (14–26 barg) | 0.01 bar |
| Flow | SCMD | × 10 | 0–20000 SCMD | 0.1 SCMD |
| Temperature | K | × 10 | 2930–3180 (20°C–45°C) | 0.1 K |
| Compressor ratio | dimensionless | × 1000 | 1050–1600 | 0.001 |
| Valve position | % open | × 10 | 0–1000 | 0.1% |
| Storage inventory | fraction | × 1000 | 0–1000 | 0.001 |
| Power | kW | × 10 | 0–20000 kW | 0.1 kW |

### 8.5 Storage Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Operating pressure range | 16–28 barg | Within steel grid design pressure |
| Injection trigger (J7 pressure) | > 24 barg | Protects against over-pressure in upper grid |
| Withdrawal trigger (J5 pressure) | < 20 barg | Ensures minimum eastern distribution pressure |
| Injection flow rate | 0–200 SCMD | Limited by valve DN and pressure differential |
| Withdrawal flow rate | 0–300 SCMD | Higher than injection for emergency response |
| Inventory | 0.0 to 1.0 fraction | 0 = empty, 1 = 5000 SCMD equivalent |

---

## 9. What Happens When Components Fail or Are Attacked

This section provides a consolidated reference for **all 10 attack scenarios** (A1–A10) and major equipment failures, explaining what happens to the gas physics, the sensor readings, the protocol layer, and what signals are detectable.

### 9.1 Attack Taxonomy (MITRE ATT&CK for ICS)

| Attack ID | Name | Layer | What Is Affected | MITRE Tactic |
|-----------|------|-------|-----------------|--------------|
| A1 | Source pressure manipulation | Physics | S1 inlet pressure altered | Impair Process Control |
| A2 | Compressor ratio manipulation | Physics | CS1/CS2 setpoint altered | Impair Process Control |
| A3 | Valve forced closed | Physics + Protocol | E8 valve command | Impair Process Control |
| A4 | Demand manipulation | Physics | Demand withdrawal rate | Impair Process Control |
| A5 | Sensor spoof at D1 | Sensor/Protocol | D1 pressure reading | False Data Injection |
| A6 | Flow meter spoof at D3 | Sensor/Protocol | E17 flow reading | False Data Injection |
| A7 | Modbus command latency | Protocol | PLC polling delayed | Denial of Service |
| A8 | Pipeline leak simulation | Physics | E12 mass loss | Loss of Containment |
| A9 | Multi-stage cascading | Physics + Sensor | S1 + sensor spoof combo | Multi-Stage Attack |
| A10 | Replay attack | Protocol | Old register values replayed | Replay Attack |

### 9.2 What Detects Each Attack

| Attack ID | Physics Layer Signal | Protocol Layer Signal | Detection Difficulty |
|-----------|---------------------|----------------------|---------------------|
| A1 | EKF residual at J1/CS1. CUSUM on p_S1 trend. | S1 register drifts out of diurnal pattern. | Medium — requires temporal modelling |
| A2 | CS1 outlet/inlet ratio anomaly. J2 pressure spike or droop. | Register 100 changes without demand trigger. FC06 write detected. | Medium — ratio change visible in registers |
| A3 | J6 pressure drops to zero. D1/D2 flow stops. E8 flow register = 0. | Coil E8 command register 102 forced to 0. | Low — very visible in physics |
| A4 | Demand node withdrawal rate anomaly. CS1/CS2 respond with unexpected ratio changes. | Demand_scalar register 60 anomalous vs. time of day. | Medium — requires demand profile baseline |
| A5 | D1 EKF residual spikes. Weymouth prediction for E10 disagrees with sensor. Physics-consistent pressure shows ~12 barg but sensor shows 18 barg. | D1 register (address 15) inconsistent with E10 flow register. | **High** — requires physics residual to detect. Threshold-only alarm will miss it. |
| A6 | Flow balance at J5 broken. PRS2 control becomes erratic. | Flow register E17 (address ~37) shows suspicious step. | **High** — same as A5 |
| A7 | PLC responses delayed. EKF state estimate diverges during delay. | Modbus transaction timestamps show anomalous gaps. IRI (inter-request interval) exceeds normal 100 ms. | Medium — detectable in protocol timing features |
| A8 | Kirchhoff residual at J3 non-zero. Mass balance violated. EKF residual on q_E12. | No direct protocol signal — purely physics. | **High** — only EKF residual detects this |
| A9 | Multiple residuals spike simultaneously. S1 pressure + D3 sensor both anomalous. | Multiple register anomalies at same time. | **Very High** — most stealthy attack |
| A10 | Sensor readings freeze at previous values despite changing physical state. Register values stop evolving. | Protocol timestamps advance but register values do not change — impossible in real operation. | Medium — temporal pattern recognition |

### 9.3 Equipment Failure Scenarios (Non-Attack)

| Failure Scenario | First Indicator | Cascade Effect | Auto-Response |
|-----------------|-----------------|----------------|---------------|
| CS1 mechanical trip | cs1_alarm coil TRUE. J2 pressure falls. | D1/D2 undersupply. J3 pressure drops. CS2 alarm soon follows. | Emergency shutdown if ratio spikes. S2 + storage try to compensate. |
| PRS1 valve stuck closed | D1 and D2 flow = 0 on registers E10/E11. | CS1 sees reduced load — ratio drops. J2 pressure rises. E8 may close. | No auto-response — needs operator action. SCADA alarm on D1 pressure = 0. |
| PRS2 valve stuck open | D3/D4 receive inlet pressure (20+ barg instead of 14). | Over-pressure downstream of PRS2. Equipment damage risk. | SSV (slam-shut valve) trips at PRS2 if outlet exceeds 14.5 barg. |
| S1 feed interruption | J1 pressure falls. CS1 inlet pressure falls. | CS1 ratio rises trying to compensate. Alarm at CS1. If S2 has capacity, diagonal E12 compensates. | Storage withdrawal triggers if J5 < 20 barg. Emergency shutdown if CS1 trips. |
| STO empty during high demand | sto_withdraw_active TRUE but J5 still falling. | Eastern network (D3/D4) undersupply. CS2 alarm. | Emergency shutdown if PRS2 cannot maintain minimum. |
| Communication failure (Python gateway offline) | PLC receives no new register values. PLC holds last-known values (fail-safe). | PLC runs on stale physics data. Control decisions become wrong as network state diverges from stale registers. | PLC has 5-second timeout: if no new FC16 write received, triggers emergency shutdown coil. |

---

## 10. The Dataset It Produces

### 10.1 Physics Dataset (master_dataset.csv)

One row is written for every simulation step (every 100 ms at 10 Hz). A 24-hour simulation produces 864,000 rows.

**Column groups (approximately 114 columns total):**

| Column Group | Count | What It Contains | Unit |
|-------------|-------|-----------------|------|
| Timestamp | 1 | Date/time of this simulation step | ISO 8601 datetime |
| Nodal pressures | 20 | p_S1 through p_D6 — pressure at each of the 20 nodes | barg |
| Edge flows | 20 | q_E1 through q_E20 — mass flow in each of the 20 pipe segments | SCMD |
| Node temperatures | 20 | T_S1 through T_D6 — gas temperature at each node | °C |
| Node densities | 20 | rho_S1 through rho_D6 — gas density at each node | kg/m³ |
| CS1 metrics | 4 | cs1_ratio, cs1_power_kW, cs1_head_m, cs1_efficiency | various |
| CS2 metrics | 4 | Same for CS2 | various |
| PRS1 metrics | 2 | prs1_throttle_position, prs1_outlet_actual | % / barg |
| PRS2 metrics | 2 | Same for PRS2 | % / barg |
| Storage | 2 | sto_inventory_fraction, sto_flow_direction | 0–1 / +/- |
| EKF residuals | 2 | ekf_residual_pressure_norm, ekf_residual_flow_norm | dimensionless |
| Attack labels | 2 | attack_id (integer 0–10), mitre_id (string) | integer / string |
| PLC snapshot | 20 | plc_p_* and plc_q_* — what the PLC sees (may differ from truth during attack) | barg / SCMD |
| CUSUM states | 4 | cusum_high_p, cusum_low_p, cusum_high_q, cusum_low_q | dimensionless |

### 10.2 Protocol Dataset (pipeline_data_*.csv — 150 columns)

This dataset is produced by the Python data logger at the same 10 Hz rate. It contains everything the physics dataset contains, plus the raw integer Modbus register values. This is the **dual-layer dataset** — it contains both physics and protocol information simultaneously.

| Column Group | Count | What It Contains |
|-------------|-------|-----------------|
| Timestamps | 3 | timestamp_ms (milliseconds), datetime_utc, cycle_number |
| Physics engineering values | 61 | Same as physics dataset (pressures, flows, temperatures) |
| Actuator engineering values | 9 | CS1/CS2 ratios, valve positions, PRS setpoints |
| Coil states | 7 | All 7 boolean coil values |
| Sensor raw INT registers | 61 | Raw integer values from Modbus addresses 0–60 |
| Actuator raw INT registers | 9 | Raw integer values from Modbus addresses 100–108 |

The raw INT registers are the protocol-layer feature set. The difference between a raw INT value and its engineering conversion reveals quantisation noise. The timestamps between successive rows reveal polling jitter. Both are features that single-layer detectors miss.

### 10.3 Event Log (sim_events.log)

Plain text log with one line per event. Events include:
- Alarm activations (CS1 ratio alarm, CUSUM threshold breach)
- Attack start/stop timestamps
- Emergency shutdown triggers
- Storage mode changes (injection/withdrawal start/stop)
- PRS setpoint changes
- Valve state changes

### 10.4 Modbus Transaction Log (modbus_transactions_*.csv)

One row per Modbus TCP transaction (FC16 write or FC3/FC1 read). Columns:
- `timestamp_ms` — millisecond-precision transaction timestamp
- `function_code` — FC1, FC3, or FC16
- `start_address` — first register address in transaction
- `register_count` — how many registers in this transaction
- `direction` — "write" or "read"
- `duration_ms` — round-trip time for this transaction

This is the **pure protocol-layer feature dataset**. It contains no physics information — only timing and communication patterns. An IDS that uses only this dataset is a **protocol-only detector**. Combining it with physics features produces the hybrid detector that is the thesis's contribution.

---

## 11. Standards and Regulatory Compliance

### 11.1 Indian Standards Applied

| Standard | Full Name | Application in This Simulator |
|----------|-----------|-------------------------------|
| PNGRB T4S (2008, amended 2024) | Technical Standards and Specifications including Safety Standards for City or Local Natural Gas Distribution Networks | All operating pressures, pipe materials, slam-shut valve settings, design pressure limits |
| IS 3589 | Steel Tubes for Structural Purposes — Specification | Steel pipe grades, wall thicknesses, diameter selections |
| IS 1239 Part 1 | Mild Steel Tubes and Tubular Fittings | Branch pipe dimensions |
| IS 15663 | Natural Gas — Requirements for Compression, Gas Quality and Safety at Fuelling Stations | Gas composition and temperature requirements |
| BIS IS 2502 | Code of Practice for Bending and Forming of Steel Tubes | Relevant for pipe segment geometry assumptions |
| ASME B31.8 | Gas Transmission and Distribution Piping Systems | Referenced by PNGRB T4S; governs design pressure, material factors, testing requirements |
| API 5L | Specification for Line Pipe | Pipe material grade API 5L Gr. B as alternative to IS 3589 |
| API 1104 | Welding of Pipelines and Related Facilities | Welding quality standards for CGD steel grid |

### 11.2 Cybersecurity Standards Applied

| Standard | Application |
|----------|-------------|
| IEC 62443-3-3 | Security Levels and System Security Requirements — attack classification framework |
| NERC CIP-005 | Electronic Security Perimeters — defines the network boundaries modelled in the simulator |
| NIST SP 800-82 Rev 3 | Guide to ICS Security — Modbus exposure, SCADA architecture, IDS deployment guidance |
| MITRE ATT&CK for ICS | Attack scenario taxonomy — A1 through A10 mapped to MITRE tactics and techniques |
| IEC 62351 | Power Systems Management and Communication Security — extended to Modbus TCP authentication discussion |

### 11.3 Key Differences from GasLib/European Standard

The following table summarises every place where this simulator **departs from European GasLib norms** and adopts Indian PNGRB standards. This table is the justification for the "Indian CGD adaptation" novelty claim in the thesis:

| Parameter | GasLib (European) | This Simulator (Indian PNGRB) | Regulatory Basis |
|-----------|------------------|-------------------------------|-----------------|
| Network type | High-pressure transmission (40–100 bar) | Medium-pressure city distribution (14–26 barg) | PNGRB T4S — distinct network categories |
| Gas specific gravity | 0.60 (higher alkane content, North Sea gas) | 0.57 (methane-dominant Indian domestic gas) | GAIL/ONGC supply specification |
| Compressor control target | 30 bar (CS1), 25 bar (CS2) | 18 barg (CS1→D1), 14 barg (CS2→D3) | PNGRB T4S DRS outlet pressures |
| PRS setpoints | 30 bar, 25 bar | 18 barg, 14 barg | PNGRB T4S pressure cascade |
| Pipe diameters | DN200–DN600 | DN50–DN300 (IS 3589) | Urban CGD grid sizing |
| Compressibility Z | 0.88 at 60 bar | 0.95 at 20 bar | PR-EOS at Indian operating conditions |
| Temperature range | 5–50°C (includes Northern European winter) | 20–45°C (Indian climate, no sub-zero) | No winter sub-zero in Indian plains CGD |
| Pipe roughness | 0.01–0.05 mm | 0.045 mm (API 5L Gr. B) | PNGRB T4S material specification |
| Storage logic trigger | Inject >52 bar, withdraw <46 bar | Inject >24 barg, withdraw <20 barg | Scaled to Indian operating range |
| Emergency shutdown | CS1 ratio ≥ 1.75 | CS1 ratio ≥ 1.60 | Indian booster station operating range |

---

## Appendix A — Node and Edge Quick Reference

### Nodes
```
Index  ID    Type         Indian CGD Role                    Normal Pressure
1      S1    Source       City Gate Station 1 (CGS1)         24–26 barg
2      J1    Junction     Pre-booster grid junction          23–25 barg
3      CS1   Compressor   Booster Station 1 (CS1)            In: 23–25, Out: 24–26
4      J2    Junction     Branch junction — main/side split  23–25 barg
5      J3    Junction     Mid-grid junction                  22–24 barg
6      J4    Junction     Pre-CS2 junction                   21–23 barg
7      CS2   Compressor   Booster Station 2 (CS2)            In: 21–23, Out: 22–24
8      J5    Junction     Eastern distribution hub           20–22 barg
9      J6    Junction     Side branch junction               20–22 barg
10     PRS1  PRS (DRS)    District Regulating Station 1      In: 21–24, Out: 18 barg
11     J7    Junction     Upper grid hub / second CGS hub    22–24 barg
12     STO   Storage      High-pressure buffer storage       16–28 barg
13     PRS2  PRS (DRS)    District Regulating Station 2      In: 20–22, Out: 14 barg
14     S2    Source       City Gate Station 2 (CGS2)         22–24 barg
15     D1    Demand       Industrial MRS consumer (via PRS1) 18 barg
16     D2    Demand       Commercial MRS consumer (via PRS1) 18 barg
17     D3    Demand       Industrial MRS consumer (via PRS2) 14 barg
18     D4    Demand       CNG mother station (via PRS2)      14 barg
19     D5    Demand       Direct industrial tap (via J4)     20–22 barg
20     D6    Demand       Medium-pressure consumer (via J7)  21–22 barg
```

### Edges
```
ID   From  To    Type    Indian CGD Role
E1   S1    J1    Pipe    CGS1 outlet header
E2   J1    CS1   Pipe    Booster 1 inlet pipe
E3   CS1   J2    Pipe    Booster 1 outlet pipe
E4   J2    J3    Pipe    Main trunk westward
E5   J3    J4    Pipe    Main trunk continues
E6   J4    CS2   Pipe    Booster 2 inlet pipe
E7   CS2   J5    Pipe    Booster 2 outlet pipe
E8   J2    J6    VALVE   Side branch isolation valve
E9   J6    PRS1  Pipe    PRS1 inlet pipe
E10  PRS1  D1    Pipe    Industrial supply line 1
E11  PRS1  D2    Pipe    Commercial supply line 1
E12  J3    J7    Pipe    Cross-link diagonal pipe
E13  S2    J7    Pipe    CGS2 outlet header
E14  J7    STO   VALVE   Storage injection valve
E15  STO   J5    VALVE   Storage withdrawal valve
E16  J5    PRS2  Pipe    PRS2 inlet pipe
E17  PRS2  D3    Pipe    Industrial supply line 2
E18  PRS2  D4    Pipe    CNG station supply line
E19  J4    D5    Pipe    Direct industrial bypass
E20  J7    D6    Pipe    Medium-pressure supply
```

---

## Appendix B — Per-Step Simulation Execution Sequence

Every 100 milliseconds (10 Hz), the following operations execute in this exact order:

| Step | Function | Module | What It Does |
|------|----------|--------|-------------|
| 1 | `applyAttackEffects` | attacks/ | Modifies source pressures, actuator states, or demand based on active attack (A1–A4) |
| 2 | `updateFlow` | network/ | Calculates gas flow in all 20 edges using Darcy-Weisbach + hydrostatic correction |
| 3 | `updateStorage` | equipment/ | Checks J7/J5 pressures, opens/closes E14/E15 valves, updates STO inventory |
| 4 | `updatePressure` | network/ | Updates all 20 nodal pressures using mass balance and acoustic wave propagation |
| 5 | `updateCompressor ×2` | equipment/ | Applies CS1 then CS2 head curves, updates outlet pressures, checks alarm thresholds |
| 6 | `updatePRS ×2` | equipment/ | Applies PRS1 (18 barg) and PRS2 (14 barg) throttle response with τ = 5 s |
| 7 | `updateTemperature` | network/ | Calculates Joule-Thomson cooling and thermal mixing at each node |
| 8 | `updateDensity` | equipment/ | Runs Peng-Robinson EOS to calculate gas density at each node from P and T |
| 9 | `applySensorSpoof` | attacks/ | For attacks A5/A6: corrupts pressure or flow sensor values before PLC sees them |
| 10 | `sendToGateway` | middleware/ | Sends 61 engineering values to Python via UDP (488 bytes) |
| 11 | `receiveFromGateway` | middleware/ | Receives 9 actuator commands + 7 coil states back from Python/PLC |
| 12 | `updatePLC` | scada/ | Processes PLC sensor polling, applies latency buffer for A7 attack simulation |
| 13 | `updateEKF` | scada/ | Runs 40-state Extended Kalman Filter: predict → update → compute residuals |
| 14 | `updateControlLogic` | control/ | Runs PID for CS1/CS2, enforces valve interlocks, checks emergency shutdown logic |
| 15 | `updateLogs` | logging/ | Appends current full state to pre-allocated arrays (pressure, flow, temp, attack labels, etc.) |
| 16 | `detectIncidents` | attacks/ | Evaluates CUSUM alarms, logs any threshold breaches to event log |

---

*End of Document*

---

**Document prepared for:** Gas Pipeline CPS Simulator Research Project  
**Indian Regulatory Compliance:** PNGRB T4S (2008, Second Amendment 2024)  
**Target Publications:** IEEE Access / Computers & Security (Paper 1: Testbed + Dataset); IEEE Transactions on Industrial Informatics (Paper 2: Physics-Residual Hybrid IDS)  
**Version History:** v1.0 — GasLib European baseline; v2.0 — Indian CGD PNGRB T4S adaptation (March 2026)
