`timescale 1ns / 1ps
`define FIXED_POINT 1
module accelerator_tb;

	reg seen_first = 1'b0, seen_last = 1'b0;
   integer start_time, stop_time;

	// Inputs
	reg clk;
	reg ce;
	reg [71:0] weight1;
	reg global_rst;
	reg [7:0] activation;

	// Outputs
	wire [7:0] acc_op,conv_out;
	wire conv_valid,conv_end;
	wire end_op;
	wire valid_op;
	integer i;
    parameter clkp = 20;
    integer ip_file,r3,op_file;
	 
	// Instantiate the Unit Under Test (UUT)
	accelerator #(.MAP_SIZE('d6),.p('d2),.k('d3),.N('d8),.Q('d4),.ptype('d0),.AW('d8),.DW('d8),.s('d1),.p_sqr_inv(8'b00000100)) uut (
		.clk(clk), 
		.ce(ce), 
		.weight1(weight1), 
		.global_rst(global_rst), 
		.activation(activation), 
		.data_out(acc_op), 
		.valid_op(valid_op), 
		.end_op(end_op),
		.conv_out(conv_out),
		.conv_valid(conv_valid),
		.conv_end(conv_end)
	);

	initial begin
		// Initialize Inputs
		clk = 0;
		ce = 0;
		weight1 = 0;
		global_rst = 0;
		activation = 0;

		// Wait 100 ns for global reset to finish
		#100;
		
      clk = 0;
		ce = 0;
		weight1 = 0;
		activation = 0;
        global_rst =1;
        #60;
        global_rst =0;	
        //#10;	
		ce=1;
		ip_file = $fopen("activations.txt","r");
		op_file = $fopen("acc_out.txt","a");
		`ifdef FIXED_POINT
		weight1 = 72'b11111001_00010111_00001111_11010001_11110110_10001101_11111010_10010011_11110100;
		`else
        weight1 = 72'hF9_17_0F_D1_F6_8D_FA_93_F4;
		`endif
		
		// Initialize Inputs
		for(i=0;i<36;i=i+1) begin
		`ifdef FIXED_POINT
		r3 = $fscanf(ip_file,"%b\n",activation);
    	`else
		activation = i;
		`endif
		#clkp; 
		end
		//$display(">>> 36 inputs done, finishing");
		//$finish;
	end 
      always #(clkp/2) clk = ~clk;  
      
      always@(posedge clk) begin
		// Time to inference counters:
		  if(global_rst) begin
		    seen_first = 0;
			 seen_last = 0;
		  end
		
        if(valid_op & !end_op & !seen_first) begin 
				seen_first = 1;
				start_time = $time;
				$display(">>> Inference START at time %0t ns", start_time);
            $fdisplay(op_file,"%b",acc_op); 
        end
        //if(conv_end) begin
        //if(ce)
        //begin
        //$fdisplay(op_file,"%s%0d","end",0);
        //$finish;
        //end
      //end
		if (end_op && seen_first && !seen_last) begin
			seen_last   = 1;
			stop_time   = $time;
			$display(">>> Inference END   at time %0t ns", stop_time);
			$display(">>> Total latency = %0t ns", stop_time - start_time);
			$finish;
    end
    end    
endmodule