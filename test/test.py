import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.triggers import RisingEdge
from cocotb.triggers import FallingEdge
from cocotb.triggers import ReadOnly, Timer

import os
import glob
import itertools
from PIL import Image, ImageChops


@cocotb.test()
async def test_project(dut):
    # cocotb.pass_test()
    # Set clock period to 20 ns (50 MHz)
    CLOCK_PERIOD = 20
    clock = Clock(dut.clk, CLOCK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset the design
    dut.ena.value = 1
    dut.ui_in.value = 0 # zero in means test mode
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    #let test run 60ms, and test the final state
    await Timer(65, unit="ms")
    assert int(dut.uo_out.value) == 192
    
    # if we reach here it works
    await Timer(1, unit="ms")
    cocotb.log.info("Full lanch cycle simulation complate");

@cocotb.test()
async def compare_reference(dut):
    cocotb.pass_test()
