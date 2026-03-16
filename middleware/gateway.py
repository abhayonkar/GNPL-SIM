"""
gateway.py — Gas Pipeline Gateway: MATLAB <-> CODESYS Modbus TCP
================================================================
Holding registers : 67 total
  Sensor inputs   : 60 (addr 0-59,   Modbus 40001-40060)
  Actuator outputs:  7 (addr 100-106, Modbus 40101-40107)
Coils             :  3 (addr 0-2,    Modbus 00001-00003)

All values are INT in CODESYS. MATLAB decodes:
  pressure  = int16 / 100   (bar)
  flow      = int16 / 100   (kg/s)
  temp      = int16 / 10    (K)
  ratio     = int16 / 1000
  valve     = int16 / 1000  (0=closed, 1=open)

Install: pip install pymodbus pyyaml
Run:     python gateway.py
"""

import socket, struct, yaml, time, logging, csv, os, argparse
from datetime import datetime

logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

NODE_NAMES = ['S1','J1','CS1','J2','J3','J4','CS2','J5','J6','PRS1',
              'J7','STO','PRS2','S2','D1','D2','D3','D4','D5','D6']
EDGE_NAMES = ['E1','E2','E3','E4','E5','E6','E7','E8','E9','E10',
              'E11','E12','E13','E14','E15','E16','E17','E18','E19','E20']

# Register addresses (0-based CODESYS = Modbus - 40001)
PRESSURE_ADDR  = 0    # 20 registers  addr 0-19
FLOW_ADDR      = 20   # 20 registers  addr 20-39
TEMP_ADDR      = 40   # 20 registers  addr 40-59
ACTUATOR_ADDR  = 100  # 7 registers   addr 100-106
COIL_ADDR      = 0    # 3 coils       addr 0-2

ACTUATOR_NAMES = ['cs1_ratio_cmd','cs2_ratio_cmd',
                  'valve_E8_cmd','valve_E14_cmd','valve_E15_cmd',
                  'prs1_setpoint','prs2_setpoint']
COIL_NAMES     = ['emergency_shutdown','cs1_alarm','cs2_alarm']

# Scales for encoding (MATLAB value * scale = INT register value)
P_SCALE = 100    # bar   -> INT
Q_SCALE = 100    # kg/s  -> INT
T_SCALE = 10     # K     -> INT


def load_config(path='config.yaml') -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def to_int16(val: float, scale: int) -> int:
    """Convert engineering float to signed INT16 register value."""
    raw = int(round(val * scale))
    return max(-32768, min(32767, raw))

def from_int16(raw: int, scale: int) -> float:
    """Convert signed INT16 register value to engineering float."""
    if raw > 32767: raw -= 65536   # unsigned -> signed
    return raw / scale


