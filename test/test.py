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
async def test_BIST(dut):
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
async def test_SYSTEM(dut):
    # cocotb.pass_test()
    # Set clock period to 20 ns (50 MHz)
    CLOCK_PERIOD = 20
    clock = Clock(dut.clk, CLOCK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset the design
    dut.ena.value = 1
    dut.ui_in.value = 131  #bits 0,1 are active low
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # charge should rise after reset
    cocotb.log.info("Charge = %s", dut.uo_out.value[3] )
    assert dut.uo_out.value[3] == 0
    while dut.uo_out.value[3] != 1:
        await ClockCycles(dut.clk, 1)
    cocotb.log.info("Charge started")
    cocotb.log.info("Charge = %s", dut.uo_out.value[3] )
    assert dut.uo_out.value[3] == 1
    assert dut.uo_out.value[5] == 0 # dump is still zero
    assert int(dut.ad_vcap.value) > 1000
    assert int(dut.ad_vcap.value) < 2000

    # wait for charge to complete and arm led high
    while dut.uo_out.value[3] == 1:
        await ClockCycles(dut.clk, 1)
    cocotb.log.info("Charge done, arm_led %s", dut.uo_out.value[0] )
    assert dut.uo_out.value[0] == 1

    # wait for speaker tone
    while dut.uo_out.value[2] == 1:
        await ClockCycles(dut.clk, 1)
    cocotb.log.info("ontinuity tone, cont_led %s", dut.uo_out.value[1] );

    # wait 1ms and assert /launch button
    await Timer(1, unit="ms")
    cocotb.log.info("Press Button")
    dut.ui_in.value = 130 #bits 0,1 are active low

    # wait 6ms for debounce and de-assert launch
    await Timer(6, unit="ms")
    cocotb.log.info("Release Button");
    dut.ui_in.value = 131 #bits 0,1 are active low

    # should see pwm on/off
    while dut.uo_out.value[4] == 0:
        await ClockCycles(dut.clk, 1)
    cocotb.log.info("PWM posedge seen")
    while dut.uo_out.value[4] == 1:
        await ClockCycles(dut.clk, 1)
    cocotb.log.info("PWM negedge seen")

    # wait 5ms then sample 2A
    await Timer(5, unit="ms")
    assert int(dut.ad_iout.value) > 300 
    assert int(dut.ad_iout.value) < 500 
    cocotb.log.info("2Amp seen");

    # wait 10ms then sample 4A
    await Timer(10, unit="ms")
    assert int(dut.ad_iout.value) > 600 
    assert int(dut.ad_iout.value) < 1000 
    cocotb.log.info("4 Amp seen");

    # wait 10ms then sample 6A
    await Timer(10, unit="ms")
    assert int(dut.ad_iout.value) > 900 
    assert int(dut.ad_iout.value) < 1500 
    cocotb.log.info("6 Amp seen");

    # wait 10ms then sample 8A
    await Timer(10, unit="ms")
    assert int(dut.ad_iout.value) > 1200 
    assert int(dut.ad_iout.value) < 2000 
    cocotb.log.info("8 Amp seen");

    # wait 5ms (total wait 40ms) some time and then assert burn through
    await Timer(5, unit="ms")
    cocotb.log.info("gniter Burn Through")
    dut.ui_in.value = 195

    # wait and test remaining energy in cap
    await Timer(1, unit="ms")
    assert int(dut.ad_vcap.value) > 100 
    assert int(dut.ad_vcap.value) < 400 
    assert dut.uo_out.value[5] == 0 # dump is still zero
    
    # if we reach here it works
    await Timer(1, unit="ms")
    cocotb.log.info("Full lanch cycle simulation complate");


@cocotb.test()
async def compare_reference(dut):
    cocotb.pass_test()
