"""
gateway.py — Gas Pipeline Gateway: MATLAB <-> CODESYS Modbus TCP
================================================================
Phase 2 additions:
  - NetworkLogger integration (src/dst IP + device ID per transaction)
  - attack_id carried through from MATLAB packet for correct labels
  - sensor poll and actuator write logged with device-level identity

The attack_id is passed in the 62nd float of the MATLAB UDP packet
(extended from 61 to 62 doubles). If MATLAB sends only 61, attack_id=0.
"""

import socket, struct, yaml, time, logging, csv, os, argparse
from datetime import datetime
from network_logger import NetworkLogger

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

# Device that "owns" each sensor variable — used for dst_id in READ logs
SENSOR_DEVICE_MAP = {
    'p_S1':  'PLC_001', 'p_J1':  'RTU_005', 'p_CS1': 'PLC_003',
    'p_J2':  'RTU_006', 'p_J3':  'RTU_007', 'p_J4':  'RTU_008',
    'p_CS2': 'PLC_004', 'p_J5':  'RTU_009', 'p_J6':  'RTU_010',
    'p_PRS1':'PLC_012', 'p_J7':  'RTU_011', 'p_STO': 'PLC_014',
    'p_PRS2':'PLC_013', 'p_S2':  'PLC_002',
    'p_D1':  'RTU_018', 'p_D2':  'RTU_019', 'p_D3':  'RTU_020',
    'p_D4':  'RTU_021', 'p_D5':  'RTU_022', 'p_D6':  'RTU_023',
}
ACTUATOR_DEVICE_MAP = {
    'cs1_ratio_cmd': 'PLC_003', 'cs2_ratio_cmd': 'PLC_004',
    'valve_E8_cmd':  'RTU_015', 'valve_E14_cmd': 'RTU_016',
    'valve_E15_cmd': 'RTU_017', 'prs1_setpoint': 'PLC_012',
    'prs2_setpoint': 'PLC_013', 'cs1_power_kW':  'PLC_003',
    'cs2_power_kW':  'PLC_004',
}
P_REGISTER_BASE   = 40001
FLOW_REGISTER_BASE = 40021
ACT_REGISTER_BASE  = 40101


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

    SEND_BYTES_61 = 61 * 8   # legacy: 61 doubles
    SEND_BYTES_62 = 62 * 8   # extended: 61 + attack_id float
    RECV_BYTES    = 16 * 8

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

    def receive(self) -> tuple[dict | None, int]:
        """Returns (sensor_ints, attack_id). attack_id=0 if not in packet."""
        try:
            data, _ = self._rx.recvfrom(65535)
            n_doubles = len(data) // 8
            if n_doubles < 61:
                return None, 0

            vals = struct.unpack(f'{n_doubles}d', data[:n_doubles * 8])
            ints = {}
            for i, name in enumerate(NODE_NAMES):
                ints[f'p_{name}'] = int(round(vals[i]    * 100))
            for i, name in enumerate(EDGE_NAMES):
                ints[f'q_{name}'] = int(round(vals[20+i] * 100))
            for i, name in enumerate(NODE_NAMES):
                ints[f'T_{name}'] = int(round(vals[40+i] * 10))
            ints['demand_scalar'] = int(round(vals[60] * 1000))

            # attack_id is 62nd double (index 61) if present
            attack_id = int(round(vals[61])) if n_doubles >= 62 else 0

            return ints, attack_id
        except socket.timeout:
            return None, 0
        except Exception as e:
            logger.error(f'UDP receive error: {e}')
            return None, 0

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
# Modbus transaction logger (physics-level, kept for backward compat)
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
        ts = int(time.time() * 1000)
        for i, (name, scale, unit) in enumerate(
                zip(ACTUATOR_NAMES, ACTUATOR_SCALES, ACTUATOR_UNITS)):
            raw = act_ints.get(name, 0)
            eng = raw / scale
            self._w.writerow([ts, 'FC3', 'READ', 40101+i,
                               name, raw, f'{eng:.4f}', unit])

    def log_coils(self, coils: dict):
        ts = int(time.time() * 1000)
        for i, name in enumerate(COIL_NAMES):
            val = coils.get(name, False)
            self._w.writerow([ts, 'FC1', 'READ', 1+i,
                               name, int(val), str(val), 'BOOL'])

    def flush(self): self._fh.flush()
    def close(self): self._fh.close()