# =========================================================================
# CODESYS Modbus TCP
# =========================================================================
class CodesysModbus:

    def __init__(self, config):
        self.host    = config['plc'].get('host', '127.0.0.1')
        self.port    = config['plc'].get('port', 502)
        self.unit_id = config['plc'].get('unit_id', 1)
        self._client = None

    def connect(self) -> bool:
        try:
            from pymodbus.client import ModbusTcpClient
            self._client = ModbusTcpClient(self.host, port=self.port, timeout=3)
            ok = self._client.connect()
            if ok:
                logger.info(f'Modbus connected  {self.host}:{self.port}  unit={self.unit_id}')
            else:
                logger.error(f'Modbus refused at {self.host}:{self.port}')
                logger.error('Check CODESYS: runtime started, PLC running (F5), port=502')
            return ok
        except ImportError:
            raise ImportError('pip install pymodbus')
        except Exception as e:
            logger.error(f'Modbus connect: {e}')
            return False

    def disconnect(self):
        if self._client:
            try: self._client.close()
            except Exception: pass

    def is_connected(self) -> bool:
        return self._client is not None and self._client.is_socket_open()

    def write_pressures(self, pressures: list) -> bool:
        return self._write_block(PRESSURE_ADDR, pressures, P_SCALE)

    def write_flows(self, flows: list) -> bool:
        return self._write_block(FLOW_ADDR, flows, Q_SCALE)

    def write_temps(self, temps: list) -> bool:
        return self._write_block(TEMP_ADDR, temps, T_SCALE)

    def write_sensors(self, sensor_ints: dict) -> bool:
        """Write all sensor INT values from MATLAB UDP packet.
        sensor_ints keys: p_S1..p_D6, q_E1..q_E20, T_S1..T_D6, demand_scalar
        Values are already scaled INTs — write directly as registers.
        """
        if not self.is_connected(): return False
        try:
            # Build 61-register block (addr 0-60)
            regs = []
            for name in NODE_NAMES:
                regs.append(int(sensor_ints.get(f'p_{name}', 5000)) & 0xFFFF)
            for name in EDGE_NAMES:
                regs.append(int(sensor_ints.get(f'q_{name}', 0)) & 0xFFFF)
            for name in NODE_NAMES:
                regs.append(int(sensor_ints.get(f'T_{name}', 2850)) & 0xFFFF)
            regs.append(int(sensor_ints.get('demand_scalar', 750)) & 0xFFFF)
            result = self._client.write_registers(0, regs, device_id=self.unit_id)
            return not result.isError()
        except Exception as e:
            logger.warning(f'write_sensors: {e}')
            return False

    def _write_block(self, start_addr: int, values: list, scale: int) -> bool:
        if not self.is_connected(): return False
        try:
            regs = [to_int16(v, scale) & 0xFFFF for v in values]
            result = self._client.write_registers(start_addr, regs,
                                                  device_id=self.unit_id)
            return not result.isError()
        except Exception as e:
            logger.warning(f'Modbus write block @{start_addr}: {e}')
            return False

    def read_actuators(self) -> dict:
        """Read 7 actuator registers addr 100-106 (FC3)."""
        if not self.is_connected(): return {}
        try:
            rr = self._client.read_holding_registers(ACTUATOR_ADDR, count=7,
                                                     device_id=self.unit_id)
            if rr.isError():
                logger.warning(f'FC3 read error: {rr}')
                return {}
            scales = [1000, 1000, 1000, 1000, 1000, 100, 100]
            return {name: from_int16(rr.registers[i], scales[i])
                    for i, name in enumerate(ACTUATOR_NAMES)}
        except Exception as e:
            logger.warning(f'Modbus actuator read: {e}')
            return {}

    def read_coils(self) -> dict:
        """Read 3 coils addr 0-2 (FC1)."""
        if not self.is_connected(): return {}
        try:
            rr = self._client.read_coils(COIL_ADDR, count=3, device_id=self.unit_id)
            if rr.isError(): return {}
            return {name: bool(rr.bits[i]) for i, name in enumerate(COIL_NAMES)}
        except Exception as e:
            logger.warning(f'Modbus coil read: {e}')
            return {}


# =========================================================================
# Siemens S7-1200 (swap via config.yaml plc.type = "s7")
# =========================================================================
class S7PLC:

    def __init__(self, config):
        self.host         = config['plc']['host']
        self.rack         = config['plc'].get('rack', 0)
        self.slot         = config['plc'].get('slot', 1)
        self.db_sensors   = config['plc'].get('db_sensors', 1)
        self.db_actuators = config['plc'].get('db_actuators', 2)
        self._client      = None

    def connect(self) -> bool:
        try:
            import snap7
            self._client = snap7.client.Client()
            self._client.connect(self.host, self.rack, self.slot)
            ok = self._client.get_connected()
            if ok: logger.info(f'S7 connected  {self.host}')
            return ok
        except ImportError:
            raise ImportError('pip install python-snap7')

    def disconnect(self):
        if self._client: self._client.disconnect()

    def is_connected(self) -> bool:
        return self._client is not None and self._client.get_connected()

    def write_pressures(self, pressures):
        return self._write_int_block(0, pressures, P_SCALE)

    def write_flows(self, flows):
        return self._write_int_block(40, flows, Q_SCALE)

    def write_temps(self, temps):
        return self._write_int_block(80, temps, T_SCALE)

    def _write_int_block(self, byte_offset, values, scale):
        if not self.is_connected(): return False
        try:
            buf = bytearray(len(values) * 2)
            for i, v in enumerate(values):
                raw = to_int16(v, scale)
                buf[i*2]   = (raw >> 8) & 0xFF
                buf[i*2+1] = raw & 0xFF
            self._client.db_write(self.db_sensors, byte_offset, buf)
            return True
        except Exception as e:
            logger.warning(f'S7 write: {e}')
            return False

    def read_actuators(self):
        if not self.is_connected(): return {}
        try:
            buf = self._client.db_read(self.db_actuators, 0, 14)
            scales = [1000, 1000, 1000, 1000, 1000, 100, 100]
            result = {}
            for i, name in enumerate(ACTUATOR_NAMES):
                raw = (buf[i*2] << 8) | buf[i*2+1]
                result[name] = from_int16(raw, scales[i])
            return result
        except Exception as e:
            logger.warning(f'S7 read: {e}')
            return {}

    def read_coils(self): return {}


