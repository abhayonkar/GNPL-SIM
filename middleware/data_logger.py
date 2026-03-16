"""
data_logger.py  —  Complete Modbus Data Logger
================================================
Logs ALL 70 holding registers + 7 coils to CSV every cycle.
Runs standalone (no MATLAB needed) — just needs CODESYS running.

CSV columns (80 total):
  timestamp_ms          — Unix ms
  datetime              — human readable
  cycle                 — sample counter
  [20 pressures]        — p_S1..p_D6        bar   (raw/100)
  [20 flows]            — q_E1..q_E20       kg/s  (raw/100)
  [20 temperatures]     — T_S1..T_D6        K     (raw/10)
  demand_scalar         —                         (raw/1000)
  [9 actuators]         — cs1_ratio..power        (raw/scale)
  [7 coils]             — bool status bits

Usage:
  python data_logger.py                          # logs forever, Ctrl+C to stop
  python data_logger.py --duration 3600          # log for 1 hour
  python data_logger.py --interval 0.1           # 10 Hz (default)
  python data_logger.py --interval 1.0           # 1 Hz (smaller files)
  python data_logger.py --host 192.168.5.74 --port 1502

Install: pip install pymodbus
"""

import argparse
import csv
import os
import signal
import struct
import sys
import time
from datetime import datetime

# =========================================================================
# Register map — matches PLC_PRG exactly
# =========================================================================
NODE_NAMES = ['S1','J1','CS1','J2','J3','J4','CS2','J5','J6','PRS1',
              'J7','STO','PRS2','S2','D1','D2','D3','D4','D5','D6']
EDGE_NAMES = ['E1','E2','E3','E4','E5','E6','E7','E8','E9','E10',
              'E11','E12','E13','E14','E15','E16','E17','E18','E19','E20']

# (column_name, modbus_addr_0based, scale, unit)
SENSOR_MAP = [
    *[(f'p_{n}_bar',    i,    100,  'bar')  for i, n in enumerate(NODE_NAMES)],
    *[(f'q_{e}_kgs',    20+i, 100,  'kg/s') for i, e in enumerate(EDGE_NAMES)],
    *[(f'T_{n}_K',      40+i, 10,   'K')    for i, n in enumerate(NODE_NAMES)],
    ('demand_scalar',   60,   1000, ''),
]  # 61 registers, addr 0-60

ACTUATOR_MAP = [
    ('cs1_ratio_cmd',   100,  1000, ''),
    ('cs2_ratio_cmd',   101,  1000, ''),
    ('valve_E8_cmd',    102,  1000, 'bool'),
    ('valve_E14_cmd',   103,  1000, 'bool'),
    ('valve_E15_cmd',   104,  1000, 'bool'),
    ('prs1_setpoint_bar', 105, 100, 'bar'),
    ('prs2_setpoint_bar', 106, 100, 'bar'),
    ('cs1_power_kW',    107,  10,   'kW'),
    ('cs2_power_kW',    108,  10,   'kW'),
]  # 9 registers, addr 100-108

COIL_MAP = [
    ('emergency_shutdown',   0),
    ('cs1_alarm',            1),
    ('cs2_alarm',            2),
    ('sto_inject_active',    3),
    ('sto_withdraw_active',  4),
    ('prs1_active',          5),
    ('prs2_active',          6),
]  # 7 coils, addr 0-6

# Build CSV header
HEADER = (
    ['timestamp_ms', 'datetime_utc', 'cycle']
    + [name for name, *_ in SENSOR_MAP]       # 61 sensor columns
    + [name for name, *_ in ACTUATOR_MAP]     # 9 actuator columns
    + [name for name, _ in COIL_MAP]          # 7 coil columns
    # raw integer columns (for protocol analysis)
    + [f'{name}_raw' for name, *_ in SENSOR_MAP]
    + [f'{name}_raw' for name, *_ in ACTUATOR_MAP]
)
# Total columns: 3 + 61 + 9 + 7 + 61 + 9 = 150


def to_signed(val: int) -> int:
    """Convert unsigned 16-bit Modbus register to signed INT."""
    return val - 65536 if val > 32767 else val


