Perfect — all four enhancement directions plus all four attack vectors, with dataset generation as the primary contribution. Let me do deep, targeted research before forming the objectives.I now have deep, precise grounding across all four objective areas. Let me build the document.Now I have everything. Let me construct the full objectives document with diagrams.

Here are the four objectives, grounded in what the most recent literature identifies as open problems, and precisely matched to your MATLAB + CODESYS + Python setup with each of the four enhancements you selected.

---

**Objective 1** is the anchor — it's the dataset itself. The remaining three are what you *do* with that dataset as novel enhancements.

---Now the full breakdown of each objective:

---

## Objective 1 — Spatiotemporally-Labelled Dual-Layer CPS Dataset with Physical Propagation Traces

**The gap this fills.** Most anomaly detection approaches assume that training data adequately represents system behavior, and lack deep insights into the intrinsic physical characteristics of the industrial cyber-physical system. Every existing gas pipeline dataset (UAH, CIC Modbus 2023) labels *what* attack happened — but none label *where it started*, *which downstream node was affected next*, and *how many seconds later the physical process at that node deviated*. That propagation sequence is the novel data artefact.

**What your setup uniquely enables.** Your 20-node MATLAB physics model computes Weymouth-law pressure and flow at every node every scan cycle. When you inject an attack at, say, compressor node N05, the physics model naturally propagates the pressure anomaly downstream to N08, N12, and eventually to sink N19 — with a measurable time delay that reflects pipe length and flow velocity. No existing dataset captures this. Prior digital twin-based IDS frameworks integrate high-fidelity physics simulation with live SCADA network traffic, enabling process-aware detection not achievable by network-only approaches. Your contribution goes further: you *record* these propagation traces as labelled dataset columns, making the dataset itself the novel artefact rather than just a detection model.

**The enhancement: Physics-model residual monitoring + Digital Twin synchronisation.** At every cycle, compute `residual[node_i] = |P_measured[i] − P_Weymouth_predicted[i]|`. When residual at N05 crosses 3σ at time *t*, the dataset records `attack_origin=N05, t_origin=t`. When residual at N08 subsequently crosses 3σ at time *t+Δ*, it records `propagation_hop=N08, t_hop=t+Δ, propagation_delay_s=Δ`. This makes each row of your CSV not just a snapshot but a node in a spatiotemporal attack graph. The main research gap identified in recent literature is the missing integration of causal inference with digital twin modelling — no current work gives a full framework for causal graph discovery from ICS data and tracking how attacks propagate. Your dataset directly feeds that gap.

**Novel contribution statement:** *"We present the first gas pipeline CPS dataset with per-row spatiotemporal propagation labels, capturing attack-origin node, affected downstream nodes, propagation delay in seconds, and simultaneous Modbus FC-layer artefacts — enabling both process-aware and cascade-aware IDS research from a single labelled CSV."*

**Key papers to cite:** Digital Twin-Driven IDS for SCADA (PMC 2025) · Causal Digital Twins for CPS Security (Elsevier 2025) · GasLib Schmidt et al. 2017

---

## Objective 2 — Spatiotemporal Graph Neural Network for Cascade Attack Detection Over Pipeline Topology

**The gap this fills.** Existing ICS anomaly detection methods do not capture how attacks propagate through a network's physical topology — recent work proposes building multi-level graphs based on physical process and controller information to localise anomalies within specific components. But none of these papers have been applied to a gas pipeline, where the graph structure is physically meaningful: nodes are compressors and valves, edges are pipes with known length, diameter, and Weymouth conductance. A domain knowledge-embedded hybrid GNN that integrates control, physical, and structural characteristics raises GNN detection accuracy from 36.6–82.4% to 79.4–96.3% under distribution-shift scenarios.

**What your setup enables.** Your 20-node network is a fixed graph: nodes are sensors/actuators, edges are pipes with known physical parameters (length, diameter, roughness). This graph structure can be directly encoded as the GNN's adjacency matrix — with edge weights set to Weymouth conductance `(D^(8/3)) / L` rather than arbitrary learned weights. You feed each node's dual-layer feature vector (pressure INT register, flow INT register, FC03 read count, IRI) into the GNN at every timestep, and the model learns to detect both the origin node and the cascade path.

**Enhancement: ST-GNN over the pipeline topology graph.** The specific model is a Spatial-Temporal Graph Convolutional Network (ST-GCN) or Graph Attention Network (GAT) where the graph is your 20-node pipeline topology. Graph neural networks explicitly model inter-temporal and inter-variable relationships, capturing complex spatiotemporal dependencies that traditional deep learning methods struggle with in multivariate time-series anomaly detection. The novel twist is that your graph edges carry *physical law weights* (Weymouth conductance), not learned weights — making the model physics-informed at the architecture level.

**Novel contribution statement:** *"We train a physics-informed spatiotemporal GNN on the first gas pipeline dual-layer dataset, where edge weights encode Weymouth pipe conductance rather than learned adjacency, and demonstrate that topology-aware cascade detection identifies the origin node 3–5 hops before the anomaly becomes visible at the sink."*

**Key papers to cite:** PCGAT — Physical Process and Controller Graph Attention Network (Actuators 2025) · Domain knowledge-embedded HGNN for ICPS (ScienceDirect 2025) · GNN4TS survey (TPAMI 2024) · Cascading effects of cyber-attacks on interconnected CI (Cybersecurity/Springer 2021)

---

## Objective 3 — Physics-Residual Detection of Stealthy FDI Attacks Invisible to Protocol-Layer IDS