# =========================================================================
# UDP bridge to MATLAB
# =========================================================================
class MatlabUDP:

    def __init__(self, config):
        m = config['matlab']
        self._rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._rx.bind((m['recv_ip'], m['recv_port']))
        self._rx.settimeout(m.get('timeout_s', 0.5))
        self._tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._tx_addr = (m['send_ip'], m['send_port'])

    def receive(self) -> dict | None:
        """
        Receive physics state from MATLAB.
        Packet: 61 x float64 = 488 bytes
          [0:19]  20 pressures  bar
          [20:39] 20 flows      kg/s
          [40:59] 20 temps      K
          [60]     1 demand_scalar
        Returns sensor_ints dict (already scaled to INT) or None on timeout.
        """
        try:
            data, _ = self._rx.recvfrom(65535)
            if len(data) < 488: return None
            vals = struct.unpack('61d', data[:488])

            sensor_ints = {}
            for i, name in enumerate(NODE_NAMES):
                sensor_ints[f'p_{name}'] = int(round(vals[i]    * 100))
            for i, name in enumerate(EDGE_NAMES):
                sensor_ints[f'q_{name}'] = int(round(vals[20+i] * 100))
            for i, name in enumerate(NODE_NAMES):
                sensor_ints[f'T_{name}'] = int(round(vals[40+i] * 10))
            sensor_ints['demand_scalar'] = int(round(vals[60] * 1000))
            return sensor_ints
        except socket.timeout:
            return None
        except Exception as ex:
            logger.error(f'UDP recv: {ex}')
            return None

    def send(self, actuator_ints: dict, coils: dict):
        """
        Send PLC actuator raw INTs + coil bools to MATLAB.
        Packet: 16 x float64 = 128 bytes
          [0:8]  9 actuator raw INT values (MATLAB divides by scale)
          [9:15] 7 coil bool values (0.0 or 1.0)
        """
        vals = [
            float(actuator_ints.get('cs1_ratio_cmd', 1250)),
            float(actuator_ints.get('cs2_ratio_cmd', 1150)),
            float(actuator_ints.get('valve_E8_cmd',  1000)),
            float(actuator_ints.get('valve_E14_cmd', 1000)),
            float(actuator_ints.get('valve_E15_cmd', 1000)),
            float(actuator_ints.get('prs1_setpoint', 3000)),
            float(actuator_ints.get('prs2_setpoint', 2500)),
            float(actuator_ints.get('cs1_power_kW',     0)),
            float(actuator_ints.get('cs2_power_kW',     0)),
            float(coils.get('emergency_shutdown',  False)),
            float(coils.get('cs1_alarm',           False)),
            float(coils.get('cs2_alarm',           False)),
            float(coils.get('sto_inject_active',   False)),
            float(coils.get('sto_withdraw_active', False)),
            float(coils.get('prs1_active',         False)),
            float(coils.get('prs2_active',         False)),
        ]
        self._tx.sendto(struct.pack(f'{len(vals)}d', *vals), self._tx_addr)

    def close(self):
        self._rx.close(); self._tx.close()