def connect_modbus(host: str, port: int, unit_id: int, retries: int = 999):
    """Connect with retry loop. Returns client or raises."""
    from pymodbus.client import ModbusTcpClient
    attempt = 0
    while attempt < retries:
        try:
            client = ModbusTcpClient(host, port=port, timeout=3)
            if client.connect():
                print(f'[{ts()}] Connected to {host}:{port}  unit={unit_id}')
                return client
        except Exception as e:
            pass
        attempt += 1
        print(f'[{ts()}] Connection failed ({attempt}) — retrying in 3s...')
        time.sleep(3)
    raise RuntimeError('Cannot connect to PLC')


def ts():
    return datetime.now().strftime('%H:%M:%S')


def _read_registers(client, address, count, unit_id):
    """pymodbus 3.12+: count= and device_id= are keyword-only args"""
    return client.read_holding_registers(address, count=count, device_id=unit_id)


def _read_coils(client, address, count, unit_id):
    """pymodbus 3.12+: count= and device_id= are keyword-only args"""
    return client.read_coils(address, count=count, device_id=unit_id)


def read_all(client, unit_id: int):
    """
    Read all registers in 3 Modbus transactions:
      FC3 addr=0  count=61  -> sensors (holding regs 40001-40061)
      FC3 addr=100 count=9  -> actuators (holding regs 40101-40109)
      FC1 addr=0  count=7   -> coils

    Returns (sensor_raw, actuator_raw, coil_vals) or None on error.
    """
    try:
        # Sensors: addr 0, count 61
        r_sens = _read_registers(client, 0, 61, unit_id)
        if r_sens.isError():
            return None

        # Actuators: addr 100, count 9
        r_act = _read_registers(client, 100, 9, unit_id)
        if r_act.isError():
            return None

        # Coils: addr 0, count 7
        r_coil = _read_coils(client, 0, 7, unit_id)
        if r_coil.isError():
            coil_vals = [False] * 7
        else:
            coil_vals = list(r_coil.bits[:7])

        sensor_raw   = [to_signed(v) for v in r_sens.registers]   # 61 values
        actuator_raw = [to_signed(v) for v in r_act.registers]    # 9 values

        return sensor_raw, actuator_raw, coil_vals

    except Exception as e:
        print(f'[{ts()}] Read error: {e}')
        return None


def build_row(cycle: int, sensor_raw: list, actuator_raw: list,
              coil_vals: list) -> list:
    """Build one CSV row with timestamp, engineering values, and raw integers."""
    now_ms  = int(time.time() * 1000)
    now_str = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'

    # Engineering values (float, rounded to 4 dp)
    sensor_eng   = [round(raw / scale, 4)
                    for raw, (_, _, scale, _) in zip(sensor_raw, SENSOR_MAP)]
    actuator_eng = [round(raw / scale, 4)
                    for raw, (_, _, scale, _) in zip(actuator_raw, ACTUATOR_MAP)]
    coil_ints    = [int(v) for v in coil_vals]

    return (
        [now_ms, now_str, cycle]
        + sensor_eng           # 61 engineering values
        + actuator_eng         # 9 engineering values
        + coil_ints            # 7 bool as 0/1
        + sensor_raw           # 61 raw integers
        + actuator_raw         # 9 raw integers
    )


def make_output_path(log_dir: str) -> str:
    os.makedirs(log_dir, exist_ok=True)
    ts_str = datetime.now().strftime('%Y%m%d_%H%M%S')
    return os.path.join(log_dir, f'pipeline_data_{ts_str}.csv')


