# Tabletop Physical Gas Pipeline Testbed — Construction Guide

> **Scope:** Standalone single-pipe (or two-pipe) compressed-air physical testbed for validating
> process-layer and protocol-layer ICS security research. This is **completely independent** from
> the MATLAB + CODESYS software simulator. It has its own PLC, its own HMI laptop, and its own
> network. No shared infrastructure.

---

## Table of Contents

1. [What this testbed achieves](#1-what-this-testbed-achieves)
2. [Bill of materials](#2-bill-of-materials)
3. [Purdue model architecture](#3-purdue-model-architecture)
4. [Physical pipeline construction](#4-physical-pipeline-construction)
5. [Electrical and signal wiring](#5-electrical-and-signal-wiring)
6. [Network topology and IP addressing](#6-network-topology-and-ip-addressing)
7. [PLC configuration in TIA Portal](#7-plc-configuration-in-tia-portal)
8. [HMI / SCADA on the second laptop](#8-hmi--scada-on-the-second-laptop)
9. [Commissioning and validation checklist](#9-commissioning-and-validation-checklist)
10. [Limitations](#10-limitations)

---

## 1. What this testbed achieves

This physical setup provides two categories of validation that a purely software simulation
cannot:

**Process-layer validation** — real compressed air flowing through a real pipe, measured by real
sensors. Pressure, temperature, and flow readings carry genuine physical noise, quantisation
artefacts from the ADC, and thermal drift. These characteristics make the dataset look like real
industrial data rather than clean floating-point arrays.

**Protocol-layer validation** — a hardware Siemens S7-1200 PLC executing ladder logic on a real
scan cycle (~10 ms) communicates over a real Ethernet cable using S7 or Modbus/TCP. Packet
timing, function-code sequences, register-update patterns, and response latencies match what
you would capture from a live field installation — not what a software PLC or Docker container
can reproduce.

A one-pipe setup is sufficient to demonstrate both layers and to validate that your sensor
scaling, register map, and PID logic are correct before scaling up.

---

## 2. Bill of materials

### 2.1 Core control hardware

| Item | Model | Qty | Notes |
|------|-------|-----|-------|
| PLC CPU | Siemens S7-1200 CPU 1214C DC/DC/DC (6ES7214-1AG40-0XB0) | 1 | 14 DI, 10 DO, 2 AI onboard |
| Analog input module | SM 1231 8AI (6ES7231-4HF32-0XB0) | 1 | 4-20 mA, 12-bit+sign |
| Analog output module | SM 1232 2AO (6ES7232-4HB32-0XB0) | 1 | 4-20 mA / 0-10 V out |
| 24 V DC power supply | Siemens SITOP PSU100S 24V/5A (6EP1333-2BA20) | 1 | Powers PLC + all sensors |
| DIN rail, 35 mm | Standard 500 mm length | 1 | Mounts all modules |
| Terminal block set | Phoenix Contact or equivalent | 1 set | Signal and power distribution |

### 2.2 Field instruments (process layer)

| Item | Model | Qty | Notes |
|------|-------|-----|-------|
| Pressure transmitter | Endress+Hauser Cerabar PMP71, 0-10 bar, 4-20 mA, 2-wire | 2 | One upstream, one downstream of valve |
| Temperature transmitter | PT100 probe + head-mounted RTD to 4-20 mA transmitter | 1 | Pipe wall temperature |
| Thermal mass flow meter | Bronkhorst EL-FLOW Select, 0-200 Nm3/h, 4-20 mA | 1 | Placed on inlet section |

### 2.3 Actuators (field devices)

| Item | Model | Qty | Notes |
|------|-------|-----|-------|
| Proportional control valve | Festo VPCF or VPPE, 4-20 mA input, half-inch body | 1 | Main flow modulator |
| Solenoid shutoff valve | ASCO 8210 series, 24 V DC coil, NC, half-inch body | 1 | Emergency shutoff, fail-safe closed |
| Compressor (air source) | Small lab piston or scroll, 0.25-0.75 HP | 1 | Supplies compressed air |
| Variable frequency drive | Siemens SINAMICS V20, 0.37 kW (6SL3210-5BE13-7UV0) | 1 | Controls compressor motor speed |

### 2.4 Pipe and fittings

| Item | Spec | Qty | Notes |
|------|------|-----|-------|
| Steel pipe | 15 mm or half-inch NB IS 1239 medium class | 1-2 m | Main pipe run |
| Compression tee fittings | half-inch BSP brass | 3 | Sensor tapping points |
| Ball valve (manual isolation) | half-inch BSP, brass | 2 | Manual isolators either end |
| Pressure relief valve | Set at 1.5x MAOP, half-inch BSP | 1 | Safety - mandatory |
| Flexible hose | half-inch, rated 3x MAOP or more | 0.3 m | Connects compressor to pipe |
| End cap or regulator | half-inch BSP | 1 | Downstream end termination |

### 2.5 Electrical miscellaneous

| Item | Qty |
|------|-----|
| Shielded twisted-pair cable, 0.5 mm2, 2-core (for 4-20 mA signals) | 10 m |
| Single-core power wire, 1.0 mm2 red and black | 5 m each |
| Motor cable, 4-core shielded, 1.0 mm2 | 2 m |
| Interposing relay, 24 V DC coil (for solenoid valve drive) | 1 |
| Freewheeling diode 1N4007 | 2 |
| Cable glands, IP67, M16 | 6 |
| Ferrule crimp terminals | 1 pack |
| Circuit breaker, 6 A (for 230 V AC input) | 1 |
| Earth busbar | 1 |

### 2.6 Network and computing

| Item | Qty | Notes |
|------|-----|-------|
| Managed Ethernet switch, 5-port, 100 Mbps | 1 | Connects PLC + HMI laptop + data-capture PC |
| Ethernet cable Cat5e, 1 m | 3 | PLC to switch, HMI to switch, capture PC to switch |
| HMI / SCADA laptop | 1 | Dedicated — runs WinCC or Node-RED dashboard |
| Engineering laptop (separate) | 1 | Runs TIA Portal for PLC programming only |

The engineering laptop is only connected during programming. It is removed from the network
during experiment runs. The HMI laptop stays connected permanently.

---

## 3. Purdue model architecture

The Purdue Reference Model (IEC 62264 / ISA-95) divides industrial control systems into five
levels. Your tabletop testbed implements Levels 0 through 3 with one exception: there is no
Level 4 (enterprise) because this is a standalone research setup.

```
+----------------------------------------------------------------------+
|  LEVEL 3 -- Site Operations (HMI / SCADA Laptop)                     |
|  WinCC or Node-RED running on a dedicated laptop                     |
|  Functions: real-time trending, alarm management, data historian     |
|  Protocol to Level 2: S7 or Modbus TCP over Ethernet                |
|  IP: 192.168.10.20   Network: OT-LAN (isolated)                     |
+----------------------------------------------------------------------+
|  LEVEL 2 -- Supervisory Control (Siemens S7-1200 CPU 1214C)         |
|  PLC executing PID logic, safety interlock, alarm generation        |
|  SM 1231 (analog in) + SM 1232 (analog out) attached                |
|  Protocol to Level 1: hardwired 4-20 mA / 24 V DC I/O              |
|  IP: 192.168.10.10   Network: OT-LAN (isolated)                     |
+----------------------------------------------------------------------+
|  LEVEL 1 -- Basic Control (local instrument signals)                 |
|  4-20 mA current loops between PLC modules and field devices        |
|  All signals are analogue -- no digital fieldbus at this level       |
+----------------------------------------------------------------------+
|  LEVEL 0 -- Physical Process (pipe, instruments, actuators)          |
|  Compressed air pipe, pressure/temp/flow transmitters               |
|  Proportional valve, solenoid shutoff valve, VFD-driven compressor  |
|  No network connectivity -- purely physical/electrical              |
+----------------------------------------------------------------------+
```

### Network isolation principle

The OT-LAN (192.168.10.0/24) is **air-gapped from the internet and from any IT network**.
Nothing connects this switch to your home router, university LAN, or the simulator laptop. This
is not optional — it is both a safety requirement (no remote control of live pneumatic equipment)
and a research requirement (clean network captures without background traffic).

```
                  +------------------+
  TIA Portal      |  5-port managed  |
  Engineering PC  |  Ethernet switch |   <-- OT-LAN only, no uplink
  192.168.10.30   |  192.168.10.0/24 |
  (connected only +--+----------+----+
   during prog.)     |          |
             +--------+--+  +---+------------+
             |  PLC       |  |  HMI Laptop   |
             |  S7-1200   |  |  WinCC /      |
             |  .10       |  |  Node-RED .20 |
             +------------+  +---------------+
```

A data-capture laptop (192.168.10.40) can optionally connect to the switch during experiments
to run Wireshark and capture Modbus/S7 packets for protocol-layer dataset generation. This
laptop has no other network connections while capturing.

---

## 4. Physical pipeline construction

### 4.1 Single-pipe layout (minimum viable setup)

```
COMPRESSOR
    |  flexible hose
    |
[MANUAL BALL VALVE -- isolation]
    |
[FLOW METER -- EL-FLOW]                    <-- 4-20 mA --> SM1231 ch6
    |
[PRESSURE TRANSMITTER PT-1 -- upstream]   <-- 4-20 mA --> SM1231 ch0
    |
[TEMPERATURE TRANSMITTER TT-1]             <-- 4-20 mA --> SM1231 ch4
    |
[SOLENOID SHUTOFF VALVE SV-1 (NC)]        <-- PLC DO --> relay --> valve coil
    |
[PROPORTIONAL CONTROL VALVE CV-1]         <-- SM1232 ch0 --> 4-20 mA --> valve
    |
[PRESSURE TRANSMITTER PT-2 -- downstream] <-- 4-20 mA --> SM1231 ch1
    |
[PRESSURE RELIEF VALVE -- fixed, 1.5x MAOP]  (passive, no wiring)
    |
[MANUAL BALL VALVE -- isolation]
    |
 EXHAUST / VENT (to atmosphere or collection tank)
```

All pipe fittings are compression type (no welding required). Total pipe run is approximately
1.0-1.5 m, fitting comfortably on a 1.2 x 0.6 m table.

### 4.2 Two-pipe extension (for junction node experiments)

Add a tee fitting after PT-1 and create a parallel branch with its own proportional valve and
downstream pressure transmitter. This creates a minimal branched topology matching a 3-node
network (source node -> junction node -> two demand nodes) and allows demonstration of
flow splitting, differential pressure effects, and branch valve isolation — the most important
phenomena for attack injection experiments.

```
                        +------[CV-1A]------[PT-2A]--> BRANCH A exhaust
[FM][PT-1][TT-1][SV-1]--+
                        +------[CV-1B]------[PT-2B]--> BRANCH B exhaust
```

### 4.3 Mounting and mechanical safety rules

Mount all components on the DIN rail panel first. Test electrical connections before connecting
the pipe. Always keep the manual isolation valves closed until electrical commissioning is
complete. Set the pressure relief valve before first pressurisation — for a 0-10 bar sensor, a
relief setting of 8 bar (80% FS) is appropriate. Never exceed the rated working pressure of the
lowest-rated component in the loop.

---

## 5. Electrical and signal wiring

### 5.1 24 V DC power distribution

```
230 V AC (circuit breaker 6A) ---> SITOP PSU 24V/5A
                                        |
                                +-------+--------+
                                |  +24 V DC bus  |  (red terminal blocks)
                                |  0 V / GND bus |  (blue terminal blocks)
                                +-------+--------+
                                        |
             +--------------------------+--------------------------+
             |                          |                         |
        PLC L+ / M              Sensor loop power         Solenoid relay
        CPU + modules           (+24 V to each transmitter) coil supply
```

### 5.2 Sensor wiring (4-20 mA, 2-wire loop)

For every 2-wire loop-powered transmitter (pressure and temperature):

```
+24 V DC --------------------------------> Transmitter terminal (+)
                                                  |
                                           [sensor circuit]
                                                  |
Transmitter terminal (-) -----------------> SM1231 channel (+)
                                                  |
                                           [internal 250 ohm shunt]
                                                  |
SM1231 channel (-) --------------------------> 0 V / GND bus
```

Never connect +24 V directly to the SM1231 channel input. The +24 V always goes to the
transmitter first, and the transmitter controls how much current flows (4-20 mA proportional
to the measured value). The SM1231 measures this current across its internal shunt resistor.

**Channel assignments on SM1231:**

| SM1231 Channel | Signal | Device |
|----------------|--------|--------|
| AI Ch0 | 4-20 mA | PT-1 upstream pressure |
| AI Ch1 | 4-20 mA | PT-2 downstream pressure |
| AI Ch2 | 4-20 mA | PT-3 (branch A, if fitted) |
| AI Ch3 | 4-20 mA | PT-4 (branch B, if fitted) |
| AI Ch4 | 4-20 mA | TT-1 temperature |
| AI Ch5 | spare | -- |
| AI Ch6 | 4-20 mA | FM-1 flow meter |
| AI Ch7 | spare | -- |

### 5.3 Analog output wiring (SM1232 to actuators)

For the proportional valve (4-20 mA command):

```
SM1232 AO Ch0 (+) ---------> Valve controller Signal In (+)
SM1232 AO Ch0 (-) ---------> Valve controller Signal In (-) -> 0V
+24 V DC ------------------> Valve controller supply (+24 V)
0 V -----------------------> Valve controller supply (0 V)
```

For the VFD speed reference (0-10 V):

```
SM1232 AO Ch1 (+) ---------> VFD AI1 (+)
SM1232 AO Ch1 (-) ---------> VFD AI1 (-) -> 0V / VFD DIC
+24 V DC ------------------> VFD power supply (separate from signal)
```

**Channel assignments on SM1232:**

| SM1232 Channel | Signal | Device |
|----------------|--------|--------|
| AO Ch0 | 4-20 mA | CV-1 proportional valve setpoint |
| AO Ch1 | 0-10 V | VFD speed reference (compressor) |

### 5.4 Digital output wiring (CPU DO to solenoid valve)

The CPU digital output can supply only ~0.5 A. The ASCO solenoid coil draws 0.8-1.0 A,
so an interposing relay is required:

```
PLC DO 0.0 (+24 V when ON) -----> Relay coil terminal A1
0 V -----------------------------> Relay coil terminal A2
+24 V DC ------------------------> Relay common terminal (COM)
Relay NO terminal ---------------> Solenoid valve coil (+)
Solenoid valve coil (-) ---------> 0 V
Freewheeling diode 1N4007 -------> Across solenoid coil (cathode to + side)
```

The freewheeling diode absorbs the back-EMF spike when the coil de-energises. Without it,
the voltage spike can damage the PLC transistor output.

### 5.5 Digital input wiring (VFD fault feedback to CPU DI)

```
VFD fault relay contact RL1A ----> PLC DI 0.0
VFD fault relay contact RL1C ----> 0 V
+24 V ---------------------------> PLC DI supply (provided by CPU internally)
```

### 5.6 VFD terminal wiring summary

| VFD Terminal | Connect to | Purpose |
|---|---|---|
| L / L1 | Mains 230 V Line | AC power input |
| N / L2 | Mains Neutral | AC power input |
| PE | Earth busbar | Safety earth |
| U, V, W | Compressor motor U, V, W | Power output to motor |
| PE motor side | Motor frame earth | Motor earth bond |
| AI1 (+) | SM1232 AO Ch1 (+) | Speed reference signal |
| AI1 (-) | SM1232 AO Ch1 (-) / 0V | Signal return |
| DI1 | PLC DO 0.1 | Run/Stop command |
| DIC | 0 V common | Digital input common |
| RL1A, RL1C | PLC DI 0.0 | Fault relay output |

### 5.7 Complete wiring summary table

| Field device | Device terminal | PLC terminal | Module | Signal type |
|---|---|---|---|---|
| PT-1 upstream pressure | TX(+) | +24V rail | -- | Loop power supply |
| PT-1 upstream pressure | TX(-) | SM1231 AI Ch0(+) | SM1231 | 4-20 mA signal |
| PT-1 upstream pressure | SM1231 AI Ch0(-) | 0V rail | SM1231 | Signal return |
| PT-2 downstream pressure | Same pattern | SM1231 AI Ch1 +/- | SM1231 | 4-20 mA |
| TT-1 temperature transmitter | TX +24V in | +24V rail | -- | Power |
| TT-1 temperature transmitter | TX Output(+) | SM1231 AI Ch4(+) | SM1231 | 4-20 mA signal |
| TT-1 temperature transmitter | TX Output(-) / 0V | 0V rail | SM1231 | Signal return |
| FM-1 flow meter | FM +24V | +24V rail | -- | Power |
| FM-1 flow meter | FM 0V | 0V rail | -- | Power return |
| FM-1 flow meter | FM Output(+) | SM1231 AI Ch6(+) | SM1231 | 4-20 mA signal |
| FM-1 flow meter | FM Output(-) | SM1231 AI Ch6(-) -> 0V | SM1231 | Signal return |
| CV-1 proportional valve | Valve +24V | +24V rail | -- | Power |
| CV-1 proportional valve | Valve 0V | 0V rail | -- | Power return |
| CV-1 proportional valve | Valve Signal In(+) | SM1232 AO Ch0(+) | SM1232 | 4-20 mA control |
| CV-1 proportional valve | Valve Signal In(-) | SM1232 AO Ch0(-) -> 0V | SM1232 | Signal return |
| SV-1 solenoid valve | Coil(+) | Relay NO terminal | -- | Via relay |
| SV-1 solenoid valve | Coil(-) | 0V rail | -- | Coil return |
| Relay coil A1 | -- | PLC DO 0.0 | CPU DO | DO triggers relay |
| Relay coil A2 | -- | 0V rail | -- | DO return |
| Relay COM | -- | +24V rail | -- | Switched power source |
| VFD speed ref | AI1(+) | SM1232 AO Ch1(+) | SM1232 | 0-10 V reference |
| VFD speed ref | AI1(-) | SM1232 AO Ch1(-) -> 0V | SM1232 | Signal return |
| VFD run/stop | DI1 | PLC DO 0.1 | CPU DO | Run command |
| VFD common | DIC | 0V rail | -- | DI return |
| VFD fault | RL1A / RL1C | PLC DI 0.0 | CPU DI | Fault feedback |

---

## 6. Network topology and IP addressing

```
+------------------------------------------------------------+
|             OT-LAN  192.168.10.0/24                        |
|                                                            |
|  +----------+   +----------+   +------------------+       |
|  | S7-1200  |   |  HMI     |   |  Capture PC      |       |
|  | PLC      |   |  Laptop  |   |  Wireshark       |       |
|  | .10      |   |  .20     |   |  .40             |       |
|  +----+-----+   +----+-----+   +--------+---------+       |
|       |              |                  |                  |
|  +----+--------------+------------------+-----------+      |
|  |    5-port managed switch                         |      |
|  |    no uplink port connected                      |      |
|  +--------------------------------------------------+      |
|                                                            |
|  [ Engineering PC .30 -- connected only during            |
|    TIA Portal programming, then physically unplugged ]    |
+------------------------------------------------------------+
```

**Protocol choice — Modbus/TCP vs S7:** For ICS security dataset purposes, Modbus/TCP on port
502 is preferable because it is the industry-standard open protocol your simulator already uses,
making cross-validation between the software simulator and the physical testbed
straightforward. Configure the S7-1200's Modbus TCP server via TIA Portal's MB_SERVER
instruction block. The HMI can connect via S7 protocol (port 102), while Wireshark on the
capture PC sees both protocol streams on the switch mirror port.

---

## 7. PLC configuration in TIA Portal

### 7.1 Hardware configuration steps

1. Open TIA Portal, create New Project, Add device, select S7-1200 CPU 1214C (6ES7214-1AG40-0XB0)
2. In the device view, drag SM 1231 (8AI) onto slot 1 (right of CPU)
3. Drag SM 1232 (2AO) onto slot 2
4. For each SM1231 channel in use: set Measurement type = Current, Range = 4-20 mA, enable overflow/underflow diagnostics = Yes
5. For SM1232 Ch0 (valve): Output type = Current, Range = 4-20 mA
6. For SM1232 Ch1 (VFD): Output type = Voltage, Range = 0-10 V
7. Set PLC IP address = 192.168.10.10, subnet mask = 255.255.255.0

### 7.2 Engineering unit conversion (TIA Portal scaling)

TIA Portal maps 4-20 mA to the integer range 5530-27648 internally on SM1231. Use the
NORM_X and SCALE_X instructions:

```
// Convert SM1231 raw counts to pressure in bar (example: 0-10 bar sensor)
#normalized := NORM_X(MIN := 5530.0, VALUE := INT_TO_REAL(#SM1231_Ch0_raw), MAX := 27648.0);
#PT1_bar    := SCALE_X(MIN := 0.0, VALUE := #normalized, MAX := 10.0);

// Convert pressure in bar to SM1232 output (4-20 mA = 0-100% valve command)
#SM1232_Ch0_raw := REAL_TO_INT(NORM_X(MIN := 0.0, VALUE := #CV1_pct, MAX := 100.0) * 27648.0);
```

### 7.3 Modbus TCP server configuration

Add a Global Data Block (DB1, non-optimised access, 200 bytes minimum) to hold Modbus
registers. In OB1, add the MB_SERVER function block:

```
// In OB1 (cyclic, scan cycle approx 10 ms)
"MB_SERVER_DB"(
    MB_HOLD_REG := "ModbusHR",
    NDR         => #newDataReceived,
    DR          => #dataRead,
    ERROR       => #mbError,
    STATUS      => #mbStatus
);
```

**Modbus holding register map (mirrors the CODESYS simulator convention):**

| Register (0-based) | Modbus address | Engineering value | Scaling | Units |
|---|---|---|---|---|
| 0 | 40001 | PT-1 upstream pressure | x 100 to INT | bar |
| 1 | 40002 | PT-2 downstream pressure | x 100 to INT | bar |
| 2 | 40003 | TT-1 temperature | x 10 to INT | degrees C |
| 3 | 40004 | FM-1 flow rate | x 10 to INT | Nm3/h |
| 10 | 40011 | CV-1 valve command | x 100 to INT | percent open |
| 11 | 40012 | VFD speed setpoint | x 10 to INT | Hz |
| 12 | 40013 | SV-1 status | 0/1 | 0=closed, 1=open |
| 20 | 40021 | Alarm word | bit flags | see below |

**Alarm word bit definitions:**

| Bit | Alarm |
|---|---|
| 0 | High-pressure alarm (PT-1 or PT-2 > 8 bar) |
| 1 | Low-pressure alarm (PT-2 < 0.5 bar) |
| 2 | Flow meter fault (FM reading = 0 with valve open) |
| 3 | VFD fault |
| 4 | Emergency shutdown active |

### 7.4 PID pressure control loop

Use the PID_Compact function block from TIA Portal's standard library. Tune using the
built-in commissioning wizard (auto-tune with step response):

```
// PID_Compact configuration
"PID_Compact_DB"(
    Setpoint     := 3.0,        // bar (write this from HMI)
    Input        := #PT2_bar,   // downstream pressure in bar (float)
    Output       := #CV1_pct,   // 0.0 to 100.0 percent valve position
    ManualEnable := false,
    Config.InputLimHigh := 10.0,
    Config.InputLimLow  := 0.0,
    Config.OutputUpperLimit := 100.0,
    Config.OutputLowerLimit := 0.0
);
```

### 7.5 Safety interlock logic

```
// Emergency shutdown: upstream pressure above 8 bar
IF #PT1_bar > 8.0 THEN
    #SV1_coil    := FALSE;   // de-energises relay, NC valve closes
    #CV1_setpoint := 0.0;
    #VFD_run     := FALSE;
    #ALARM_word.4 := TRUE;   // emergency shutdown bit
END_IF;

// Normal run: solenoid opens only when pressure is stable and no alarm
IF #PT1_bar > 0.5 AND NOT #ALARM_word.4 THEN
    #SV1_coil := TRUE;
END_IF;
```

---

## 8. HMI / SCADA on the second laptop

### 8.1 Software options

| Option | Cost | Notes |
|---|---|---|
| WinCC Unified PC Runtime | EUR 500-1000 licence | Best S7-1200 integration |
| WinCC Basic (included with TIA Portal Basic) | Included | 500 tag limit, fine for this setup |
| Node-RED + node-red-contrib-modbus | Free, open-source | Best for rapid prototyping |
| Python + pymodbus + Grafana | Free, open-source | Best for research data capture |

For a research testbed on a tight deadline, **Node-RED with node-red-contrib-modbus** is the
fastest path to a working HMI. Install on the HMI laptop:

```bash
npm install -g node-red
cd ~/.node-red
npm install node-red-contrib-modbus
node-red
# Open browser at http://localhost:1880
```

Create a flow that polls the S7-1200 Modbus server every 500 ms and logs to a CSV file.

### 8.2 Data historian for dataset generation

The HMI laptop should continuously log all tag values to CSV with the following minimum
columns. This exactly mirrors the `pipeline_data_*.csv` schema from the software simulator
for direct cross-comparison.

| Column | Description |
|---|---|
| timestamp_ms | Unix timestamp in milliseconds |
| datetime_utc | Human-readable UTC datetime |
| cycle | Sample counter |
| p_PT1_bar | PT-1 upstream pressure engineering value |
| p_PT2_bar | PT-2 downstream pressure engineering value |
| T_TT1_degC | TT-1 temperature engineering value |
| q_FM1_nm3h | FM-1 flow rate engineering value |
| p_PT1_raw | PT-1 raw INT register value |
| p_PT2_raw | PT-2 raw INT register value |
| T_TT1_raw | TT-1 raw INT register value |
| q_FM1_raw | FM-1 raw INT register value |
| CV1_pct | Valve command percent open |
| VFD_hz | VFD speed setpoint Hz |
| SV1_status | Solenoid valve 0=closed 1=open |
| alarm_word | Alarm bit field |
| label | Manually entered: normal or attack type name |

### 8.3 Wireshark capture for protocol dataset

On the data-capture laptop (192.168.10.40), configure the managed switch to mirror all traffic
to the capture port. Then run:

```bash
# Capture only Modbus TCP (port 502) and S7 (port 102)
wireshark -i eth0 -f "port 502 or port 102" -w /captures/session_$(date +%Y%m%d_%H%M%S).pcap
```

The captured PCAP file contains the complete protocol-layer ground truth: transaction IDs,
function codes (FC01 coils, FC03 holding registers, FC06 single write, FC16 multi-write),
request/response pairing, inter-request intervals, and response times. This is the evidence
that justifies the "protocol-authentic" claim that neither Docker containers nor pure software
PLCs can provide.

---

## 9. Commissioning and validation checklist

Work through these stages in strict order. Never move to the next stage until the current one passes.

### Stage 1 — Electrical safety (before any power-on)

- [ ] All power terminals verified correct polarity (+/-) with multimeter at 0V
- [ ] All analog signal cable shields connected at PLC end only (not at sensor end)
- [ ] Freewheeling diode fitted across solenoid valve coil (cathode to + side)
- [ ] Motor cable routed separately from signal cables (minimum 200 mm separation)
- [ ] All wire ends have ferrule crimp terminals (no bare stranded ends)
- [ ] All wires labelled at both ends with wire number
- [ ] Earth bonding verified: PSU -> DIN rail -> PLC -> enclosure -> mains earth
- [ ] 6 A circuit breaker on 230 V AC input
- [ ] Pressure relief valve installed and set (record relief pressure in logbook)
- [ ] All manual isolation valves CLOSED

### Stage 2 — Power-on without field devices

- [ ] Apply 24 V DC to terminal rail; verify +24 V and 0 V with multimeter
- [ ] Connect PLC to engineering laptop via Ethernet; verify TIA Portal can ping 192.168.10.10
- [ ] Download hardware configuration; verify no module faults in TIA Portal diagnostics
- [ ] Verify SM1231 channels read approximately 0 mA (open circuit gives underflow fault -- correct behaviour)

### Stage 3 — Sensor loop verification

- [ ] Connect PT-1 loop; pressurise to known value with a hand pump; verify PLC reads correct engineering value within plus or minus 0.5 bar
- [ ] Repeat for PT-2, TT-1, FM-1
- [ ] Verify 4 mA = 0 engineering units and 20 mA = full-scale in TIA Portal watch table

### Stage 4 — Actuator verification (unpressurised)

- [ ] Command SM1232 Ch0 to 4 mA (0% = valve fully closed); verify valve physically closes
- [ ] Command SM1232 Ch0 to 20 mA (100% = valve fully open); verify valve fully opens
- [ ] Command PLC DO 0.0 ON; verify relay clicks and solenoid valve energises (audible click)
- [ ] Command SM1232 Ch1 to 5 V (50% speed); VFD should display 25 Hz

### Stage 5 — Pressurised loop (must remain attended throughout)

- [ ] Open upstream manual isolation valve slowly; watch PT-1 reading on HMI
- [ ] Verify pressure relief valve does not open at normal operating pressure
- [ ] Enable PID loop; verify PT-2 downstream pressure stabilises at setpoint
- [ ] Verify flow meter reads plausible flow rate for the valve opening
- [ ] Test emergency shutdown: manually force alarm; verify solenoid closes and VFD stops

### Stage 6 — Protocol layer verification

- [ ] Wireshark running on capture laptop; verify Modbus FC03 requests appear every approximately 500 ms
- [ ] Force a value change (partially close valve manually); verify holding register 40002 changes in Wireshark within one scan cycle
- [ ] Calculate mean inter-request interval and standard deviation; should be approximately 500 ms with standard deviation below 25 ms
- [ ] Verify no unexpected broadcasts or ARP storms on the OT-LAN

---

## 10. Limitations

Understanding what this testbed cannot do is as important as knowing what it can. State
these explicitly in your thesis.

### 10.1 Physical process limitations

**Air versus natural gas.** The working fluid is compressed air (dry, specific gravity approximately 1.0),
not natural gas (specific gravity approximately 0.55-0.65). The Weymouth and Darcy-Weisbach
equations give different results. Compressibility (Z-factor) at 4-8 bar for air is approximately 0.998
(nearly ideal); for natural gas at 50 bar it is approximately 0.88. Any cross-validation between this
testbed and your MATLAB natural gas simulator must include a unit-conversion layer accounting
for gas properties.

**Low operating pressure.** The testbed operates at 2-8 bar, not at the 14-26 bar CGD steel
grid regime or the 40-85 bar GasLib transmission regime. Joule-Thomson cooling, linepack
dynamics, and acoustic wave propagation all scale with pressure squared — they are essentially
absent at testbed pressures. You cannot directly validate the 50-bar MATLAB Weymouth
physics against this 4-bar physical setup without rescaling.

**Single pipe, no network topology.** One pipe has no junction nodes, no loops, and no
multi-source flow splitting. The topological complexity of the 20-node simulator — which drives
the regime diversity in your IDS dataset — cannot be reproduced at tabletop scale without
significant additional hardware cost.

**No compressor head curve.** A small piston compressor provides a near-fixed outlet pressure,
not the variable-ratio characteristic of the CS1/CS2 head curves in MATLAB. Compressor-ratio
spoofing attacks (A2 in your attack schedule) cannot be physically reproduced.

**Negligible linepack.** A 1.5 m run of half-inch pipe holds roughly 250 ml of air at atmospheric
conditions. At 4 bar absolute, that is about 1 litre equivalent. Linepack effects — the slow
pressure propagation delay modelled in MATLAB — are effectively instantaneous at this scale.
Propagation-delay attacks cannot be meaningfully validated here.

### 10.2 Protocol and control limitations

**Single PLC zone.** A real pipeline has multiple PLCs in separate control zones. This testbed has
one CPU, so multi-zone Modbus polling patterns, zone-to-zone latency, and inter-PLC attack
propagation cannot be demonstrated.

**No hardware security barriers.** The testbed has no TLS on Modbus, no certificate-based S7
authentication, and no hardware security module. All attacks on this network are trivially
accessible. This is useful for demonstrating attack mechanics but does not validate detection
methods against adversaries who must bypass real operational barriers.

**Fixed scan cycle.** The S7-1200 OB1 runs at approximately 10 ms. Real field PLCs range from
5 ms (fast process) to 500 ms (slow field instruments). Your dataset will capture only the
10 ms timing signature.

**No packet loss simulation.** A direct Ethernet cable on a clean lab switch shows essentially
zero packet loss — less realistic than industrial noisy environments modelled by the A7
(PLC latency) attack in your simulator.

### 10.3 Research scope and honest claim

**What this testbed validates:** The S7-1200 hardware PLC running TIA Portal ladder logic
produces Modbus/TCP timing, function-code patterns, register quantisation, and scan-cycle
jitter that are indistinguishable from a real industrial field installation. The 4-20 mA sensor
chain introduces realistic quantisation noise and ADC resolution effects. These are protocol-
layer and sensor-layer validation claims.

**What this testbed does not validate:** The 50-bar MATLAB Weymouth gas physics. That
validation is handled separately through GasLib-24 parameter comparison. The single honest
thesis sentence is: "This physical testbed confirms that the CODESYS SoftPLC in the software
simulator produces Modbus/TCP artefacts consistent with hardware PLC communication, and
that the sensor chain introduces quantisation characteristics matching real 4-20 mA transmitters
as measured on the physical setup."

**Safety certification scope.** This testbed is a research demonstrator using compressed air
only. It does not conform to OISD-STD-141, PNGRB T4S, or IS 1239 gas-specific safety
certification, which would apply only if natural gas were used.

---

## Quick-start time estimate

| Step | Action | Estimated time |
|---|---|---|
| 1 | Procure components (BOM section 2) | 1-2 weeks |
| 2 | Mount DIN rail, PSU, PLC, modules on panel | 2 hours |
| 3 | Wire terminal rail and verify 24 V | 1 hour |
| 4 | Assemble pipe run (tees, fittings, transmitters) | 2 hours |
| 5 | Wire all signal cables (shielded STP) | 3 hours |
| 6 | Configure TIA Portal: hardware config + Modbus server + PID | 4 hours |
| 7 | Configure HMI laptop: Node-RED + historian | 2 hours |
| 8 | Commissioning stages 1-6 | 4 hours |
| 9 | First dataset capture (normal + manual valve manipulation) | 2 hours |
| Total | | 20-22 hours active work |

Estimated total hardware cost: INR 1.5-2.5 lakh depending on whether Endress+Hauser and
Bronkhorst instruments are purchased new or sourced through used industrial equipment
dealers. The S7-1200 and SM modules alone are approximately INR 40,000-60,000. Lab-grade
alternatives such as Wika pressure transmitters and Alicat flow meters can reduce cost by
30-40% with minimal impact on research validity.

---

*Last updated: March 2026 | For use with the Gas Pipeline CPS Simulator project*
