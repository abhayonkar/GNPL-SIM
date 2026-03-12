"""
gateway.py
==========
Python middleware gateway: MATLAB <-> PLC

Data flow:
  MATLAB (UDP) --> gateway --> PLC (Modbus or S7)
  PLC (Modbus or S7) --> gateway --> MATLAB (UDP)

TO SWAP PLC:
  Change ONE line below:
    plc = ModbusPLC(config)   # CODESYS or any Modbus TCP device
    plc = S7PLC(config)       # Siemens S7-1200 / S7-300

Run: python gateway.py [--config config.yaml]

Install: pip install pymodbus pyyaml numpy
"""

import socket
import struct
import yaml
import time
import logging
import csv
import os
import argparse
from datetime import datetime
from plc_interface import ModbusPLC, S7PLC

# -------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

# =========================================================================
# Configuration
# =========================================================================
def load_config(path='config.yaml') -> dict:
    with open(path) as f:
        return yaml.safe_load(f)

# =========================================================================
# UDP communication with MATLAB
# =========================================================================
class MatlabUDP:
    """
    Receive sensor arrays from MATLAB and send actuator commands back.

    MATLAB sends:   [nNodes pressures | nEdges flows | nNodes temps] as doubles
    Gateway sends:  [comp1_ratio | comp2_ratio | valve1 | valve2 | valve3] as doubles
    """

    def __init__(self, config: dict):
        self.recv_ip   = config['matlab']['recv_ip']
        self.recv_port = config['matlab']['recv_port']     # MATLAB sends here
        self.send_ip   = config['matlab']['send_ip']
        self.send_port = config['matlab']['send_port']     # MATLAB listens here
        self.n_nodes   = config['network']['n_nodes']      # 20
        self.n_edges   = config['network']['n_edges']      # 20
        self.timeout   = config['matlab'].get('timeout_s', 0.5)

        self._sock_recv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock_recv.bind((self.recv_ip, self.recv_port))
        self._sock_recv.settimeout(self.timeout)

        self._sock_send = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def receive_sensor_data(self) -> dict | None:
        """
        Receive sensor packet from MATLAB.
        Returns dict with 'pressures', 'flows', 'temps' or None on timeout.
        """
        try:
            data, _ = self._sock_recv.recvfrom(65535)
            n = self.n_nodes
            e = self.n_edges
            expected = (n + e + n) * 8   # doubles = 8 bytes each
            if len(data) < expected:
                logger.warning(f'Short packet: {len(data)} < {expected} bytes')
                return None
            vals = struct.unpack(f'{n+e+n}d', data[:expected])
            return {
                'pressures': list(vals[:n]),
                'flows':     list(vals[n:n+e]),
                'temps':     list(vals[n+e:]),
            }
        except socket.timeout:
            return None
        except Exception as ex:
            logger.error(f'UDP recv error: {ex}')
            return None

    def send_actuator_commands(self, cmds: dict):
        """
        Send actuator commands to MATLAB.
        cmds: {'CS1_ratio_cmd', 'CS2_ratio_cmd', 'valve_E8_cmd',
                'valve_E14_cmd', 'valve_E15_cmd'}
        """
        packet = struct.pack('5d',
            cmds.get('CS1_ratio_cmd',  1.25),
            cmds.get('CS2_ratio_cmd',  1.15),
            float(cmds.get('valve_E8_cmd',  1)),
            float(cmds.get('valve_E14_cmd', 1)),
            float(cmds.get('valve_E15_cmd', 1)),
        )
        self._sock_send.sendto(packet, (self.send_ip, self.send_port))

    def close(self):
        self._sock_recv.close()
        self._sock_send.close()

# =========================================================================
# Transaction logger (creates the protocol-layer dataset)
# =========================================================================
class TransactionLogger:
    """
    Logs every sensor write and actuator read with precise timestamps.
    This is the protocol-layer dataset that makes your research unique.
    Columns: timestamp_ms, direction, register_name, value, raw_register
    """

    def __init__(self, log_dir='logs'):
        os.makedirs(log_dir, exist_ok=True)
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        self.path = os.path.join(log_dir, f'modbus_transactions_{ts}.csv')
        self._fh  = open(self.path, 'w', newline='')
        self._writer = csv.writer(self._fh)
        self._writer.writerow(['timestamp_ms', 'direction',
                                'register_name', 'value', 'raw_register_value'])
        logger.info(f'Transaction log: {self.path}')

    def log_write(self, name: str, value: float, raw: int):
        ts = int(time.time() * 1000)
        self._writer.writerow([ts, 'WRITE', name, f'{value:.4f}', raw])

    def log_read(self, name: str, value: float, raw: int):
        ts = int(time.time() * 1000)
        self._writer.writerow([ts, 'READ', name, f'{value:.4f}', raw])

    def flush(self):
        self._fh.flush()

    def close(self):
        self._fh.close()

