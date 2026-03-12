
# Gas Pipeline Cyber‑Physical Simulation — Extended Requirements

## Introduction

This document extends the original simulation requirements by incorporating **physics realism improvements, expanded network topology, cyber‑layer enhancements, data quality realism, and a hybrid MATLAB–PLC architecture**.

The goal is to transform the MATLAB gas pipeline simulation into a **high‑fidelity cyber‑physical testbed** capable of generating realistic operational data and advanced cyber‑attack scenarios for anomaly detection and security research.

This document builds upon the baseline requirements defined in the original requirements document and introduces additional system components and requirements.

(Original requirements referenced from the base document.)

---

# System Architecture

The modified architecture separates the simulation into **physical process, control system, communication layer, and attack environment**.

```
MATLAB Physical Plant
        │
        │ UDP
        ▼
Python Communication Gateway
        │
        │ Modbus/TCP
        ▼
CODESYS SoftPLC
        │
        │ OPC / Web / API
        ▼
SCADA / HMI Dashboard
```

Attack modules may intercept communication between layers.

---

# Core System Components

## 1. Physical Plant Model (MATLAB)

Role:
Simulates the physical behaviour of the gas pipeline network including pressure, flow, compressor behaviour, leaks, and gas dynamics.

Responsibilities:

- Execute physical pipeline simulation
- Calculate pressure, temperature, and mass flow
- Implement gas dynamics and network topology
- Send simulated sensor values to control systems
- Receive actuator commands from PLC

Communication:

- UDP or OPC‑UA to middleware
- MATLAB OPC Toolbox or TCP/UDP sockets

Key files:

- runSimulation.m
- updatePipelinePhysics.m
- updateCompressorStation.m
- computeFDIVector.m

---

## 2. SoftPLC (CODESYS)

Role:
Implements industrial control logic identical to a real pipeline PLC system.

Responsibilities:

- Run safety logic and control loops
- Process sensor inputs
- Generate actuator outputs
- Implement compressor and valve control

Logic Languages:

- Structured Text (ST)
- Ladder Logic (LD)
- Function Block Diagram (FBD)

Deployment:

- CODESYS Control Win runtime
- Raspberry Pi runtime (optional)

Communication:

- Modbus/TCP
- OPC‑UA

---

## 3. Communication Gateway (Python)

Role:
Acts as middleware translating data between MATLAB simulation and PLC registers.

Responsibilities:

- Poll PLC registers via Modbus
- Convert register data into engineering values
- Forward commands between MATLAB and PLC
- Provide logging and buffering

Libraries:

- pymodbus
- asyncio / sockets
- opcua (optional)

Data flow:

MATLAB → UDP → Python → Modbus/TCP → PLC

PLC → Modbus/TCP → Python → UDP → MATLAB

---

## 4. Human Machine Interface / SCADA

Role:
Provides operator visibility and monitoring capability.

Implementation options:

- CODESYS visualization
- Python Flask dashboard
- React / Web dashboard

Displays:

- pressures
- flows
- compressor state
- alarms
- attack indicators

---

## 5. Attack Module (False Actor)

Role:
Implements cyberattack scenarios against the cyber‑physical system.

Capabilities:

- Sensor spoofing
- Replay attacks
- False data injection
- Latency and packet attacks

Attacks operate as **Man‑in‑the‑Middle agents** between system components.

---

## 6. Configuration and Logging

Role:
Ensures reproducibility and structured experiment configuration.

Files:

config.yaml
attack_config.yaml

Responsibilities:

- map PLC registers to MATLAB variables
- define attack schedules
- configure simulation parameters
- store experiment metadata

---

# Extended Physical Model Requirements

## Multi‑Compressor Stations

The simulation SHALL support multiple compressors operating in series or parallel.

Capabilities:

- load sharing
- surge protection
- staged pressure boosting

Implementation:

updateCompressorStation.m

---

## Line Pack Modelling

The pipeline SHALL model **gas stored inside pipe volume**.

Requirements:

- pipe segments store gas mass
- pressure propagation delay
- realistic transient behaviour

This introduces a **state variable for each pipe segment**.

---

## Gas Equation of State

The simulation SHALL support **Peng‑Robinson equation of state** for gas compressibility.

Benefits:

- realistic density calculation
- nonlinear pressure behaviour
- accurate high‑pressure modelling

---

## Elevation Profile

Nodes SHALL support elevation values.

Pressure equation SHALL include hydrostatic component:

ρgh

This creates realistic directional flow effects.

---

# Network Topology Requirements

## Expanded Network Size

The simulation SHALL support networks with **15‑20 nodes**.

New node types:

- additional junctions
- multiple sources
- multiple demand nodes

---

## Pressure Regulating Stations

The simulation SHALL include PRS components.

PRS behaviour:

- automatic pressure reduction
- valve‑like control dynamics
- common cyber‑attack target

---

## Underground Storage Node

The network SHALL support storage nodes capable of:

- injecting gas
- withdrawing gas
- enabling bidirectional flow

---

# Cyber Layer Requirements

## Historian / SCADA Data Layer

Sensor data SHALL pass through a historian layer.

Features:

- deadband compression
- scan‑rate aliasing
- timestamp buffering

Implementation file:

updateHistorian.m

---

## Multi‑PLC Architecture

The system SHALL support multiple PLCs controlling separate pipeline zones.

Example:

PLC‑1 → compressor station  
PLC‑2 → distribution network  
PLC‑3 → storage facility

A master SCADA node coordinates communication.

---

## False Data Injection Attack (A9)

The system SHALL implement an advanced FDI attack.

Characteristics:

- individually plausible measurements
- collectively inconsistent state
- designed to bypass EKF residual checks

Implementation:

computeFDIVector.m

---

## Replay Attack (A10)

The system SHALL support replay attacks.

Mechanism:

- record historical sensor window
- replay during physical attack
- mask anomalies from state estimators

---

# Data Realism Requirements

## Diurnal Demand Profile

Demand SHALL follow realistic daily cycles.

Example profile:

low demand at night  
morning peak  
evening peak

This creates a **non‑stationary baseline**.

---

## Measurement Quantisation

Sensors SHALL simulate finite resolution.

Example:

12‑bit ADC → 4096 levels

Quantisation formula:

floor(value / resolution) * resolution

---

## Communication Packet Loss

The system SHALL simulate packet loss.

Behaviour:

- configurable loss rate
- PLC holds last known value

---

## Structured Event Logging

Simulation SHALL produce an event‑based log.

Event examples:

- attack start/end
- valve actuation
- compressor surge
- alarm triggers

This enables training sequence models.

---

# Data Flow Summary

1. MATLAB computes pipeline physics.
2. MATLAB sends sensor values via UDP.
3. Python middleware writes values to PLC registers.
4. PLC runs control logic.
5. PLC outputs actuator commands.
6. Python forwards commands back to MATLAB.
7. MATLAB updates plant state.

---

# Backward Compatibility

The system SHALL maintain compatibility with the original simulation where possible.

If advanced features are disabled:

- the system SHALL behave like the baseline implementation
- existing scripts SHALL execute without modification

---

# Research Use Cases

The upgraded system supports:

- cyber‑physical anomaly detection research
- machine learning dataset generation
- SCADA cyberattack simulation
- digital twin experimentation
