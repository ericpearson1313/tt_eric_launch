// vim: ts=4:
// Inteteger model for synthesizable system simulation.
// To be part a an FGPA impremented chip tester.
// assume external cs input io reg, and serial data io output reg.
`timescale 1ns / 1ps

module lcc_adcsim (
		// system
		input logic clk,
		input logic reset,
		// ADC simulator connections, parallel in, serial out
		input logic [3:0][11:0] ad_in,
		output logic [3:0] ad_out,
		// driven by sampled falling edge of cs
		input logic ad_cs
	);

	logic [19:0] cs_del;
	always_ff @(posedge clk)
	  if( reset ) begin
		cs_del <= 0;
	  end else begin
		cs_del <= { cs_del[18:0], ad_cs };
	  end
	logic [19:0] cs_trig;
	assign cs_trig[18:0] =  cs_del[19:0] &~{ cs_del[18:0], ad_cs };
	logic [3:0][11:0] hold;
	always_ff @(posedge clk) begin
	  if( reset ) begin
		hold <= 0;
	  end else begin
		hold[0] <= ( cs_trig[0] ) ? ( ad_in[0] ^ 12'h800 ) : ( |cs_trig[12-:12] ) ? { hold[0][10:0], 1'b0 } : hold[0];
		hold[1] <= ( cs_trig[0] ) ? ( ad_in[1] ^ 12'h800 ) : ( |cs_trig[12-:12] ) ? { hold[1][10:0], 1'b0 } : hold[1];
		hold[2] <= ( cs_trig[0] ) ? ( ad_in[2] ^ 12'h800 ) : ( |cs_trig[12-:12] ) ? { hold[2][10:0], 1'b0 } : hold[2];
		hold[3] <= ( cs_trig[0] ) ? ( ad_in[3] ^ 12'h800 ) : ( |cs_trig[12-:12] ) ? { hold[3][10:0], 1'b0 } : hold[3];
	  end
	end
	assign ad_out[0] = hold[0][11];
	assign ad_out[1] = hold[1][11];
	assign ad_out[2] = hold[2][11];
	assign ad_out[3] = hold[3][11];
endmodule

// Primary synthesiable model of the coil current and capacitor energy
// intgration of coil current and cap energy are done in extended fixed point ADC units
// Capcitor voltage is derived by LUT from cap voltage
// Output voltage is derived from current and conductage constants (1/R),
// Capacitor current is intermediate for cap energy calc

module lcc_syssim #(
	parameter	ADC_VOLTS_PER_DN	= 0.2005,
	parameter   ADC_DN_PER_JOULE	= 205,
	parameter	ADC_DN_PER_AMP		= 205,
	parameter	CLOCK_FREQ_MHZ		= 48, // clock in mhz
	parameter	COIL_UH				= 390, // coil in uH
	parameter 	CAP_UF				= 200,
	parameter   CH_RATE				= 30.0, // Joule/sec
    parameter	CH_INIT             = 1500,
	parameter   R_DUMP 				= 300.0, // Dump resistor in ohms
	parameter   R      				= 2.0 // igniter resistance in ohms
	) (
		// system
		input logic clk,
		input logic reset,
		// hardware power control signals
		input logic dump,
		input logic charge,
		input logic pwm,
		// virtual simulaiton inputs
		input logic burn,
		// ADC outputs
		output logic [11:0] ad_iout,
		output logic [11:0] ad_vout,
		output logic [11:0] ad_vcap,
		// Monitoring outputs
		output logic [11:0] ad_icap,
		output logic [11:0] ad_ecap
	);
	
	logic signed [11:0] vout;
	logic signed [39:0] iout;
	logic signed [39:0] ecap;
	logic signed [11:0] icap;
	logic signed [11:0] vcap;

	// 268435456.0 = (1<<28)
	// 16777216.0 = (1<<24)
	// 65536.0 = (1<<16)

	localparam [15:0] ADC_CHARGE_PER_CYCLE = int'(( 268435456.0 * ADC_DN_PER_JOULE * CH_RATE ) / ( 1000000.0 * CLOCK_FREQ_MHZ ));
	localparam [17:0] ADC_DUMP_CONST = int'(( 268435456.0 * 512.0 ) / ( R_DUMP * CAP_UF * CLOCK_FREQ_MHZ ));
	localparam [15:0] ADC_COIL_CONST = int'(( 16777216.0 * ADC_VOLTS_PER_DN * ADC_DN_PER_AMP   ) / ( COIL_UH * CLOCK_FREQ_MHZ ));
	localparam [15:0] ADC_CAP_CONST  = int'(( 268435456.0 * 512.0 * ADC_VOLTS_PER_DN * ADC_DN_PER_JOULE ) / ( 1000000.0 * ADC_DN_PER_AMP * CLOCK_FREQ_MHZ));
	localparam [15:0] ADC_OUT_CONST  = int'(( 65536.0 *  R ) / ( ADC_DN_PER_AMP * ADC_VOLTS_PER_DN ));

//initial begin
//	$display("ADC_CHARGE_PER_CYCLE = %d", ADC_CHARGE_PER_CYCLE);
//	$display("ADC_DUMP_CONST = %d", ADC_DUMP_CONST);
//	$display("ADC_COIL_CONST = %d", ADC_COIL_CONST);
//	$display("ADC_CAP_CONST = %d", ADC_CAP_CONST);
//	$display("ADC_OUT_CONST = %d", ADC_OUT_CONST);
//end

	// Cap Energy to voltage rom
	logic [11:0] vcap_rom [63:0]; // unsigned 6 MSBs as input
	always_comb begin
vcap_rom[0] = 12'd139;
vcap_rom[1] = 12'd241;
vcap_rom[2] = 12'd312;
vcap_rom[3] = 12'd369;
vcap_rom[4] = 12'd418;
vcap_rom[5] = 12'd462;
vcap_rom[6] = 12'd502;
vcap_rom[7] = 12'd540;
vcap_rom[8] = 12'd575;
vcap_rom[9] = 12'd607;
vcap_rom[10] = 12'd639;
vcap_rom[11] = 12'd668;
vcap_rom[12] = 12'd697;
vcap_rom[13] = 12'd724;
vcap_rom[14] = 12'd750;
vcap_rom[15] = 12'd776;
vcap_rom[16] = 12'd800;
vcap_rom[17] = 12'd824;
vcap_rom[18] = 12'd848;
vcap_rom[19] = 12'd870;
vcap_rom[20] = 12'd892;
vcap_rom[21] = 12'd914;
vcap_rom[22] = 12'd935;
vcap_rom[23] = 12'd955;
vcap_rom[24] = 12'd975;
vcap_rom[25] = 12'd995;
vcap_rom[26] = 12'd1014;
vcap_rom[27] = 12'd1033;
vcap_rom[28] = 12'd1052;
vcap_rom[29] = 12'd1070;
vcap_rom[30] = 12'd1088;
vcap_rom[31] = 12'd1106;
vcap_rom[32] = 12'd1123;
vcap_rom[33] = 12'd1141;
vcap_rom[34] = 12'd1157;
vcap_rom[35] = 12'd1174;
vcap_rom[36] = 12'd1191;
vcap_rom[37] = 12'd1207;
vcap_rom[38] = 12'd1223;
vcap_rom[39] = 12'd1238;
vcap_rom[40] = 12'd1254;
vcap_rom[41] = 12'd1269;
vcap_rom[42] = 12'd1285;
vcap_rom[43] = 12'd1300;
vcap_rom[44] = 12'd1315;
vcap_rom[45] = 12'd1329;
vcap_rom[46] = 12'd1344;
vcap_rom[47] = 12'd1358;
vcap_rom[48] = 12'd1372;
vcap_rom[49] = 12'd1386;
vcap_rom[50] = 12'd1400;
vcap_rom[51] = 12'd1414;
vcap_rom[52] = 12'd1428;
vcap_rom[53] = 12'd1441;
vcap_rom[54] = 12'd1455;
vcap_rom[55] = 12'd1468;
vcap_rom[56] = 12'd1481;
vcap_rom[57] = 12'd1494;
vcap_rom[58] = 12'd1507;
vcap_rom[59] = 12'd1520;
vcap_rom[60] = 12'd1533;
vcap_rom[61] = 12'd1545;
vcap_rom[62] = 12'd1558;
vcap_rom[63] = 12'd1570;
	end


	always_ff @(posedge clk) vcap <= vcap_rom[ ecap[38-:6] ];

	// Cap current is just gated coil current
	always_ff @(posedge clk) icap <= ( pwm ) ? iout[39-:12] : 12'b0;

	// Model loop
	always_ff @(posedge clk) begin
		if( reset ) begin
			iout <= 40'd0;
			vout <= 12'd0;
			ecap <= ((CH_INIT)<<(40-12));
		end else if( dump ) begin
			iout <= 40'd0;
			vout <= 12'd0;
			//ecap <= ecap - ((ecap[39-:12] * ADC_DUMP_CONST)>>9);
			ecap <= ecap - ((ecap[39-:12] * 47722)>>9);
		end else if( charge ) begin
			iout <= 40'd0;
			vout <= 12'd0;
			//ecap <= ecap + ADC_CHARGE_PER_CYCLE;
			ecap <= ecap + 57322;
		end else if( burn ) begin
			iout <= 40'd0;
			vout <= 12'h7FF; // max V flyback
			ecap <= ecap;
		end else if( pwm ) begin
	//$display("ecap %x vcap %x, iout %x, VI %x, dE %x",ecap, vcap, iout, (24'd1 * vcap * iout[39-:12]), ((( 24'd1 * vcap * iout[39-:12] ) * ADC_CAP_CONST)>>9) );
			//iout <= iout + ((( vcap - vout ) * ADC_COIL_CONST)<<4 ) ;
			iout <= iout + ((( vcap - vout ) * 36837)<<4 ) ;
			//ecap <= ecap - ((( 24'd1 * vcap * iout[39-:12] ) * ADC_CAP_CONST)>>9);
			ecap <= ecap - ((( 24'd1 * vcap * iout[39-:12] ) * 574)>>9);
			//vout <= ( iout[39-:12] * ADC_OUT_CONST ) >> 16;
			vout <= ( iout[39-:12] * 15945) >> 16;
		end else /* !pwm */ begin
			//iout <= iout - (( vout * ADC_COIL_CONST )<<4);
			iout <= iout - (( vout * 36837)<<4);
			ecap <= ecap;
			//vout <= ( iout[39-:12] * ADC_OUT_CONST ) >> 16;
			vout <= ( iout[39-:12] * 15945) >> 16;
		end 
	end

	// connect up outputs
	assign ad_iout = iout[39-:12];
	assign ad_ecap = ecap[39-:12];
	assign ad_vout = vout;
	assign ad_icap = icap;
	assign ad_vcap = vcap;

endmodule