# =========================================================================
# Main gateway loop
# =========================================================================
def run_gateway(config: dict):

    logger.info('=== Gas Pipeline Gateway Starting ===')
    logger.info(f'Network: {config["network"]["n_nodes"]} nodes, '
                f'{config["network"]["n_edges"]} edges')

    # -----------------------------------------------------------------
    # SELECT PLC TYPE HERE — change to S7PLC for Siemens S7-1200
    # -----------------------------------------------------------------
    plc_type = config['plc'].get('type', 'modbus').lower()
    if plc_type == 'modbus':
        plc = ModbusPLC(config)
        logger.info('PLC type: Modbus TCP (CODESYS)')
    elif plc_type == 's7':
        plc = S7PLC(config)
        logger.info('PLC type: Siemens S7 (snap7)')
    else:
        raise ValueError(f'Unknown plc.type: {plc_type}')
    # -----------------------------------------------------------------

    matlab  = MatlabUDP(config)
    txlog   = TransactionLogger(log_dir=config.get('log_dir', 'logs'))

    node_names = config['network']['node_names']
    edge_names = config['network']['edge_names']

    # Connect PLC
    if not plc.connect():
        logger.error('Cannot connect to PLC — check runtime/network')
        return

    cycle_s = config.get('cycle_time_s', 0.1)
    stats   = {'cycles': 0, 'plc_errors': 0, 'matlab_timeouts': 0}

    logger.info('Gateway running. Press Ctrl+C to stop.')

    try:
        while True:
            t0 = time.time()

            # 1. Receive sensor data from MATLAB
            sensor_data = matlab.receive_sensor_data()
            if sensor_data is None:
                stats['matlab_timeouts'] += 1
                if stats['matlab_timeouts'] % 100 == 0:
                    logger.warning(f'MATLAB timeout #{stats["matlab_timeouts"]}')
            else:
                # 2. Build named sensor dict for PLC
                plc_data = {}
                for i, name in enumerate(node_names):
                    plc_data[f'{name}_pressure_bar'] = sensor_data['pressures'][i]
                    plc_data[f'{name}_temp_K']        = sensor_data['temps'][i]
                for i, name in enumerate(edge_names):
                    plc_data[f'{name}_flow_kgs'] = sensor_data['flows'][i]

                # 3. Write sensors to PLC
                ok = plc.write_sensors(plc_data)
                if not ok:
                    stats['plc_errors'] += 1

                # Log writes (protocol dataset)
                for name, val in list(plc_data.items())[:5]:   # log first 5
                    txlog.log_write(name, val, int(val * 100))

            # 4. Read actuator commands from PLC
            cmds = plc.read_actuators()
            if cmds:
                matlab.send_actuator_commands(cmds)
                for name, val in cmds.items():
                    txlog.log_read(name, val, int(val * 100))

            stats['cycles'] += 1
            if stats['cycles'] % 1000 == 0:
                txlog.flush()
                logger.info(f'Cycles: {stats["cycles"]}  '
                            f'PLC errors: {stats["plc_errors"]}  '
                            f'MATLAB timeouts: {stats["matlab_timeouts"]}')

            # Maintain cycle time
            elapsed = time.time() - t0
            sleep_t = max(0, cycle_s - elapsed)
            time.sleep(sleep_t)

    except KeyboardInterrupt:
        logger.info('Shutdown requested.')
    finally:
        matlab.close()
        plc.disconnect()
        txlog.close()
        logger.info(f'Gateway stopped. Total cycles: {stats["cycles"]}')


# =========================================================================
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Gas Pipeline Gateway')
    parser.add_argument('--config', default='config.yaml')
    args = parser.parse_args()
    config = load_config(args.config)
    run_gateway(config)