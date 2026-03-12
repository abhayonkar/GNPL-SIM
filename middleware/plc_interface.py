"""
plc_interface.py
================
Abstract PLC communication interface.

Swap between CODESYS (Modbus/TCP) and Siemens S7-1200 (S7 protocol)
by changing ONE line in gateway.py:

    plc = ModbusPLC(config)    # CODESYS Control Win / any Modbus PLC
    plc = S7PLC(config)        # Siemens S7-1200 / S7-300 / S7-400

Both implement identical read_actuators() / write_sensors() interface.
MATLAB and gateway.py never need to change when swapping PLC hardware.

Register/DB mapping is defined entirely in config.yaml.
"""

from abc import ABC, abstractmethod
import struct
import logging

logger = logging.getLogger(__name__)


# =========================================================================
# Abstract base — the contract both PLCs must satisfy
# =========================================================================
class PLCInterface(ABC):

    @abstractmethod
    def connect(self) -> bool:
        """Open connection to PLC. Returns True on success."""

    @abstractmethod
    def disconnect(self):
        """Close connection cleanly."""

    @abstractmethod
    def write_sensors(self, data: dict) -> bool:
        """
        Write MATLAB sensor values to PLC.
        data keys match config.yaml sensor register names.
        Example: {'S1_pressure_bar': 51.2, 'E1_flow_kgs': 3.4, ...}
        Returns True on success.
        """

    @abstractmethod
    def read_actuators(self) -> dict:
        """
        Read PLC actuator outputs.
        Returns dict matching config.yaml actuator register names.
        Example: {'CS1_ratio_cmd': 1.25, 'CS2_ratio_cmd': 1.15,
                  'valve_E8_cmd': 1, 'valve_E14_cmd': 1, 'valve_E15_cmd': 0}
        """

    @abstractmethod
    def is_connected(self) -> bool:
        """Returns True if connection is alive."""


# =========================================================================
# CODESYS / any Modbus TCP PLC
# =========================================================================
class ModbusPLC(PLCInterface):
    """
    Modbus TCP client for CODESYS Control Win (or any Modbus-capable PLC).

    Holding registers (FC3/FC16) starting at address 40001.
    Values are scaled to int16: e.g. pressure * 100 -> register value.
    Scaling factors defined in config.yaml per register.

    Install: pip install pymodbus
    """

    def __init__(self, config: dict):
        self.host    = config['plc']['host']
        self.port    = config['plc']['port']          # typically 502
        self.unit_id = config['plc']['unit_id']       # typically 1
        self.sensors   = config['registers']['sensors']
        self.actuators = config['registers']['actuators']
        self._client  = None

    def connect(self) -> bool:
        try:
            from pymodbus.client import ModbusTcpClient
            self._client = ModbusTcpClient(self.host, port=self.port,
                                           timeout=3)
            ok = self._client.connect()
            if ok:
                logger.info(f'Modbus connected to {self.host}:{self.port}')
            else:
                logger.error(f'Modbus connection failed to {self.host}:{self.port}')
            return ok
        except ImportError:
            raise ImportError("Install pymodbus: pip install pymodbus")

    def disconnect(self):
        if self._client:
            self._client.close()

    def is_connected(self) -> bool:
        return self._client is not None and self._client.is_socket_open()

    def write_sensors(self, data: dict) -> bool:
        if not self.is_connected():
            return False
        try:
            for name, reg_cfg in self.sensors.items():
                if name in data:
                    addr   = reg_cfg['address'] - 40001   # 0-based
                    scale  = reg_cfg.get('scale', 100)
                    value  = int(data[name] * scale)
                    value  = max(-32768, min(32767, value))
                    self._client.write_register(addr, value & 0xFFFF,
                                                slave=self.unit_id)
            return True
        except Exception as e:
            logger.warning(f'Modbus write error: {e}')
            return False

    def read_actuators(self) -> dict:
        result = {}
        if not self.is_connected():
            return result
        try:
            for name, reg_cfg in self.actuators.items():
                addr  = reg_cfg['address'] - 40001
                scale = reg_cfg.get('scale', 100)
                rr    = self._client.read_holding_registers(addr, 1,
                                                            slave=self.unit_id)
                if not rr.isError():
                    raw = rr.registers[0]
                    # Convert unsigned 16-bit back to signed
                    if raw > 32767:
                        raw -= 65536
                    result[name] = raw / scale
        except Exception as e:
            logger.warning(f'Modbus read error: {e}')
        return result


# =========================================================================
# Siemens S7-1200 (or S7-300/S7-400/S7-1500)
# =========================================================================
class S7PLC(PLCInterface):
    """
    Siemens S7 protocol client using python-snap7.

    Values are read/written to a Data Block (DB) in the PLC.
    DB number and byte offsets defined in config.yaml under
    registers.sensors[n].db and registers.sensors[n].offset.

    Data types: REAL (4 bytes, float) at each offset.

    Install: pip install python-snap7
    Also install snap7 DLL/SO from:
      https://github.com/gijzelaerr/python-snap7

    S7-1200 SETUP:
      1. In TIA Portal: enable "Permit access from PUT/GET communication"
         in PLC properties > Protection & Security
      2. In TIA Portal: set DB as "Non-optimized" (standard layout)
      3. Note your PLC IP, rack=0, slot=1 for S7-1200
    """

    def __init__(self, config: dict):
        self.host    = config['plc']['host']
        self.rack    = config['plc'].get('rack', 0)
        self.slot    = config['plc'].get('slot', 1)    # S7-1200: slot=1
        self.db_sensors   = config['plc'].get('db_sensors', 1)
        self.db_actuators = config['plc'].get('db_actuators', 2)
        self.sensors   = config['registers']['sensors']
        self.actuators = config['registers']['actuators']
        self._client  = None

    def connect(self) -> bool:
        try:
            import snap7
            self._client = snap7.client.Client()
            self._client.connect(self.host, self.rack, self.slot)
            ok = self._client.get_connected()
            if ok:
                logger.info(f'S7 connected to {self.host} rack={self.rack} slot={self.slot}')
            return ok
        except ImportError:
            raise ImportError("Install python-snap7: pip install python-snap7")

    def disconnect(self):
        if self._client:
            self._client.disconnect()

    def is_connected(self) -> bool:
        return self._client is not None and self._client.get_connected()

    def write_sensors(self, data: dict) -> bool:
        if not self.is_connected():
            return False
        try:
            import snap7.util
            for name, reg_cfg in self.sensors.items():
                if name in data:
                    offset = reg_cfg['offset']   # byte offset in DB
                    buf = bytearray(4)
                    snap7.util.set_real(buf, 0, float(data[name]))
                    self._client.db_write(self.db_sensors, offset, buf)
            return True
        except Exception as e:
            logger.warning(f'S7 write error: {e}')
            return False

    def read_actuators(self) -> dict:
        result = {}
        if not self.is_connected():
            return result
        try:
            import snap7.util
            for name, reg_cfg in self.actuators.items():
                offset = reg_cfg['offset']
                buf = self._client.db_read(self.db_actuators, offset, 4)
                result[name] = snap7.util.get_real(buf, 0)
        except Exception as e:
            logger.warning(f'S7 read error: {e}')
        return result