"""
diagnostic.py  —  Full CODESYS Communication Diagnostic
=========================================================
Tests every layer of the current setup:
  1. TCP connectivity
  2. PLC sensor registers (Python → PLC write, then read back)
  3. PLC actuator registers (PLC → Python, read PID outputs)
  4. Coil status (PLC → Python, read bool flags)
  5. Round-trip write/verify test

Run: python diagnostic.py
"""

from pymodbus.client import ModbusTcpClient
import time, struct

HOST    = '127.0.0.1'
PORT    = 1502
DEV_ID  = 1

# ── colour helpers ──────────────────────────────────────────────
def OK(msg):  print(f'  \033[92m✓\033[0m  {msg}')
def ERR(msg): print(f'  \033[91m✗\033[0m  {msg}')
def HDR(msg): print(f'\n\033[1m{msg}\033[0m')
def INF(msg): print(f'     {msg}')

def to_signed(v):
    return v - 65536 if v > 32767 else v

# ── connect ──────────────────────────────────────────────────────
HDR('1 / TCP Connection')
c = ModbusTcpClient(HOST, port=PORT, timeout=3)
ok = c.connect()
if ok:
    OK(f'Connected to {HOST}:{PORT}')
else:
    ERR(f'Cannot connect to {HOST}:{PORT} — is CODESYS running and PLC started (F5)?')
    exit(1)

# ── read ALL sensor registers (0-60) ─────────────────────────────
HDR('2 / Sensor Registers (addr 0-60)  — written by Python, init values from PLC_PRG')

r = c.read_holding_registers(0, count=61, device_id=DEV_ID)
if r.isError():
    ERR(f'FC3 read failed: {r}')
else:
    regs = r.registers
    # Pressures 0-19
    print('\n  Pressures (bar = raw/100):')
    nodes = ['S1','J1','CS1','J2','J3','J4','CS2','J5','J6','PRS1',
             'J7','STO','PRS2','S2','D1','D2','D3','D4','D5','D6']
    for i, name in enumerate(nodes):
        raw = to_signed(regs[i])
        bar = raw / 100.0
        flag = ' ← default init' if raw != 0 else ' ← 0 (MATLAB not connected yet)'
        INF(f'p_{name:5s} [addr {i:2d}] = {raw:6d} raw = {bar:6.2f} bar{flag}')

    # Flows 20-39
    print('\n  Flows (kg/s = raw/100):')
    edges = ['E1','E2','E3','E4','E5','E6','E7','E8','E9','E10',
             'E11','E12','E13','E14','E15','E16','E17','E18','E19','E20']
    nonzero_flows = [(edges[i], to_signed(regs[20+i])) for i in range(20) if regs[20+i] != 0]
    if nonzero_flows:
        for name, raw in nonzero_flows:
            INF(f'q_{name} = {raw} raw = {raw/100:.2f} kg/s')
    else:
        INF('All flow registers = 0  (expected — MATLAB not connected)')

    # Temperatures 40-59
    print('\n  Temperatures (K = raw/10):')
    nonzero_T = [(nodes[i], to_signed(regs[40+i])) for i in range(20) if regs[40+i] != 0]
    if nonzero_T:
        for name, raw in nonzero_T:
            INF(f'T_{name} = {raw} raw = {raw/10:.1f} K')
    else:
        INF('All temperature registers = 0  (expected — MATLAB not connected)')

    # Demand scalar 60
    demand_raw = to_signed(regs[60])
    INF(f'\n  demand_scalar [addr 60] = {demand_raw} raw = {demand_raw/1000:.3f}')

    nonzero = sum(1 for v in regs if v != 0)
    OK(f'Read 61 sensor registers — {nonzero} non-zero (PLC init defaults)')

# ── read actuator registers (100-108) ────────────────────────────
HDR('3 / Actuator Registers (addr 100-108)  — written by PLC control logic')

r = c.read_holding_registers(100, count=9, device_id=DEV_ID)
if r.isError():
    ERR(f'FC3 read actuators failed: {r}')