# =========================================================================
# Transaction logger — the protocol-layer dataset
# =========================================================================
class TransactionLogger:

    def __init__(self, log_dir='logs'):
        os.makedirs(log_dir, exist_ok=True)
        ts   = datetime.now().strftime('%Y%m%d_%H%M%S')
        path = os.path.join(log_dir, f'modbus_transactions_{ts}.csv')
        self._fh = open(path, 'w', newline='')
        self._w  = csv.writer(self._fh)
        self._w.writerow(['timestamp_ms','fc','direction',
                          'modbus_addr','variable','int16_raw','eng_value','unit'])
        logger.info(f'Transaction log: {path}')

    def log_pressures(self, pressures):
        ts = int(time.time() * 1000)
        for i, (name, val) in enumerate(zip(NODE_NAMES, pressures)):
            self._w.writerow([ts,'FC16','WRITE', 40001+i,
                               f'p_{name}', to_int16(val, P_SCALE),
                               f'{val:.2f}', 'bar'])

    def log_flows(self, flows):
        ts = int(time.time() * 1000)
        for i, (name, val) in enumerate(zip(EDGE_NAMES, flows)):
            self._w.writerow([ts,'FC16','WRITE', 40021+i,
                               f'q_{name}', to_int16(val, Q_SCALE),
                               f'{val:.3f}', 'kg/s'])

    def log_temps(self, temps):
        ts = int(time.time() * 1000)
        for i, (name, val) in enumerate(zip(NODE_NAMES, temps)):
            self._w.writerow([ts,'FC16','WRITE', 40041+i,
                               f'T_{name}', to_int16(val, T_SCALE),
                               f'{val:.1f}', 'K'])

    def log_actuators(self, actuators):
        ts = int(time.time() * 1000)
        scales = [1000, 1000, 1000, 1000, 1000, 100, 100]
        units  = ['ratio','ratio','0/1','0/1','0/1','bar','bar']
        for i, name in enumerate(ACTUATOR_NAMES):
            val = actuators.get(name, 0)
            self._w.writerow([ts,'FC3','READ', 40101+i,
                               name, to_int16(val, scales[i]),
                               f'{val:.4f}', units[i]])

    def log_coils(self, coils):
        ts = int(time.time() * 1000)
        for i, name in enumerate(COIL_NAMES):
            val = coils.get(name, False)
            self._w.writerow([ts,'FC1','READ', 1+i,
                               name, int(val), str(val), 'BOOL'])

    def flush(self): self._fh.flush()
    def close(self): self._fh.close()


# =========================================================================
# Main loop
# =========================================================================
def run_gateway(config: dict):

    plc_type = config['plc'].get('type', 'modbus').lower()
    if plc_type in ('modbus', 'codesys'):
        plc = CodesysModbus(config)
        logger.info('PLC: CODESYS Modbus TCP')
    elif plc_type == 's7':
        plc = S7PLC(config)
        logger.info(f'PLC: Siemens S7  {config["plc"]["host"]}')
    else:
        raise ValueError(f'Unknown plc.type: {plc_type}')

    matlab = MatlabUDP(config)
    txlog  = TransactionLogger(config.get('log_dir', 'logs'))

    while not plc.connect():
        logger.info('PLC not ready — retrying in 3s...')
        time.sleep(3)

    cycle_s   = config.get('cycle_time_s', 0.1)
    log_every = config.get('log_every_n_cycles', 10)
    stats     = {'cycles':0, 'plc_errors':0, 'timeouts':0, 'reconnects':0}
    last_act   = {name: 1250 if 'ratio' in name else 1000
                  for name in ACTUATOR_NAMES}
    last_coils = {name: False for name in COIL_NAMES}

    logger.info('Gateway running. Ctrl+C to stop.')
    logger.info(f'Registers: 60 sensor inputs (40001-40060) + '
                f'7 actuator outputs (40101-40107) + 3 coils (00001-00003)')

    try:
        while True:
            t0 = time.time()

            if not plc.is_connected():
                logger.warning('PLC disconnected — reconnecting...')
                time.sleep(2)
                plc.connect()
                stats['reconnects'] += 1

            sensor = matlab.receive()
            do_log = (stats['cycles'] % log_every == 0)

            if sensor is None:
                stats['timeouts'] += 1
            else:
                # sensor is already a dict of raw INTs keyed by variable name
                ok = plc.write_sensors(sensor)
                if not ok: stats['plc_errors'] += 1

                if do_log:
                    txlog.log_sensors(sensor)

            act   = plc.read_actuators()
            coils = plc.read_coils()
            if act:   last_act   = act
            if coils: last_coils = coils
            matlab.send(last_act, last_coils)

            if do_log and act:
                txlog.log_actuators(last_act)
                txlog.log_coils(last_coils)
                txlog.flush()

            stats['cycles'] += 1
            if stats['cycles'] % 1000 == 0:
                logger.info(f'Cycles={stats["cycles"]}  '
                            f'Errors={stats["plc_errors"]}  '
                            f'Timeouts={stats["timeouts"]}  '
                            f'Reconnects={stats["reconnects"]}')

            time.sleep(max(0, cycle_s - (time.time() - t0)))

    except KeyboardInterrupt:
        logger.info('Stopped.')
    finally:
        matlab.close(); plc.disconnect(); txlog.close()
        logger.info(f'Total cycles: {stats["cycles"]}')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--config', default='config.yaml')
    args = ap.parse_args()
    run_gateway(load_config(args.config))