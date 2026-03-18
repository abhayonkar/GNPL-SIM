"""
gateway.py — Gas Pipeline Gateway: MATLAB <-> CODESYS Modbus TCP
================================================================
Synchronisation: REQUEST-RESPONSE — Python blocks on mat.receive(),
processes, replies immediately. MATLAB send→receive = one step.
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

ACTUATOR_NAMES  = ['cs1_ratio_cmd','cs2_ratio_cmd',
                   'valve_E8_cmd','valve_E14_cmd','valve_E15_cmd',
                   'prs1_setpoint','prs2_setpoint',
                   'cs1_power_kW','cs2_power_kW']
ACTUATOR_SCALES = [1000, 1000, 1000, 1000, 1000, 100, 100, 10, 10]
ACTUATOR_UNITS  = ['ratio','ratio','0-1','0-1','0-1','bar','bar','kW','kW']

COIL_NAMES = ['emergency_shutdown','cs1_alarm','cs2_alarm',
              'sto_inject_active','sto_withdraw_active',
              'prs1_active','prs2_active']

ACTUATOR_DEFAULTS = {
    'cs1_ratio_cmd': 1250, 'cs2_ratio_cmd': 1150,
    'valve_E8_cmd': 1000,  'valve_E14_cmd': 1000, 'valve_E15_cmd': 1000,
    'prs1_setpoint': 3000, 'prs2_setpoint': 2500,
    'cs1_power_kW': 0,     'cs2_power_kW': 0,
}
COIL_DEFAULTS = {n: False for n in COIL_NAMES}


def load_config(path='config.yaml') -> dict:
    with open(path) as f:
        return yaml.safe_load(f)

def to_signed(val: int) -> int:
    return val - 65536 if val > 32767 else val


# =========================================================================
# Modbus client
# =========================================================================
class ModbusGateway:

    def __init__(self, host, port, unit_id):
        self.host    = host
        self.port    = port
        self.unit_id = unit_id
        self._client = None

    def connect(self) -> bool:
        from pymodbus.client import ModbusTcpClient
        self._client = ModbusTcpClient(self.host, port=self.port, timeout=2)
        ok = self._client.connect()
        if ok:
            logger.info(f'Modbus connected  {self.host}:{self.port}  unit={self.unit_id}')
        return ok

    def disconnect(self):
        if self._client:
            try: self._client.close()
            except: pass

    def is_connected(self) -> bool:
        return self._client is not None and self._client.is_socket_open()

    def write_sensors(self, sensor_ints: dict) -> bool:
        if not self.is_connected():
            return False
        try:
            regs = []
            for name in NODE_NAMES:
                regs.append(sensor_ints.get(f'p_{name}', 5000) & 0xFFFF)
            for name in EDGE_NAMES:
                regs.append(sensor_ints.get(f'q_{name}', 0) & 0xFFFF)
            for name in NODE_NAMES:
                regs.append(sensor_ints.get(f'T_{name}', 2850) & 0xFFFF)
            regs.append(sensor_ints.get('demand_scalar', 750) & 0xFFFF)
            r = self._client.write_registers(0, regs, device_id=self.unit_id)
            return not r.isError()
        except Exception as e:
            logger.warning(f'write_sensors: {e}')
            return False

    def read_actuators(self) -> dict:
        if not self.is_connected():
            return dict(ACTUATOR_DEFAULTS)
        try:
            r = self._client.read_holding_registers(100, count=9,
                                                    device_id=self.unit_id)
            if r.isError():
                return dict(ACTUATOR_DEFAULTS)
            return {name: to_signed(r.registers[i])
                    for i, name in enumerate(ACTUATOR_NAMES)}
        except Exception as e:
            logger.warning(f'read_actuators: {e}')
            return dict(ACTUATOR_DEFAULTS)

    def read_coils(self) -> dict:
        if not self.is_connected():
            return dict(COIL_DEFAULTS)
        try:
            r = self._client.read_coils(0, count=7, device_id=self.unit_id)
            if r.isError():
                return dict(COIL_DEFAULTS)
            return {name: bool(r.bits[i]) for i, name in enumerate(COIL_NAMES)}
        except Exception as e:
            logger.warning(f'read_coils: {e}')
            return dict(COIL_DEFAULTS)

    def reconnect(self):
        self.disconnect()
        time.sleep(1)
        return self.connect()


# =========================================================================
# UDP bridge to MATLAB
# =========================================================================
class MatlabUDP:

    SEND_BYTES = 61 * 8   # 488 bytes  MATLAB → Python
    RECV_BYTES = 16 * 8   # 128 bytes  Python → MATLAB

    def __init__(self, cfg):
        m = cfg['matlab']
        self._rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._rx.bind((m['recv_ip'], m['recv_port']))
        self._rx.settimeout(m.get('timeout_s', 0.5))
        self._tx      = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._tx_ip   = m['send_ip']
        self._tx_port = m['send_port']
        logger.info(f'UDP RX listening on {m["recv_ip"]}:{m["recv_port"]}')
        logger.info(f'UDP TX will reply to {m["send_ip"]}:{m["send_port"]}')

    def receive(self) -> dict | None:
        try:
            data, _ = self._rx.recvfrom(65535)
            if len(data) < self.SEND_BYTES:
                return None
            vals = struct.unpack('61d', data[:self.SEND_BYTES])
            ints = {}
            for i, name in enumerate(NODE_NAMES):
                ints[f'p_{name}'] = int(round(vals[i]    * 100))
            for i, name in enumerate(EDGE_NAMES):
                ints[f'q_{name}'] = int(round(vals[20+i] * 100))
            for i, name in enumerate(NODE_NAMES):
                ints[f'T_{name}'] = int(round(vals[40+i] * 10))
            ints['demand_scalar'] = int(round(vals[60] * 1000))
            return ints
        except socket.timeout:
            return None
        except Exception as e:
            logger.error(f'UDP receive error: {e}')
            return None

    def send(self, act_ints: dict, coils: dict):
        vals = [
            float(act_ints.get('cs1_ratio_cmd',  1250)),
            float(act_ints.get('cs2_ratio_cmd',  1150)),
            float(act_ints.get('valve_E8_cmd',   1000)),
            float(act_ints.get('valve_E14_cmd',  1000)),
            float(act_ints.get('valve_E15_cmd',  1000)),
            float(act_ints.get('prs1_setpoint',  3000)),
            float(act_ints.get('prs2_setpoint',  2500)),
            float(act_ints.get('cs1_power_kW',      0)),
            float(act_ints.get('cs2_power_kW',      0)),
            float(coils.get('emergency_shutdown',  False)),
            float(coils.get('cs1_alarm',           False)),
            float(coils.get('cs2_alarm',           False)),
            float(coils.get('sto_inject_active',   False)),
            float(coils.get('sto_withdraw_active', False)),
            float(coils.get('prs1_active',         False)),
            float(coils.get('prs2_active',         False)),
        ]
        self._tx.sendto(struct.pack(f'{len(vals)}d', *vals),
                        (self._tx_ip, self._tx_port))

    def close(self):
        try: self._rx.close()
        except: pass
        try: self._tx.close()
        except: pass


# =========================================================================
# Transaction logger  ← method names fixed
# =========================================================================
class TransactionLogger:

    def __init__(self, log_dir='logs'):
        os.makedirs(log_dir, exist_ok=True)
        ts   = datetime.now().strftime('%Y%m%d_%H%M%S')
        path = os.path.join(log_dir, f'modbus_transactions_{ts}.csv')
        self._fh = open(path, 'w', newline='')
        self._w  = csv.writer(self._fh)
        self._w.writerow(['timestamp_ms','fc','direction','modbus_addr',
                          'variable','int16_raw','eng_value','unit'])
        logger.info(f'Transaction log: {path}')

    def log_sensors(self, sensor_ints: dict):
        """Log all 61 sensor registers written to PLC (FC16 WRITE)."""
        ts = int(time.time() * 1000)
        scales = ([100]*20) + ([100]*20) + ([10]*20) + [1000]
        names  = ([f'p_{n}' for n in NODE_NAMES] +
                  [f'q_{e}' for e in EDGE_NAMES] +
                  [f'T_{n}' for n in NODE_NAMES] +
                  ['demand_scalar'])
        units  = (['bar']*20) + (['kg/s']*20) + (['K']*20) + ['']
        for i, (name, scale, unit) in enumerate(zip(names, scales, units)):
            raw = sensor_ints.get(name, 0)
            eng = raw / scale
            self._w.writerow([ts, 'FC16', 'WRITE', 40001+i,
                               name, raw, f'{eng:.4f}', unit])

    def log_actuators(self, act_ints: dict):
        """Log 9 actuator registers read from PLC (FC3 READ)."""
        ts = int(time.time() * 1000)
        for i, (name, scale, unit) in enumerate(
                zip(ACTUATOR_NAMES, ACTUATOR_SCALES, ACTUATOR_UNITS)):
            raw = act_ints.get(name, 0)
            eng = raw / scale
            self._w.writerow([ts, 'FC3', 'READ', 40101+i,
                               name, raw, f'{eng:.4f}', unit])

    def log_coils(self, coils: dict):
        """Log 7 coil values read from PLC (FC1 READ)."""
        ts = int(time.time() * 1000)
        for i, name in enumerate(COIL_NAMES):
            val = coils.get(name, False)
            self._w.writerow([ts, 'FC1', 'READ', 1+i,
                               name, int(val), str(val), 'BOOL'])

    def flush(self): self._fh.flush()
    def close(self): self._fh.close()


# =========================================================================
# Main loop — request-response, synchronised to MATLAB
# =========================================================================
def run_gateway(config: dict):

    plc_cfg = config['plc']
    plc   = ModbusGateway(plc_cfg['host'], plc_cfg['port'], plc_cfg['unit_id'])
    mat   = MatlabUDP(config)
    txlog = TransactionLogger(config.get('log_dir', 'logs'))

    while not plc.connect():
        logger.warning('PLC not ready — retrying in 3s...')
        time.sleep(3)

    log_every  = config.get('log_every_n_cycles', 10)
    stats      = {'cycles':0, 'plc_errors':0, 'timeouts':0, 'reconnects':0}
    last_act   = dict(ACTUATOR_DEFAULTS)
    last_coils = dict(COIL_DEFAULTS)

    logger.info('Gateway ready — waiting for MATLAB UDP packets on port 5005')
    logger.info('Timing: REQUEST-RESPONSE (synchronised to MATLAB)')
    logger.info('Press Ctrl+C to stop.')

    try:
        while True:

            # 1. Block until MATLAB sends a physics packet
            sensor_ints = mat.receive()

            if sensor_ints is None:
                stats['timeouts'] += 1
                if stats['timeouts'] % 20 == 0:
                    elapsed = stats['timeouts'] * config['matlab'].get('timeout_s', 0.5)
                    logger.info(f'Waiting for MATLAB... ({elapsed:.0f}s elapsed, '
                                f'{stats["timeouts"]} timeouts)')
                continue

            # 2. Write sensor values to PLC
            ok = plc.write_sensors(sensor_ints)
            if not ok:
                stats['plc_errors'] += 1
                if not plc.is_connected():
                    logger.warning('PLC disconnected — reconnecting...')
                    plc.reconnect()
                    stats['reconnects'] += 1

            # 3. Read PLC actuator outputs
            act   = plc.read_actuators()
            coils = plc.read_coils()
            if act:   last_act   = act
            if coils: last_coils = coils

            # 4. Reply to MATLAB IMMEDIATELY (synchronisation point)
            mat.send(last_act, last_coils)

            # 5. Log (every N cycles, AFTER reply so latency is unaffected)
            stats['cycles'] += 1
            c = stats['cycles']

            if c % log_every == 0:
                txlog.log_sensors(sensor_ints)
                txlog.log_actuators(last_act)
                txlog.log_coils(last_coils)
                txlog.flush()

            if c % 1000 == 0:
                p_s1  = sensor_ints.get('p_S1',  5000) / 100.0
                p_d1  = sensor_ints.get('p_D1',  0)    / 100.0
                r_cs1 = last_act.get('cs1_ratio_cmd', 1250) / 1000.0
                logger.info(f'Step {c:6d}  p_S1={p_s1:.1f}bar  p_D1={p_d1:.1f}bar  '
                            f'cs1_ratio={r_cs1:.3f}')

    except KeyboardInterrupt:
        logger.info('Keyboard interrupt — stopping gateway.')
    finally:
        txlog.close()
        mat.close()
        plc.disconnect()
        logger.info(f'Gateway stopped. Cycles={stats["cycles"]}  '
                    f'PLCerrors={stats["plc_errors"]}  '
                    f'Timeouts={stats["timeouts"]}')


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description='Gas Pipeline Modbus Gateway')
    ap.add_argument('--config', default='config.yaml')
    args = ap.parse_args()
    run_gateway(load_config(args.config))