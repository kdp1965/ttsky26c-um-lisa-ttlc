# test.py - tt_um_lisa in the testbench: the debugger over the UART, and a
# program from the flash model.
#   make                                 test_debugger, test_bringup (firmware.hex)
#   make IHX=../../lisa-tools/sdcc_test/test_core.ihx [CACHE=1] [TIMEOUT=clocks]
#                                        test_program: run it, expect ALL PASSED
import os
import cocotb
from cocotb.triggers import ClockCycles

from lisa import Lisa, Timeout, REG_STATUS, REG_LISA1_BASE, REG_PC, CHAR_CYCLES


def plusarg(name, default=None):
    return cocotb.plusargs.get(name, default)


async def start(dut):
    lisa = Lisa(dut)
    await lisa.reset()
    return lisa


@cocotb.test(skip=plusarg('DEFAULT') is None)
async def test_debugger(dut):
    """the debugger answers: version, register write / read back, halted at reset"""
    lisa = await start(dut)
    ver = await lisa.version()
    dut._log.info('version: %s' % ver)
    assert ver == 'lisav1.2', ver
    assert (await lisa.read_reg(REG_STATUS)) & 1 == 1, 'the core is not halted after reset'
    await lisa.write_reg(REG_LISA1_BASE, 0x1234)
    await lisa.check_reg(REG_LISA1_BASE, 0x1234)
    await lisa.write_reg(REG_LISA1_BASE, 0)
    await lisa.write_reg(REG_PC, 0x0123)
    await lisa.check_reg(REG_PC, 0x0123)


@cocotb.test(skip=plusarg('DEFAULT') is None)
async def test_bringup(dut):
    """progs/hello.hex prints its banner from the flash and echoes a character"""
    lisa = await start(dut)
    await lisa.setup(cache=False, quad=True)
    text = await lisa.run(timeout=400 * CHAR_CYCLES, stop_at=('ready\n',))
    assert 'hello from sdcc' in text, text
    await lisa.tx(ord('?'))
    assert (await lisa.rx(100 * CHAR_CYCLES)) == ord('?'), 'no echo'


@cocotb.test(skip=plusarg('DEFAULT') is None)
async def test_uart_burst(dut):
    """a burst of characters to hello's echo loop: the receive FIFO keeps them
    (TT07 held one byte and lost every other character of a burst)"""
    lisa = await start(dut)
    await lisa.setup(cache=False, quad=True)
    await lisa.run(timeout=400 * CHAR_CYCLES, stop_at=('ready\n',))
    burst = 'burst-of-8'
    for c in burst:
        await lisa.tx(ord(c))
    got = ''
    for _ in burst:
        v = await lisa.rx(200 * CHAR_CYCLES)
        if v is None:
            break
        got += chr(v)
    assert got == burst, 'echoed %r' % got


@cocotb.test(skip=plusarg('DEFAULT') is not None)
async def test_program(dut):
    """+FIRMWARE=<hex>: run it (the data cache on with +CACHE) and expect ALL PASSED"""
    lisa = await start(dut)
    cache = plusarg('CACHE') is not None
    timeout = int(plusarg('TIMEOUT', 2_000_000))
    await lisa.setup(cache=cache, quad=plusarg('SPI') is None)
    dut._log.info('running %s with the data cache %s' % (plusarg('PROGRAM', plusarg('FIRMWARE')), 'on' if cache else 'off'))
    text = await lisa.run(timeout=timeout)
    assert 'ALL PASSED' in text, 'the program did not pass: %r' % text[-200:]
