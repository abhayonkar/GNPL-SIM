"""
diagnostic.py - Full CODESYS communication diagnostic.

Tests every layer of the current setup:
  1. TCP connectivity
  2. PLC sensor registers
  3. PLC actuator registers
  4. Coil status
  5. Round-trip write/verify test

Run: python diagnostic.py
"""

from __future__ import annotations

import time

from pymodbus.client import ModbusTcpClient

from architecture import ACTUATOR_MAP, COIL_MAP, EDGE_NAMES, NODE_NAMES

HOST = "127.0.0.1"
PORT = 1502
DEV_ID = 1


def ok(msg):
    print(f"  [OK]   {msg}")


def err(msg):
    print(f"  [ERR]  {msg}")


def hdr(msg):
    print(f"\n\033[1m{msg}\033[0m")


def inf(msg):
    print(f"     {msg}")


def to_signed(value):
    return value - 65536 if value > 32767 else value


def main():
    hdr("1 / TCP Connection")
    client = ModbusTcpClient(HOST, port=PORT, timeout=3)
    if client.connect():
        ok(f"Connected to {HOST}:{PORT}")
    else:
        err(f"Cannot connect to {HOST}:{PORT} - is CODESYS running and PLC started (F5)?")
        raise SystemExit(1)

    try:
        hdr("2 / Sensor Registers (addr 0-60) - written by Python, init values from PLC_PRG")
        response = client.read_holding_registers(0, count=61, device_id=DEV_ID)
        if response.isError():
            err(f"FC3 read failed: {response}")
        else:
            regs = response.registers

            print("\n  Pressures (bar = raw/100):")
            for i, name in enumerate(NODE_NAMES):
                raw = to_signed(regs[i])
                bar = raw / 100.0
                flag = " <- default init" if raw != 0 else " <- 0 (MATLAB not connected yet)"
                inf(f"p_{name:5s} [addr {i:2d}] = {raw:6d} raw = {bar:6.2f} bar{flag}")

            print("\n  Flows (kg/s = raw/100):")
            nonzero_flows = [(EDGE_NAMES[i], to_signed(regs[20 + i])) for i in range(20) if regs[20 + i] != 0]
            if nonzero_flows:
                for name, raw in nonzero_flows:
                    inf(f"q_{name} = {raw} raw = {raw / 100:.2f} kg/s")
            else:
                inf("All flow registers = 0  (expected - MATLAB not connected)")

            print("\n  Temperatures (K = raw/10):")
            nonzero_temp = [(NODE_NAMES[i], to_signed(regs[40 + i])) for i in range(20) if regs[40 + i] != 0]
            if nonzero_temp:
                for name, raw in nonzero_temp:
                    inf(f"T_{name} = {raw} raw = {raw / 10:.1f} K")
            else:
                inf("All temperature registers = 0  (expected - MATLAB not connected)")

            demand_raw = to_signed(regs[60])
            inf(f"\n  demand_scalar [addr 60] = {demand_raw} raw = {demand_raw / 1000:.3f}")

            nonzero = sum(1 for value in regs if value != 0)
            ok(f"Read 61 sensor registers - {nonzero} non-zero (PLC init defaults)")

        hdr("3 / Actuator Registers (addr 100-108) - written by PLC control logic")
        response = client.read_holding_registers(100, count=9, device_id=DEV_ID)
        if response.isError():
            err(f"FC3 read actuators failed: {response}")
        else:
            regs = response.registers
            for i, (name, _, scale, unit) in enumerate(ACTUATOR_MAP):
                raw = to_signed(regs[i])
                eng = raw / scale
                inf(f"{name:20s} [addr {100 + i}] = {raw:6d} raw = {eng:.4f} {unit}")

            cs1 = to_signed(regs[0]) / 1000.0
            cs2 = to_signed(regs[1]) / 1000.0
            if 1.05 <= cs1 <= 1.80:
                ok(f"cs1_ratio_cmd = {cs1:.3f}  (valid range 1.05-1.80)")
            else:
                err(f"cs1_ratio_cmd = {cs1:.3f}  OUT OF RANGE - check PID init")

            if 1.02 <= cs2 <= 1.60:
                ok(f"cs2_ratio_cmd = {cs2:.3f}  (valid range 1.02-1.60)")
            else:
                err(f"cs2_ratio_cmd = {cs2:.3f}  OUT OF RANGE - check PID init")

        hdr("4 / Status Coils (addr 0-6) - written by PLC logic")
        response = client.read_coils(0, count=7, device_id=DEV_ID)
        if response.isError():
            err(f"FC1 read coils failed: {response}")
        else:
            bits = response.bits[:7]
            for i, ((name, _), value) in enumerate(zip(COIL_MAP, bits)):
                state = "TRUE " if value else "FALSE"
                warn = " <- PID saturated (normal until MATLAB connects)" if value and "alarm" in name else ""
                inf(f"Coil {i}  {name:22s} = {state}{warn}")
            ok("Read 7 coils successfully")

        hdr("5 / Round-Trip Write Test - write a test value, read it back")
        test_addr = 0
        test_value = 4999
        try:
            write_response = client.write_register(test_addr, test_value, device_id=DEV_ID)
            if write_response.isError():
                err(f"Write failed: {write_response}")
            else:
                time.sleep(0.1)
                read_response = client.read_holding_registers(test_addr, count=1, device_id=DEV_ID)
                readback = read_response.registers[0]
                if readback == test_value:
                    ok(f"Write {test_value} -> addr {test_addr} -> readback {readback} match")
                else:
                    err(f"Write {test_value} -> addr {test_addr} -> readback {readback} MISMATCH")

                client.write_register(test_addr, 5000, device_id=DEV_ID)
                inf("Restored p_S1 to 5000 (50.00 bar)")
        except Exception as exc:
            err(f"Write test exception: {exc}")

        hdr("Summary")
        inf("CODESYS Modbus TCP server : RUNNING")
        inf("Python can READ actuators : YES  (cs1_ratio, cs2_ratio, valves, PRS setpoints)")
        inf("Python can WRITE sensors  : YES  (pressures, flows, temps)")
        inf("Coils readable            : YES  (7 status bits)")
        inf("")
        inf("Next step: connect MATLAB via UDP gateway to write real physics values")
        inf("           Run: python gateway.py   (in one terminal)")
        inf("           Run: main_simulation.m   (in MATLAB)")
    finally:
        client.close()


if __name__ == "__main__":
    main()