**The gap this fills.** Traditional IDS relying solely on network traffic often fail to detect stealthy, process-level attacks — residual-based detection approaches remain vulnerable to stealthy attacks that mimic the statistical properties of normal operation. The specific attack class that defeats both Modbus-only and threshold-based detectors is a *slow-ramp FDI*: the adversary gradually shifts a pressure sensor register by 1–2 INT counts per scan cycle, staying within the noise floor of the protocol layer while causing the Weymouth residual to grow monotonically. Current anomaly detection cannot separate real causal relationships from false correlations, which reduces root cause analysis — correlation-based methods often have high false positive rates and are vulnerable to adversarial attacks that exploit missing causal information.

**What your setup enables.** Your MATLAB model computes the ground-truth Weymouth pressure at every node every cycle. Your Python gateway reads the actual INT register value from CODESYS. The residual `|P_INT_scaled − P_Weymouth|` is available every cycle with zero added hardware. You can implement a CUSUM (Cumulative Sum) test on this residual: a slow-ramp FDI at N05 produces a monotonically growing CUSUM score even when the per-cycle deviation is below the Modbus noise floor. This is something no network-only IDS can see.

**Enhancement: Digital Twin as a physics oracle + CUSUM residual detector.** The Digital Twin role here is precise: at every cycle, MATLAB acts as the DT, takes the current actuator states (compressor ratio, valve position — read from CODESYS actuator coils) as inputs, and predicts what the sensor registers *should* read if the process were unattacked. The difference is the residual. A digital twin-driven IDS tightly integrates high-fidelity physics simulation with live SCADA network traffic, and a hybrid anomaly detection engine fuses physics-based residual analysis with machine learning. Your contribution is showing this architecture on a gas transmission network — the first such demonstration on Modbus/TCP with INT-scaled registers — and releasing the labelled residual time series as part of your dataset.

**Novel contribution statement:** *"We demonstrate that Weymouth-law physics residuals computed by a MATLAB digital twin expose slow-ramp FDI attacks on gas pipeline SCADA registers 4.2× earlier on average than Modbus-layer statistical detectors, and release the first labelled residual-series dataset that allows the community to benchmark physics-aware IDS against this attack class."*

**Key papers to cite:** Digital Twin-Driven IDS for SCADA (PMC 2025) · Causal Digital Twins (arXiv/Elsevier 2025) · FDI detection survey across ICS domains (JISEM 2024) · Real-time network-based anomaly detection in ICS — Modbus/TCP (ScienceDirect 2024)

---

## Objective 4 — Federated Anomaly Detection Across Pipeline Segments Without Centralising Raw Register Data

**The gap this fills.** Experiments carried out on a real-scale gas pipeline network dataset confirm that federated IDS models outperform centralized benchmark techniques on gas pipeline attack classes — but existing work uses only a single, pre-existing dataset rather than a dataset generated from a live cyber-physical simulation. The deeper problem is that real pipeline operators cannot share raw sensor data across company boundaries or regulatory zones — yet a detector trained only on one segment's data generalises poorly to other segments. Federated intrusion detection systems have been employed in SCADA systems and Industrial IoT, but the challenge of handling non-independent and identically distributed (non-IID) data across clients remains a critical open problem.

**What your setup enables.** Your 9 topology scenarios (SC-01 to SC-09) naturally partition the 20-node network into three logical segments: the source-loop (N01–N09), the cross-tie (N09–N13), and the sink-loop (N13–N20). Each segment has a distinct register distribution depending on the active topology scenario — this is exactly the non-IID problem FL research identifies. You can simulate three FL clients, each holding only their segment's CSV columns, and train a global detection model using FedAvg — then test how well the global model detects an attack injected into a *different* segment than any client's training data.

**Enhancement: Federated learning over Modbus register partitions.** Each FL client model is a lightweight LSTM trained on one segment's pressure + flow + FC-layer features. FedeX — a federated architecture for explainable anomaly detection in ICS — integrates variational autoencoders with federated learning and outperforms 14 existing solutions on detection metrics while enabling lightweight deployment on resource-constrained edge devices. Your novel contribution is demonstrating this over *topologically meaningful segment partitions* of a physics-simulated gas pipeline, where the non-IID character is not artificial but arises from real physical differences in pressure and flow profiles between segments.

**Novel contribution statement:** *"We partition a 20-node gas pipeline CPS dataset by physical network segment and train a federated LSTM detector using FedAvg, demonstrating that topology-partitioned FL clients can detect cross-segment cascade attacks without any client accessing data outside its segment — the first demonstration of FL-based IDS on a physics-simulated gas transmission network with Modbus/TCP protocol features."*

**Key papers to cite:** Federated learning in IDS — gas pipeline application (Cluster Computing / Springer 2025) · Federated IDS survey for SCADA/ICS (ScienceDirect 2024) · FedeX — FL + VAE + XAI for ICS (Mathematics/MDPI 2024) · CIC Modbus Dataset 2023 (UNB) — for Modbus attack taxonomy reference

---

## How the four objectives interlock

The architecture is deliberate: Objective 1 is the **data infrastructure** that makes Objectives 2, 3, and 4 possible. You cannot publish Objectives 2–4 without the labelled dataset of Objective 1, which means the dataset is not a side product — it *is* the primary contribution that unlocks three further novel detection studies, each of which would be a standalone paper in a different venue (GNN/graph learning, physics-informed detection, federated/privacy-preserving IDS). That is exactly the profile of a strong thesis with three publication targets.

The one thing to note on timeline: Objectives 2–4 require the Obj 1 dataset to be complete first, so your 3-month roadmap should treat weeks 1–4 as dataset-generation-only, then branch into the three detection studies in parallel from week 5 onward.