def run_logger(host: str, port: int, unit_id: int, interval: float,
               duration: float, log_dir: str, flush_every: int):

    from pymodbus.client import ModbusTcpClient

    out_path = make_output_path(log_dir)
    print(f'[{ts()}] Output: {out_path}')
    print(f'[{ts()}] Columns: {len(HEADER)}  '
          f'(3 meta + 61 sensor_eng + 9 act_eng + 7 coils + 61 sensor_raw + 9 act_raw)')
    print(f'[{ts()}] Rate: {1/interval:.1f} Hz  '
          f'Duration: {"∞" if duration == 0 else f"{duration}s"}')

    client   = connect_modbus(host, port, unit_id)
    fh       = open(out_path, 'w', newline='')
    writer   = csv.writer(fh)
    writer.writerow(HEADER)

    cycle      = 0
    errors     = 0
    start_time = time.time()
    stop       = False

    def handle_signal(sig, frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, handle_signal)
    if hasattr(signal, 'SIGTERM'):
        signal.signal(signal.SIGTERM, handle_signal)

    print(f'[{ts()}] Logging started. Ctrl+C to stop.')
    print(f'{"Cycle":>8}  {"p_S1 bar":>10}  {"p_D1 bar":>10}  '
          f'{"cs1_ratio":>10}  {"e_shutdown":>12}  {"errors":>7}')
    print('-' * 70)

    try:
        while not stop:
            t0 = time.time()

            # Check duration limit
            if duration > 0 and (t0 - start_time) >= duration:
                print(f'\n[{ts()}] Duration limit reached ({duration}s)')
                break

            # Reconnect if dropped
            if not client.is_socket_open():
                print(f'[{ts()}] Reconnecting...')
                try:
                    client.close()
                    client = connect_modbus(host, port, unit_id, retries=30)
                except RuntimeError:
                    break

            # Read all registers
            result = read_all(client, unit_id)
            if result is None:
                errors += 1
                time.sleep(interval)
                continue

            sensor_raw, actuator_raw, coil_vals = result
            row = build_row(cycle, sensor_raw, actuator_raw, coil_vals)
            writer.writerow(row)
            cycle += 1

            # Flush periodically
            if cycle % flush_every == 0:
                fh.flush()

            # Console status every 100 cycles
            if cycle % 100 == 0:
                p_s1    = sensor_raw[0]  / 100.0
                p_d1    = sensor_raw[14] / 100.0
                cs1_r   = actuator_raw[0] / 1000.0
                e_shut  = int(coil_vals[0])
                elapsed = t0 - start_time
                rate    = cycle / elapsed if elapsed > 0 else 0
                print(f'{cycle:>8}  {p_s1:>10.2f}  {p_d1:>10.2f}  '
                      f'{cs1_r:>10.4f}  {e_shut:>12}  {errors:>7}  '
                      f'({rate:.1f} Hz)')

            # Maintain interval
            elapsed = time.time() - t0
            sleep_t = max(0, interval - elapsed)
            time.sleep(sleep_t)

    finally:
        fh.flush()
        fh.close()
        try: client.close()
        except Exception: pass

        elapsed_total = time.time() - start_time
        print(f'\n{"="*70}')
        print(f'Logger stopped.')
        print(f'  Cycles logged : {cycle}')
        print(f'  Errors        : {errors}')
        print(f'  Duration      : {elapsed_total:.1f}s')
        print(f'  Actual rate   : {cycle/elapsed_total:.2f} Hz' if elapsed_total > 0 else '')
        print(f'  Output file   : {out_path}')
        print(f'  File size     : {os.path.getsize(out_path)/1024:.1f} KB')
        print(f'{"="*70}')


# =========================================================================
if __name__ == '__main__':
    ap = argparse.ArgumentParser(
        description='Gas Pipeline Modbus Data Logger — logs all 70 registers + 7 coils')
    ap.add_argument('--host',        default='192.168.5.74',
                    help='PLC IP address (default: 192.168.5.74)')
    ap.add_argument('--port',        type=int, default=1502,
                    help='Modbus port (default: 1502)')
    ap.add_argument('--unit',        type=int, default=1,
                    help='Modbus unit ID (default: 1)')
    ap.add_argument('--interval',    type=float, default=0.1,
                    help='Logging interval in seconds (default: 0.1 = 10 Hz)')
    ap.add_argument('--duration',    type=float, default=0,
                    help='Log duration in seconds, 0=forever (default: 0)')
    ap.add_argument('--log-dir',     default='logs',
                    help='Output directory (default: logs/)')
    ap.add_argument('--flush-every', type=int, default=100,
                    help='Flush to disk every N cycles (default: 100)')
    ap.add_argument('--print-header', action='store_true',
                    help='Print CSV header and exit')

    args = ap.parse_args()

    if args.print_header:
        print('\n'.join(f'{i:3d}  {col}' for i, col in enumerate(HEADER)))
        print(f'\nTotal columns: {len(HEADER)}')
        sys.exit(0)

    run_logger(
        host       = args.host,
        port       = args.port,
        unit_id    = args.unit,
        interval   = args.interval,
        duration   = args.duration,
        log_dir    = args.log_dir,
        flush_every = args.flush_every,
    )