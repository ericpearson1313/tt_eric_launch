// vim: ts=4:
/*
 * Copyright (c) 2024 Tiny Tapeout LTD
 * SPDX-License-Identifier: Apache-2.0
 * Author: Eric Pearson
 */

`default_nettype none

module tt_um_eric_lcc (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  	// Unused outputs assigned to 0.
  	assign uio_out = 0;
  	assign uio_oe  = 0;
	assign uo_out[7] = 0;
	
  	// Suppress unused signals warning
  	wire _unused_ok = &{ena, ui_in[7:5], uio_in};


	// ADC Scale parameters
	parameter ADC_VOLTS_PER_DN = 0.2005;
	parameter ADC_DN_PER_AMP = 205;
	// Physical parameters
	parameter CLOCK_FREQ_MHZ = 48;  // 48 or 24 Mhz
	parameter COIL_IND_UH = 390;
	
	forge_launcher #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ, COIL_IND_UH ) i_chip (
		// System
		.clk			( clk ),
		.reset			( !rst_n),
		// Front Panel
		.fire_button 	( !ui_in[0] ),
		.arm_led 		( uo_out[0] ),
		.cont_led	 	( uo_out[1] ),
		.speaker 		( uo_out[2] ),
		// High Voltage
		.lt3420_charge 	( uo_out[3] ),
		.lt3420_done   	( 1'b0  ),
		.pwm           	( uo_out[4] ),
		.dump			( uo_out[5] ),
		// ADC interface
		.ad_cs			( uo_out[6] ),
		.ad_s_iout		( ui_in[2] ),
		.ad_s_vout		( ui_in[3] ),
		.ad_s_vcap		( ui_in[4] ),
		.neg_iout		( 1'b0 ),
		.neg_vout		( 1'b0 ),
		.neg_vcap		( 1'b0 ),
		// Tie off Debug inputs
		.auto_mode		( 1'b1 ),
		.use_est		( 1'b1 ),
		.mute			( !ui_in[1] ),
		.key			( 5'b00000 )
    );

endmodule 
