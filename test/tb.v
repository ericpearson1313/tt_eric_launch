// vim: ts=4:
`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    //#1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // sim test signals fed into DUT
  logic adc_vout, adc_vcap, adc_iout; // in lieu of ui_in[4:2]
  logic charge, pwm, dump, arm_led, cont_led, speaker;
  assign arm_led = uo_out[0];
  assign cont_led= uo_out[1];
  assign speaker = uo_out[2];
  assign charge  = uo_out[3];
  assign pwm	 = uo_out[4];
  assign dump	 = uo_out[5];

  // Replace tt_um_example with your module name:
  tt_um_eric_lcc user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  ({ui_in[7:5], adc_vcap, adc_vout, adc_iout, ui_in[1:0]} ),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

 // add the integer system model used on test stand fpga
 // scale down R,C and increate the charge rate to shorted sim
 // syssim monitors the dut outputs simulates the system and provides state

	logic [11:0] ad_iout, ad_vout, ad_icap, ad_vcap, ad_ecap;
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
        .charge ( uo_out[3] ),
        .pwm    ( uo_out[4] ),
        .dump   ( uo_out[5] ),
        // virtual simulaiton inputs
        .burn   ( ui_in[7] ), // sim control not used by hardware
        // ADC outputs
        .ad_iout    ( ad_iout ),  // eventual sys_sim[2] ), 
        .ad_vout    ( ad_vout ),  // eventual sys_sim[3] ),
        .ad_vcap    ( ad_vcap ),  // eventual sys_sim[4] ),
        // Monitoring outputs
        .ad_icap    ( ad_icap ),
        .ad_ecap    ( ad_ecap )
    );


   	/////////////////////
    // AD7352 Model     
    /////////////////////

	// sim pad register of CS
    logic cs_ireg;
    always @(posedge !clk)
        cs_ireg <= uo_out[6];

 	// synthesisiable ADC models to feed system data into LCC
    logic [3:0] m_ad_out;
    lcc_adcsim i_adcsim(
        .clk( !clk ),
        .reset( !rst_n ),
        .ad_in( { 12'd0, ad_vcap, ad_vout, ad_iout } ),
        .ad_out( m_ad_out[3:0] ),
        .ad_cs( cs_ireg )
    );

	// sim out pad output reg for data
    always_ff @(posedge !clk) begin
        adc_iout <= m_ad_out[0];
        adc_vout <= m_ad_out[1];
        adc_vcap <= m_ad_out[2];
    end


endmodule
