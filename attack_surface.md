Below are **three professional diagrams** you can directly include in your **project documentation, thesis, or GitHub README**.
They are written in **Mermaid**, which renders automatically in **GitHub, MkDocs, Obsidian, and many Markdown viewers**.

These diagrams represent:

1️⃣ **GasLib-24 inspired pipeline network (20 nodes)**
2️⃣ **Complete ICS cyber-physical architecture**
3️⃣ **Attack Surface Map (standard diagram used in ICS security research)**

---

# 1. GasLib-24 Inspired Pipeline Network (20 Nodes)

This diagram represents a **transmission-level gas network** with:

* 2 supply sources
* 2 compressor stations
* 1 underground storage cavern
* pressure regulating stations
* multiple demand nodes
* branching + loop topology

```mermaid
flowchart LR

%% Sources
S1((Source 1))
S2((Source 2))

%% Junctions
J1((J1))
J2((J2))
J3((J3))
J4((J4))
J5((J5))
J6((J6))
J7((J7))
J8((J8))
J9((J9))
J10((J10))

%% Compressors
C1[[Compressor Station 1]]
C2[[Compressor Station 2]]

%% Regulators
PRS1[[Pressure Regulator]]
PRS2[[Pressure Regulator]]

%% Storage
STO((Storage Cavern))

%% Demand nodes
D1((Demand1))
D2((Demand2))
D3((Demand3))
D4((Demand4))
D5((Demand5))
D6((Demand6))

%% Main trunk
S1 --> J1
J1 --> C1
C1 --> J2
J2 --> J3
J3 --> J4
J4 --> C2
C2 --> J5

%% Branches
J2 --> J6
J6 --> PRS1
PRS1 --> D1
PRS1 --> D2

J3 --> J7
J7 --> STO
STO --> J8

J5 --> J9
J9 --> PRS2
PRS2 --> D3
PRS2 --> D4

%% Loop section
J8 --> J10
J10 --> J5

%% Second source
S2 --> J7

%% Additional demand
J4 --> D5
J8 --> D6
```

### Why this topology matters

It introduces realistic features:

* **loop flows**
* **multi-source balancing**
* **bidirectional storage flow**
* **pressure drop across regulators**

This prevents ML models from **memorizing topology**, improving research quality.

---

# 2. Complete ICS Network Architecture

This diagram shows the **cyber-physical architecture of the system**.

It includes:

* MATLAB physical simulator
* Python gateway
* CODESYS PLC controllers
* SCADA system
* historian database

```mermaid
flowchart LR

subgraph Physical_System
MATLAB[MATLAB Gas Pipeline Simulator]
Sensors[Virtual Sensors\nPressure Flow Temperature]
Actuators[Virtual Actuators\nValves Compressors]
end

subgraph Middleware
PY[Python Gateway\nUDP + Modbus]
end

subgraph Control_System
PLC1[PLC Zone 1\nCompressor Station]
PLC2[PLC Zone 2\nDistribution]
PLC3[PLC Zone 3\nStorage Control]
end

subgraph SCADA_System
SCADA[SCADA Server]
HMI[Operator HMI]
HIST[Historian Database]
end

Sensors --> MATLAB
MATLAB --> PY
PY --> PLC1
PY --> PLC2
PY --> PLC3

PLC1 --> PY
PLC2 --> PY
PLC3 --> PY

PY --> MATLAB
MATLAB --> Actuators

PLC1 --> SCADA
PLC2 --> SCADA
PLC3 --> SCADA

SCADA --> HIST
HIST --> HMI
```

### What this diagram shows

Real industrial pipelines operate exactly like this:

```
field devices → PLCs → SCADA → historian
```

Your simulator recreates the **same architecture**.

---

# 3. ICS Attack Surface Map (Critical for Research Papers)

This diagram shows **where attackers can intervene in the system**.

This type of diagram is extremely common in:

* ICS cybersecurity papers
* industrial threat modeling
* digital twin security research

```mermaid
flowchart LR

Attacker((Attacker))

subgraph Field_Level
Sensors[Pressure Sensors]
FlowMeters[Flow Meters]
Valves[Control Valves]
Compressors[Compressor Drives]
end

subgraph Control_Level
PLC[PLC Controllers]
end

subgraph Network_Level
Gateway[Python Communication Gateway]
Network[Industrial Network]
end

subgraph SCADA_Level
SCADA[SCADA Server]
HMI[Operator HMI]
Historian[Historian Database]
end

subgraph Physical_Plant
Pipeline[Gas Pipeline System]
end

Pipeline --> Sensors
Pipeline --> FlowMeters

Sensors --> PLC
FlowMeters --> PLC

PLC --> Gateway
Gateway --> Network
Network --> SCADA

SCADA --> Historian
Historian --> HMI

PLC --> Valves
PLC --> Compressors

%% attack paths

Attacker -. Sensor Spoofing .-> Sensors
Attacker -. False Data Injection .-> Gateway
Attacker -. Network MITM .-> Network
Attacker -. PLC Compromise .-> PLC
Attacker -. SCADA Intrusion .-> SCADA
Attacker -. Replay Attack .-> Gateway
Attacker -. Command Tampering .-> PLC
```

---

# Why This Diagram is Important

It clearly identifies attack categories:

| Attack Type          | Target           |
| -------------------- | ---------------- |
| Sensor spoofing      | sensors          |
| False data injection | gateway          |
| Replay attack        | network          |
| PLC compromise       | PLC              |
| SCADA intrusion      | SCADA            |
| Command tampering    | actuator control |

This helps explain **where your attacks A1–A10 occur**.

---

# Recommended Usage in Your Documentation

Use the diagrams like this:

```
docs/
  architecture.md
  pipeline_network.md
  attack_surface.md
```

Or in a thesis:

```
Chapter 3 – System Architecture
    Fig 3.1 Pipeline Network
    Fig 3.2 Cyber Physical Architecture
    Fig 3.3 Attack Surface Map
```

---

💡 If you'd like, I can also generate **one more extremely powerful diagram** used in many cyber-physical research papers:

**The "Data Flow of a Single Simulation Step" diagram**

It shows:

```
Physics → Sensors → PLC → Control → Actuators → Physics
```

This makes the **entire system operation instantly understandable**.
