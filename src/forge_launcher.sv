// vim: ts=4:
`timescale 1ns / 1ps
// ForgeFPGA model rocket launcher
// Digital PWM, current controlled buck converter. capacitive discharge
// igniter pulse generator 
module forge_launcher
(
	// System
	input logic clk,
	input logic reset,

	// Front Panel I/O
	input  logic fire_button,
	output logic arm_led,
	output logic cont_led,
	output logic speaker,

	// High Voltage 
	output logic lt3420_charge,
	input  logic lt3420_done,
	output logic pwm,	
	output logic dump,
	
	// External A/D Converters (2.5v)
	output logic  ad_cs,
	input  logic  ad_s_vcap, 
	input  logic  ad_s_vout,
	input  logic  ad_s_iout,
	input  logic  neg_vcap,
	input  logic  neg_vout,
	input  logic  neg_iout,
	
	///////////////////
	// Emulation I/o //
	///////////////////
	
	// Debug Controls
	input logic auto_mode,  // Run launch sequence
	input logic use_est,	// trust current estimations
	input logic mute,	// Only beep on 1st cont measurement
	
	// Backdoor keypad controls
	input	logic [4:0] key  // keypad 
);

	// ADC Scale parameters
	parameter ADC_VOLTS_PER_DN = 0.2005;
	parameter ADC_DN_PER_AMP = 205;
	// Physical parameters
	parameter CLOCK_FREQ_MHZ = 48;  // 48 or 24 Mhz
	parameter COIL_IND_UH = 390;

	// Free running counter
	logic [25:0] count = 0;
	initial count = 0;
	always_ff @(posedge clk) 
	count <= ( reset ) ? 0 : count + 1;

	// monitor outputs for Display
	logic [11:0] 	ad_iout; 
	logic [11:0] 	ad_vcap; 
	logic [11:0] 	ad_vbat; // future 
	logic [11:0] 	ad_vout;
	logic 			ad_strobe;
	logic [11:0] 	iest;

	
	// Display and Logging control outputs




//////////////////////////////////////////////
// fire button 10ms debounce 
// signal to get 1.3 sec of pwm current control
// signal One shot capture mode on 1st rising pwm edge 1.3 sec
// signal to set discharge at 1.3sec
// signal to stop tiny scroll window at 4.3 sec
//////////////////////////////////////////////

logic fire_button_debounce;
logic long_fire;
forge_debounce #( CLOCK_FREQ_MHZ ) _firedb ( .clk( clk ), .reset( reset ), .in( fire_button ), .out( fire_button_debounce ), .long( long_fire ));

parameter PWM_START     = 1; // Enable PWM current control 
parameter PWM_END		= (CLOCK_FREQ_MHZ*4/3) * 1000 * 1000; // Total time 1.333 sec

logic [27:0] fire_count = 0; 
logic fire_flag = 0;
logic fire_done = 0;
initial fire_count = 0;
initial fire_flag = 0;
initial fire_done = 0;
always_ff @(posedge clk) begin
	if( reset ) begin
	fire_count <= 0;
	fire_flag <= 0;
	fire_done <= 0;
	end else begin
	fire_count <= ( fire_count == 0 && !fire_button_debounce ) ? 0 : fire_count + 1; // committed when past debounce
	fire_flag <= ( fire_count >= PWM_START && fire_count < PWM_END && !fire_done ) ? 1'b1 : 1'b0;
	fire_done <= ( fire_count == PWM_END ) ? 1'b1 : fire_done;
	end
end

assign dump = fire_done; // always dump after firing

////////////////////////////////
// Power On auto charge and continuity until fire button
////////////////////////////////
logic charge_reg;
logic continuity;
logic [1:0] one_time;
logic cap_charged;
initial charge_reg = 0;
initial continuity = 0;
initial one_time = 0;
always_ff @( posedge clk ) begin
  if( reset ) begin
		one_time <= 0;
		charge_reg <= 0;
		continuity <= 0;
  end else begin
	one_time <= ( one_time == 3 ) ? 3 : ( one_time == 0 && !count[16] ) ? 0 : one_time + 1;
	if( one_time == 2 ) begin
		charge_reg <= 1;//auto_mode;
		continuity <= 0;
	end else if( cap_charged && charge_reg ) begin // switch to continuity
		charge_reg <= 0;
		continuity <= 1;
	end else if( continuity && fire_flag ) begin // and end the launch sequence
		charge_reg <= 0;
		continuity <= 0;
	end else begin
		charge_reg <= charge_reg;
		continuity <= continuity;	
	end
  end
end

assign lt3420_charge = charge_reg;

//////////////////////////////

// Speaker is differential out gives 6Vp-p
logic [7:0] tone_cnt;
logic cont_tone, first_tone;
logic spk_en, spk_toggle;
always_ff @(posedge clk) begin
  if( reset ) begin
		spk_toggle <= 0;
		spk_en <= 0;
		tone_cnt <= 0;
  end else begin
	if( tone_cnt == 0 ) begin
		spk_toggle <= !spk_toggle;
		{spk_en, tone_cnt} <= 	( fire_button_debounce               ) ? { 1'b1, 8'h2C } :
								( (cont_tone && !mute) || first_tone ) ? { 1'b1, 8'h16 } : 0; // sw0 mutes tone
	end else begin
		tone_cnt <= (count[7:0]==0) ? tone_cnt - 1 : tone_cnt;
		spk_en <= spk_en;
		spk_toggle <= spk_toggle;
	end
  end
end

assign speaker = spk_toggle & spk_en ; 

////////////////////////////////////////////
// Burn-through detect 
// If burn through occurs we will see high dvdt on the output.
// In this case we'll stop operation to minimize voltage spikes.
logic burn = 0; 
//logic current_seen = 0;
logic [11:0] ad_vout_del = 0;
initial burn = 0;
//initial current_seen = 0;
initial ad_vout_del = 0;

logic signed [12:0] dv; // delta voltage
assign dv[12:0] = { ad_vout[11], ad_vout[11:0] } - { ad_vout_del[11], ad_vout_del[11:0] };
/* verilator lint_off REALCVT */
logic signed [12:0] max_dvdt = 100 * (16 * 10000) / (ADC_VOLTS_PER_DN * 10000 * CLOCK_FREQ_MHZ); // (100 v/usec limit * 16 cyc/sample)/(.2005 v/dn * 48 Mhz)
/* verilator lint_on REALCVT */
always_ff @(posedge clk) begin
	burn <= (!fire_flag&&!fire_done) ? 0 : ( fire_flag && ( dv > max_dvdt )) ? 1'b1 : burn;
	ad_vout_del <= ad_vout; // ad_vout only changes on sample x16, but is fine for our detection use
end

////////////////////////////////////////////
// PWM Current limited pulse generator
////////////////////////////////////////////

logic [11:0] 	thresh_hi, thresh_lo;

localparam COUNT_10MS = 28'h00_80000; // 10ms / CLOCK_FREQ_MHZ
localparam COUNT_20MS = 28'h01_00000; // 20ms / CLOCK_FREQ_MHZ
localparam COUNT_30MS = 28'h01_80000; // 30ms / CLOCK_FREQ_MHZ
always_ff @(posedge clk) thresh_hi <= 	(!fire_flag                           ) ? ( ADC_DN_PER_AMP * 2 + 20 ) :
									(fire_flag && fire_count < COUNT_10MS ) ? ( ADC_DN_PER_AMP * 2 + 20 ) : // until 10ms setpoint 2Amp 
									(fire_flag && fire_count < COUNT_20MS ) ? ( ADC_DN_PER_AMP * 4 + 20 ) : // until 20ms setpoint 4amp
									(fire_flag && fire_count < COUNT_30MS ) ? ( ADC_DN_PER_AMP * 6 + 20 ) : // until 20ms setpoint 4amp
									                         /* remainder */  ( ADC_DN_PER_AMP * 8 + 20 ) ; // remainder  setpoint 6Amp
always_ff @(posedge clk) thresh_lo <= 	(!fire_flag                           ) ? ( ADC_DN_PER_AMP * 2 - 20 ) : 
									(fire_flag && fire_count < COUNT_10MS ) ? ( ADC_DN_PER_AMP * 2 - 20 ) : 
									(fire_flag && fire_count < COUNT_20MS ) ? ( ADC_DN_PER_AMP * 4 - 20 ) : 
									(fire_flag && fire_count < COUNT_30MS ) ? ( ADC_DN_PER_AMP * 6 - 20 ) : 
									                         /* remainder */  ( ADC_DN_PER_AMP * 8 - 20 ) ;

logic 			pwm_pulse = 0;
logic [15:0] 	pulse_time = 0;
logic [9:0] 		pulse_count = 0;
logic			ramp_flag = 0;
initial			pwm_pulse = 0;
initial			pulse_time = 0;
initial			pulse_count = 0;
initial			ramp_flag = 0;
always_ff @(posedge clk) begin
	if( reset ) begin
		pwm_pulse <= 0;
		pulse_time <= 0;
		pulse_count <= 0;
		ramp_flag <= 0;
	end else begin
		if( pwm_pulse ) begin // turn off pulse if time or current level exceeded
			if( pulse_time < (CLOCK_FREQ_MHZ*2/3) ) begin // min pulse width 750usec
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count	
				ramp_flag <= ramp_flag;
			end else if(( burn )																	// burnthrough
			         || ( pulse_time >= (CLOCK_FREQ_MHZ  * 16))    					// 16 usec max on time
						||	( !ad_iout[11] && ((ad_iout) > (thresh_hi)))		// measure iout > 2.2 amps (panic only?)
						||	( !iest[11]  && ((iest ) > (thresh_hi)) && use_est )	// est iout > 2.2 amps, disable est use, fb only
						) begin //  >2 amp * 205 DN/A measured + 10%
				pwm_pulse <= 0;
				pulse_time <= 0;
				pulse_count <= pulse_count - 1;
				ramp_flag <= ramp_flag;
			end else begin
				ramp_flag <= ramp_flag;
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count
			end
		end else if( !burn && !pwm_pulse && ( fire_flag || pulse_count > 0 ) ) begin // wait for ad_iout to fall
			if( pulse_time < (CLOCK_FREQ_MHZ * 4) ) begin // min pulse off time is 4 Usec
				ramp_flag <= ramp_flag;
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count					
			end else if ( ( ad_iout[11] || ((ad_iout) < (thresh_lo))) ) begin //  <2 amp * 205 DN/A measured - 10%
				ramp_flag <= ramp_flag;
				pwm_pulse <= 1;
				pulse_time <= 1;
				pulse_count <= pulse_count;
			end else begin // current above min tolerance
				ramp_flag <= 0;  // cleared now meeting min tolerage
				pwm_pulse <= 0;
				pulse_time <= pulse_time + 1; 
				pulse_count <= pulse_count;
			end			
		end else begin // await trigger
			ramp_flag <= 1;
			pwm_pulse <= 0;
			pulse_time <= 0;		
			pulse_count <= 0;
		end
	end
end


// Free runnig ADC converters
// 12 bit, 4 channel simultaneous, 3 Mhz
forge_adc_module_4ch  _adc (
	// Input clock
	.clk( clk ),
	.reset( reset ),
	// External A/D interface
	.ad_cs		( ad_cs ),
	.ad_sdata 	( { ad_s_vout, 1'b0, ad_s_vcap, ad_s_iout } ),
	.ad_neg		( { neg_vout, 1'b1, neg_vcap, neg_iout } ),
	// ADC held data and strobe
	.ad_out0    ( ad_iout ),
	.ad_out1    ( ad_vcap ),
	.ad_out2    ( ad_vbat ),
	.ad_out3    ( ad_vout ),
	.ad_strobe	( ad_strobe )
);

// Modelling Coil Current
// estimate is before sample and 16x finer timing
forge_model_coil #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ, COIL_IND_UH ) _model (
	// Input clock
	.clk( clk ),
	.reset( reset ),
	// PWM input
	.pwm( pwm ),
	// Votlage Inputs
	.vcap( ad_vcap ), // ADC voltage across cap
	.vout( ad_vout ), // ADC voltage across output
	// Current input to rebase estimate
	.iout( ad_iout ), // Output current
	// Coil Current estimate
	.iest_coil( iest )
);

logic res_pwm;
forge_igniter_continuity #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ ) _res_cont (
	.clk( clk ),
	.reset( reset ),
	// Votlage and Current Inputs
	.valid_in( ad_strobe ),
	.v_in( ad_vout ), // ADC Vout
	.i_in( ad_iout ), // ADC Iout
	// PWM output and enable input
	.pwm( res_pwm ),
	.enable( continuity ),
	// Tone and LED output
	.tone( cont_tone ),
	.first_tone( first_tone ),
	.led( cont_led )
);

assign pwm = pwm_pulse | res_pwm;

// Arm is based on vcap with 300v on thresh and 50v off thresh
// clip inputs to +ve
logic [10:0] vcap;
assign vcap = ( ad_vcap[11] || ad_vcap[10:4] == 0 ) ? 11'b0 : ( ad_vcap[10:0] );


always_ff @( posedge clk ) begin
  if( reset ) begin
	cap_charged <= 0;
  end else begin
	cap_charged <= ( ad_strobe && vcap > (( 310 * 10000 ) / 2005 ) ) ? 1'b1 :
	               ( ad_strobe && vcap < (( 50  * 10000 ) / 2005 ) ) ? 1'b0 : cap_charged;
  end
end

always_ff @(posedge clk)
	arm_led <= cap_charged | ( charge_reg && (count[24:21]==0) );

endmodule

			
module forge_debounce(
	input clk,
	input reset,
	input in,
	output out,	// fixed pulse 15ms after 5ms pressure
	output long // after fire held for > 2/3 sec, until release
	);

	parameter CLOCK_FREQ_MHZ = 48;	
	localparam CYC_PER_MS = CLOCK_FREQ_MHZ * 1000; // 1 Ms count time
	localparam CYC_LONG   = ( CLOCK_FREQ_MHZ * 2 / 3 ) * 'h100000;
	
	logic [25:0] count1 = 0; // total 1.3 sec
	logic [22:0] count0 = 0;
	logic [2:0] meta;
	logic       inm;

	
	always_ff @(posedge clk) { inm, meta } <= { meta, in };
	
	// State Machine	
	localparam S_IDLE 		= 0;
	localparam S_WAIT_PRESS	= 1;
	localparam S_WAIT_PULSE	= 2;
	localparam S_WAIT_LONG	= 3;
	localparam S_LONG		= 4;
	localparam S_WAIT_OFF	= 5;
	localparam S_WAIT_LOFF	= 6;
	
	logic [2:0] state = S_IDLE;
	always_ff @(posedge clk) begin
		if( reset ) begin
			state <= S_IDLE;
		end else begin
			case( state )
				S_IDLE 		 :	state <= ( inm ) ? S_WAIT_PRESS : S_IDLE;
				S_WAIT_PRESS :	state <= (!inm ) ? S_IDLE       : (count1 == ( 5  * CYC_PER_MS )) ? S_WAIT_PULSE : S_WAIT_PRESS;	// 5 msec debounce on
				S_WAIT_PULSE :	state <=                          (count1 == ( 25 * CYC_PER_MS )) ? S_WAIT_LONG  : S_WAIT_PULSE; 	// 25 msec pusle
				S_WAIT_LONG	 :	state <= (!inm ) ? S_WAIT_OFF   : (count1 >=          CYC_LONG  ) ? S_LONG       : S_WAIT_LONG;			// 0.66 sec long
				S_LONG		 :	state <= (!inm ) ? S_WAIT_LOFF  :  S_LONG;
				S_WAIT_OFF	 :	state <= ( inm ) ? S_WAIT_LONG  : (count0 == ( 100 * CYC_PER_MS)) ? S_IDLE       : S_WAIT_OFF;		// 100 mses debounce off
				S_WAIT_LOFF	 :	state <= ( inm ) ? S_LONG       : (count0 == ( 100 * CYC_PER_MS)) ? S_IDLE       : S_WAIT_LOFF;
				default: state <= S_IDLE;
			endcase
		end
	end
	
	assign out = (state == S_WAIT_PULSE) ? 1'b1 : 1'b0;
	assign long = (state == S_LONG || state == S_WAIT_LOFF) ? 1'b1 : 1'b0;
	
	// Counters
	always_ff @(posedge clk) begin
		if( reset ) begin
			count0 <= 0;
			count1 <= 0;
		end else begin
			count0 <= ( state == S_WAIT_OFF  || 
			            state == S_WAIT_LOFF ) ? (count0 + 1) : 0; // count when low waiting
			count1 <= ( state == S_IDLE      ) ? 0            : (count1 + 1); 
		end
	end

endmodule
	
	
module forge_adc_module_4ch 
(
	// Input clock,
	input logic clk,
	input logic reset,
	
	// External A/D Converters (2.5v)
	output logic        ad_cs,
	input  logic  [3:0] ad_sdata,
	input  logic  [3:0] ad_neg,
	
	// ADC monitor outputs
	output logic [11:0] ad_out0,
	output logic [11:0] ad_out1,
	output logic [11:0] ad_out2,
	output logic [11:0] ad_out3,
	output logic ad_strobe
);

// ADC sample pulse 
// RUn ADCs in-continuous mode.
// The fall of the CS signal is actually the moment of sampling, and MSB becomes valid
parameter HOLD_SEL = 15;  // select output hold delay bit 1 cyclce early but account for input regs
parameter ADCS_SEL = 15;  // early CS output cycle 


reg [3:0] sample_div = 0;
initial sample_div = 0;
always_ff @(posedge clk) sample_div <= ( reset ) ? 0 : sample_div + 1;

// ad_cs reg is to be I/O_reg
// ad_cs is active during sample_div == 0;
always_ff @(posedge clk) 
	ad_cs <= ( sample_div == ADCS_SEL ) ? 1'b1 : 1'b0;

// DATA Input I/O registers
logic [3:0] ad_ireg;
always_ff @(posedge clk)
	ad_ireg <= ad_sdata;

// Data input shift regisers MSB first
reg [3:0][11:0] ad_sreg;
always_ff @(posedge clk) begin
  if( reset ) begin
	ad_sreg <= 0;
  end else begin
		ad_sreg[0] <= { ad_sreg[0][10:0], ad_ireg[0] };
		ad_sreg[1] <= { ad_sreg[1][10:0], ad_ireg[1] };
		ad_sreg[2] <= { ad_sreg[2][10:0], ad_ireg[2] };
		ad_sreg[3] <= { ad_sreg[3][10:0], ad_ireg[3] };
  end
end

// Data hold registers
logic ad_hold_en;
always_ff @(posedge clk) 
	ad_hold_en <= ( sample_div == HOLD_SEL ) ? 1'b1 : 1'b0;
logic [3:0][11:0] ad_hold;
always_ff @(posedge clk) 
  if( reset ) begin
	ad_hold <= 0;
  end else begin
	for( int ii =  0; ii < 4; ii++ ) 
		ad_hold[ii] <= ( ad_hold_en ) ? ad_sreg[ii] : ad_hold[ii];
  end
// ad_strobe reg
always_ff @(posedge clk) ad_strobe <= ad_hold_en;

// Output optional negation
// data outputs with negation
assign ad_out0 = ad_hold[0] ^ ((ad_neg[0])?12'h7FF:12'h800);
assign ad_out1 = ad_hold[1] ^ ((ad_neg[1])?12'h7FF:12'h800);
assign ad_out2 = ad_hold[2] ^ ((ad_neg[2])?12'h7FF:12'h800);
assign ad_out3 = ad_hold[3] ^ ((ad_neg[3])?12'h7FF:12'h800);

endmodule



// This is a digital model of the current rise in the output inductor.
// This model runs at 48 Mhz (vs 3 Mhz sample rate) and give
// 16x timing precision and lower latency.
// Inputs are the PWM signal and slowely varying capacitor and output voltages. 
// The measured iout is also provided to intialize the model on PWM rising edge
// The model is ideal and optimisitic and will over-perform actual inductor current.
module forge_model_coil
(
	// Input clock, reset
	input logic clk,
	input reset,
	// ADC voltage inputs (sample and held )
	input logic [11:0] vcap, // ADC native signed format. +-401V gives -+2000DN
	input logic [11:0] vout, // -.2005V/DN, about 5 digital number steps per volt
	// Measured current
	input logic [11:0] iout, // used to re-initialize the model
	// PWM signal 
	input logic pwm,
	// Esimated Coil current 
	output [11:0] iest_coil // +-10A = -+2050 + 2048, so 205DN/A 
);

// ADC Scale parameters
parameter ADC_VOLTS_PER_DN = 0.2005;
parameter ADC_DN_PER_AMP = 205;
// Physical parameters
parameter CLOCK_FREQ_MHZ = 48;
parameter COIL_IND_UH = 390;

// Current Model assignments and accumulator
// Multiply by 1/Lf


/////////////////////////
// Coil Current Model
/////////////////////////

// Pre-process adc cap and output voltages (format, clip to zero with deadzone
logic [11:0] vcap_corr;
logic [11:0] vout_corr;
assign vcap_corr[11:0] = ( vcap[11:0] ); // signed 
assign vout_corr[11:0] = ( vout[11:0] ); // signed

// Calc deltaV across the coil when PWM On

logic [12:0] deltav;
always_ff @(posedge clk) deltav[12:0] <= { vcap_corr[11], vcap_corr[11:0] } - { vout_corr[11], vout_corr[11:0] };

// Use table lookup on &msbs of deltaV to calc deltai
logic [15:0] deltai_rom[63:0];// rom deltaI units in (4.12)
always_comb begin
	for( int ii = 0; ii < 64; ii++ )
/* verilator lint_off REALCVT */
		deltai_rom[ii] = ( (ii * 32 + 16) * 4096 * ADC_VOLTS_PER_DN * ADC_DN_PER_AMP ) / ( CLOCK_FREQ_MHZ * COIL_IND_UH );
/* verilator lint_on REALCVT */
end

logic [15:0] deltai;
always_ff @(posedge clk) deltai <= deltai_rom[(deltav[12])?0:deltav[10-:6]]; // 6 msb bits 

// Iest current is signed 12.12 in ADC current DN scale
// coil saturation at 5A ( i_acc[22] = 1 }
logic [23:0] iest_next, i_acc;
assign iest_next[23:0] = i_acc[23:0] + (i_acc[22] ? { 7'h00, deltai, 1'b0 } : { 8'h00, deltai });
always_ff @(posedge clk) begin
	if( !pwm ) begin // load rea value when pwm is low.
		i_acc[23:0] <= { ( iout[11] ) ? 12'h0 : ( iout[11:0] ), 12'h000 };
	end else begin // Accumulate during PWM for rise
		i_acc[23:0] <= iest_next; // 12 fractional bits
	end
end

// Ouput estimate is in adc units 
assign iest_coil[11:0] = i_acc[23-:12];

endmodule // model_coil
	
// Continuity Module
// Save gates over full resistance calculation, loose the 'short' detect capability.
// Enable input assertion, creates a PWM pulse (2us), and 64K hold-off on retrigger
// records max output current and voltage
// if Imax < 0.5amps --> Open, else
// else if Vmax > 30 volts resistance is high else good 
// Beep codes and continuity led are generated as outputs
module forge_igniter_continuity
(
	// System
	input logic clk,
	input reset,
	
	// ADC Inputs (output I,V)
	input logic valid_in,
	input logic [11:0] v_in, 
	input logic [11:0] i_in,	
	
	// PWM Output
	output logic pwm,

	// input Enable
	input logic enable,
	
	// Outputs
	output logic tone,
	output logic first_tone,
	output logic led
);
	
	// ADC Scale parameters
	parameter ADC_VOLTS_PER_DN = 0.2005;
	parameter ADC_DN_PER_AMP = 205;
// Physical parameters
	parameter CLOCK_FREQ_MHZ = 48;
	
	
	// Triggering with 0.6 Sec holdoff
	logic [24:0] holdoff = 0;
	always_ff @(posedge clk) begin
		if( !enable ) begin
			holdoff <= 0;
		end else if( enable && ( holdoff == 0 ) ) begin // start
			holdoff <= 1;
		end else if( holdoff != 0 ) begin // holdoff delay until wrap
			holdoff <= holdoff + 1;
		end else begin
			holdoff <= 0;
		end
	end
	
	// PWM output, 2usec
	assign pwm = ( ( holdoff != 0 ) && ( holdoff < ( CLOCK_FREQ_MHZ * 2 ))) ? 1'b1 : 1'b0; // 2 uSec continuity pulse
	
	// foramt and Clip inputs
	logic [10:0] current;
	logic [10:0] voltage;
	assign current = ( i_in[11] ) ? 11'h000 : ( i_in[10:0] );
	assign voltage = ( v_in[11] ) ? 11'h000 : ( v_in[10:0] );	
	
	localparam START_TIME = 256;
	localparam END_TIME = 4096;
	
	// Max IV accumulate
	logic [10:0] imax = 0, vmax = 0;
	always_ff @(posedge clk) begin
		if( holdoff == 0 ) begin // Idle, just hold values, zero acc
			imax <= 0;
			vmax <= 0;
		end else if( holdoff > START_TIME && holdoff < END_TIME && valid_in ) begin 
		   // accumulate valid samples
		    imax <= ( current > imax ) ? current : imax;
		    vmax <= ( voltage > vmax ) ? voltage : vmax;
		end else begin
			imax <= imax;
			vmax <= vmax;
		end
	end
	
	// Set LED if between 1 and 16 ohms
	always_ff @(posedge clk) begin
		led <= (enable == 0 ) ? 1'b0 : ( holdoff == END_TIME + 1 ) ? (( imax > 64 ) ? 1'b1 : 1'b0 ) : led;
	end
	
	// Tones 
	// Open, imax 1 < 64(300ma) - 3 beep
	// vmax > 128 (25v) high resistance - 2 beeps
	// else 1 beeps 
	
	logic [3:0] beep_time;
	assign beep_time = ( CLOCK_FREQ_MHZ == 24 ) ? holdoff[23-:4] : holdoff[24-:4];
	assign tone = 	( beep_time == 1 ) ? 1'b1 : // always a single beep
						( beep_time == 3 && ( imax < 12'h040 || vmax > 12'h080 ) ) ? 1'b1 : // two beeps if open or high
						( beep_time == 5 && ( imax < 12'h040 )) ? 1'b1 : 1'b0; // three beeps if open

	logic first = 1;	
	initial first = 1;
	always_ff @(posedge clk) begin
		first <= ( !enable ) ? 1 : ( beep_time == 8 ) ? 1'b0 : first;
	end
			
	assign first_tone = first & tone;
	
endmodule // forge_igniter_continuity
