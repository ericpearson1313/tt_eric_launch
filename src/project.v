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
	
  	// Suppress unused signals warning
  	wire _unused_ok = &{ena, ui_in[6:5], uio_in};

	// Latch on reset for test mode
	logic test_mode;
	always @(posedge clk)
		if( !rst_n ) 
			test_mode <= !ui_in[7]; 

	// Test mode muxing of ui_in and uo_out
	wire [7:0] dui_in, duo_out; // our dut device
	wire [7:0] tui_in, tuo_out; // our dut device
	assign  uo_out = ( test_mode ) ? tuo_out : duo_out;
	assign dui_in  = ( test_mode ) ? tui_in  :  ui_in ; 
	
	// ADC Scale parameters
	parameter ADC_VOLTS_PER_DN = 0.2005;
	parameter ADC_DN_PER_AMP = 205;
	// Physical parameters
	parameter CLOCK_FREQ_MHZ = 48;  // 48 or 24 Mhz
	parameter COIL_IND_UH = 390;
	
	assign duo_out[7] = 1'b0;
	forge_launcher #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ, COIL_IND_UH ) i_chip (
		// System
		.clk			( clk ),
		.reset			( !rst_n),
		// Front Panel
		.fire_button 	(!dui_in[0] ),
		.arm_led 		(duo_out[0] ),
		.cont_led	 	(duo_out[1] ),
		.speaker 		(duo_out[2] ),
		// High Voltage
		.lt3420_charge 	(duo_out[3] ),
		.lt3420_done   	( 1'b0  ),
		.pwm           	(duo_out[4] ),
		.dump			(duo_out[5] ),
		// ADC interface
		.ad_cs			(duo_out[6] ),
		.ad_s_iout		(dui_in[2] ),
		.ad_s_vout		(dui_in[3] ),
		.ad_s_vcap		(dui_in[4] ),
		.neg_iout		( 1'b0 ),
		.neg_vout		( 1'b0 ),
		.neg_vcap		( 1'b0 ),
		// Tie off Debug inputs
		.auto_mode		( 1'b1 ),
		.use_est		( 1'b1 ),
		.mute			(!dui_in[1] ),
		.key			( 5'b00000 )
    );

    logic [11:0] ad_iout, ad_vout, ad_icap, ad_vcap, ad_ecap;
	logic burn;
    lcc_syssim #(
        .ADC_VOLTS_PER_DN   ( 0.2005 ),
        .ADC_DN_PER_AMP     ( 205 ),
        .ADC_DN_PER_JOULE   ( 205 ),
        .CLOCK_FREQ_MHZ     ( 48 ),
        .COIL_UH            ( 390.0 ),
        .CAP_UF             ( 200.0 ), // normally 200.0, 
        .CH_RATE            ( 50.0 ), // normally 2.5 J/s
        .CH_INIT            ( 1900 ), // start energy, almost full, take 3ms to charge
        .R_DUMP             ( 300.0 ), // normally 3k3
        .R                  ( 10.0 ) // resistance ohms
    ) i_intsim (
        .clk    ( clk ),
        .reset  ( !rst_n ),
        // hardware power control signals
        .charge (duo_out[3] ),
        .pwm    (duo_out[4] ),
        .dump   (duo_out[5] ),
        // virtual simulaiton inputs
        .burn   ( burn ), // sim control not used by hardware
        // ADC outputs
        .ad_iout    ( ad_iout ),  // eventual sys_sim[2] ), 
        .ad_vout    ( ad_vout ),  // eventual sys_sim[3] ),
        .ad_vcap    ( ad_vcap ),  // eventual sys_sim[4] ),
        // Monitoring outputs
        .ad_icap    ( ad_icap ),
        .ad_ecap    ( ad_ecap )
    );

   // sim pad register of CS
    logic cs_ireg;
    always @(posedge !clk)
        cs_ireg <= ( !rst_n ) ? 0 : duo_out[6];

    // synthesisiable ADC models to feed system data into LCC
    logic [3:0] m_ad_out;
    lcc_adcsim i_adcsim(
        .clk( !clk ),
        .reset(  !rst_n ),
        .ad_in( { 12'd0, ad_vcap, ad_vout, ad_iout } ),
        .ad_out( m_ad_out[3:0] ),
        .ad_cs( cs_ireg )
    );

    // sim out pad output reg for data
	logic adc_iout, adc_vout, adc_vcap;
    always_ff @(posedge !clk) begin
      if( !rst_n ) begin
        adc_iout <= 0;
        adc_vout <= 0;
        adc_vcap <= 0;
      end else begin
        adc_iout <= m_ad_out[0];
        adc_vout <= m_ad_out[1];
        adc_vcap <= m_ad_out[2];
      end
    end

	//////////////////////////
    //      TESTBENCH
    //////////////////////////

	logic test_run;
	logic [21:0] test_cnt;
	logic [ 4:0] exit_flag;
	always @(posedge clk) begin
		test_cnt <= ( !rst_n ) ? 0 : ( test_run ) ? test_cnt + 1 : test_cnt;
		test_run <= ( !rst_n ) ? 1 : ( (|exit_flag) || test_cnt[21-:4] == 4'd12 ) ? 0 : test_run;
	end
	// in est mode the output is the test state, shoule
	assign tuo_out = test_cnt[21-:8];

	// Hook up trial test inputs
	assign tui_in[7:5] = 3'b000;
	assign tui_in[4:2] = {adc_vcap, adc_vout, adc_iout}; // test adc iputs
	assign tui_in[1] = 1'b1;
	// at 10 ms press the button, at 16ms release it
	assign tui_in[0] = ( test_cnt >= 10*48000 && test_cnt < 16*48000 ) ? 1'b0 : 1'b1;
    // at 56 ms assert burn
	assign burn = ( test_cnt >= 56*48000 ) ? 1'b1 : 1'b0;

	// Sample the output currents at 2, 4, 6, 8 amps
	assign exit_flag[0] = ( test_cnt == 20*48000 && ( ad_iout < 300 || ad_iout > 500 ) ) ? 1'b1 : 1'b0;
	assign exit_flag[1] = ( test_cnt == 30*48000 && ( ad_iout < 700 || ad_iout > 900 ) ) ? 1'b1 : 1'b0;
	assign exit_flag[2] = ( test_cnt == 40*48000 && ( ad_iout < 900 || ad_iout >1200 ) ) ? 1'b1 : 1'b0;
	assign exit_flag[3] = ( test_cnt == 50*48000 && ( ad_iout <1300 || ad_iout >1500 ) ) ? 1'b1 : 1'b0;

	// Measure final values of cap voltage at 57ms
	assign exit_flag[4] = ( test_cnt == 57*48000 && ( ad_vcap < 300 || ad_vcap > 400 ) ) ? 1'b1 : 1'b0;

	// The exit criteria is determiend by counter and a state comparison

endmodule 