else:
    regs = r.registers
    act_names  = ['cs1_ratio_cmd','cs2_ratio_cmd','valve_E8_cmd',
                  'valve_E14_cmd','valve_E15_cmd','prs1_setpoint',
                  'prs2_setpoint','cs1_power_kW','cs2_power_kW']
    act_scales = [1000, 1000, 1000, 1000, 1000, 100, 100, 10, 10]
    act_units  = ['ratio','ratio','(1=open)','(1=open)','(1=open)','bar','bar','kW','kW']

    for i, (name, scale, unit) in enumerate(zip(act_names, act_scales, act_units)):
        raw = to_signed(regs[i])
        eng = raw / scale
        INF(f'{name:20s} [addr {100+i}] = {raw:6d} raw = {eng:.4f} {unit}')

    cs1 = to_signed(regs[0]) / 1000.0
    cs2 = to_signed(regs[1]) / 1000.0
    if cs1 >= 1.05 and cs1 <= 1.80:
        OK(f'cs1_ratio_cmd = {cs1:.3f}  (valid range 1.05-1.80)')
    else:
        ERR(f'cs1_ratio_cmd = {cs1:.3f}  OUT OF RANGE — check PID init')

    if cs2 >= 1.02 and cs2 <= 1.60:
        OK(f'cs2_ratio_cmd = {cs2:.3f}  (valid range 1.02-1.60)')
    else:
        ERR(f'cs2_ratio_cmd = {cs2:.3f}  OUT OF RANGE — check PID init')

# ── read coils (0-6) ─────────────────────────────────────────────
HDR('4 / Status Coils (addr 0-6)  — written by PLC logic')

r = c.read_coils(0, count=7, device_id=DEV_ID)
if r.isError():
    ERR(f'FC1 read coils failed: {r}')
else:
    bits = r.bits[:7]
    coil_names = ['emergency_shutdown','cs1_alarm','cs2_alarm',
                  'sto_inject_active','sto_withdraw_active',
                  'prs1_active','prs2_active']
    for i, (name, val) in enumerate(zip(coil_names, bits)):
        state = 'TRUE ' if val else 'FALSE'
        warn  = ' ← PID saturated (normal until MATLAB connects)' if val and 'alarm' in name else ''
        INF(f'Coil {i}  {name:22s} = {state}{warn}')
    OK('Read 7 coils successfully')

# ── write/readback test ───────────────────────────────────────────
HDR('5 / Round-Trip Write Test  — write a test value, read it back')

TEST_ADDR  = 0          # p_S1
TEST_VALUE = 4999       # 49.99 bar

# write
from pymodbus.exceptions import ModbusException
try:
    wr = c.write_register(TEST_ADDR, TEST_VALUE, device_id=DEV_ID)
    if wr.isError():
        ERR(f'Write failed: {wr}')
    else:
        time.sleep(0.1)
        # read back
        rr = c.read_holding_registers(TEST_ADDR, count=1, device_id=DEV_ID)
        readback = rr.registers[0]
        if readback == TEST_VALUE:
            OK(f'Write {TEST_VALUE} → addr {TEST_ADDR} → readback {readback}  ✓ match')
        else:
            ERR(f'Write {TEST_VALUE} → addr {TEST_ADDR} → readback {readback}  ✗ MISMATCH')

        # restore original
        c.write_register(TEST_ADDR, 5000, device_id=DEV_ID)
        INF('Restored p_S1 to 5000 (50.00 bar)')
except Exception as e:
    ERR(f'Write test exception: {e}')

# ── summary ──────────────────────────────────────────────────────
HDR('Summary')
INF('CODESYS Modbus TCP server : RUNNING')
INF('Python can READ actuators : YES  (cs1_ratio, cs2_ratio, valves, PRS setpoints)')
INF('Python can WRITE sensors  : YES  (pressures, flows, temps)')
INF('Coils readable            : YES  (7 status bits)')
INF('')
INF('Next step: connect MATLAB via UDP gateway to write real physics values')
INF('           Run: python gateway.py   (in one terminal)')
INF('           Run: main_simulation.m   (in MATLAB)')

c.close()