# =========================================================================
# Main loop
# =========================================================================
def run_gateway(config: dict):

    plc_cfg = config['plc']
    plc    = ModbusGateway(plc_cfg['host'], plc_cfg['port'], plc_cfg['unit_id'])
    mat    = MatlabUDP(config)
    txlog  = TransactionLogger(config.get('log_dir', 'logs'))

    # Phase 2: device-level network logger
    net_log = NetworkLogger(log_dir=config.get('log_dir', 'logs'),
                            flush_every=50)

    while not plc.connect():
        logger.warning('PLC not ready — retrying in 3s...')
        time.sleep(3)

    log_every  = config.get('log_every_n_cycles', 10)
    stats      = {'cycles':0, 'plc_errors':0, 'timeouts':0, 'reconnects':0}
    last_act   = dict(ACTUATOR_DEFAULTS)
    last_coils = dict(COIL_DEFAULTS)
    sim_s      = 0.0   # approximate simulation time (incremented per cycle)

    logger.info('Gateway ready — waiting for MATLAB UDP packets on port 5005')

    try:
        while True:
            sensor_ints, attack_id = mat.receive()
            if sensor_ints is None:
                stats['timeouts'] += 1
                continue

            ts_ms = int(time.time() * 1000)
            sim_s += 1.0   # each UDP packet = log_every*dt = 10*0.1 = 1.0 s of sim time
                           # IMPORTANT: gateway receives once per MATLAB log step (1 Hz),
                           # not once per physics step (10 Hz). Using 0.1 here would
                           # make network timestamps 10x too small, breaking merge_cps_dataset.

            ok = plc.write_sensors(sensor_ints)
            if not ok:
                stats['plc_errors'] += 1
                if not plc.is_connected():
                    logger.warning('PLC disconnected — reconnecting...')
                    plc.reconnect()
                    stats['reconnects'] += 1

            act   = plc.read_actuators()
            coils = plc.read_coils()
            if act:   last_act   = act
            if coils: last_coils = coils

            mat.send(last_act, last_coils)

            stats['cycles'] += 1
            c = stats['cycles']

            if c % log_every == 0:
                txlog.log_sensors(sensor_ints)
                txlog.log_actuators(last_act)
                txlog.log_coils(last_coils)
                txlog.flush()

                # Phase 2: log sensor reads with device identity
                sensor_eng = {}
                for name in NODE_NAMES:
                    raw = sensor_ints.get(f'p_{name}', 5000)
                    sensor_eng[f'p_{name}_bar'] = raw / 100.0
                net_log.log_sensor_poll(ts_ms, sim_s, sensor_eng, attack_id)

                # Log actuator writes from SCADA to PLCs
                act_eng = {}
                for name, scale in zip(ACTUATOR_NAMES, ACTUATOR_SCALES):
                    act_eng[name] = last_act.get(name, 0) / scale
                net_log.log_actuator_write(ts_ms, sim_s, act_eng, attack_id)

            if c % 1000 == 0:
                p_s1  = sensor_ints.get('p_S1',  5000) / 100.0
                p_d1  = sensor_ints.get('p_D1',  0)    / 100.0
                r_cs1 = last_act.get('cs1_ratio_cmd', 1250) / 1000.0
                logger.info(f'Step {c:6d}  p_S1={p_s1:.1f}bar  p_D1={p_d1:.1f}bar  '
                            f'cs1_ratio={r_cs1:.3f}  attack_id={attack_id}')

    except KeyboardInterrupt:
        logger.info('Keyboard interrupt — stopping gateway.')
    finally:
        txlog.close()
        net_log.close()
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
