`timescale 1ns / 1ps
`define FIXED_POINT 1
module accelerator #(
    parameter MAP_SIZE = 9'h00a,  //size of the input image/activation map
    parameter k = 9'h003,  //size of the convolution window
    parameter p = 9'h002,  //size of the pooling window
    parameter s = 1,       //stride value during convolution
    parameter ptype = 1,  //0 => average pooling , 1 => max_pooling
    parameter act_type = 0,//0 => ReLu activation function, 1=> Hyperbolic tangent activation function
    parameter N = 8,     //Bit width of activations and weights (total datapath width)
    parameter Q = 4,     //Number of fractional bits in case of fixed point representation
    parameter AW = 8,    //Needed in case of tanh activation function to set the size or ROM
    parameter DW = 8,    //Datapath width = N 
	 parameter [N-1:0] p_sqr_inv = 8'b00000100
    //parameter p_sqr_inv = 16'b0000010000000000 // = 1/p**2 in the (N,Q) format being used currently								
    )(
    input clk,
    input global_rst,
    input ce,
    input [N-1:0] activation,
    input [(k*k)*N-1:0] weight1,
    output [N-1:0] data_out,
    output valid_op,
    output end_op,
    output [N-1:0] conv_out,
    output conv_valid,
    output conv_end
    );
    
    //wire [N-1:0] conv_op;
    //wire valid_conv,end_conv;
    wire valid_ip;
    wire [N-1:0] relu_op;
    wire [N-1:0] tanh_op;
    wire [N-1:0] pooler_ip;
    wire [N-1:0] pooler_op;
    reg [N-1:0] pooler_op_reg;
    
    /*convolver #(.MAP_SIZE(MAP_SIZE),.k(k),.s(s),.N(N),.Q(Q)) conv(//Convolution engine
            .clk(clk), 
            .ce(ce), 
            .weight1(weight1), 
            .global_rst(global_rst), 
            .activation(activation), 
            .conv_op(conv_op), 
            .end_conv(end_conv), 
            .valid_conv(valid_conv)
        );
    assign conv_valid = valid_conv;
    assign conv_end = end_conv;
    assign conv_out = conv_op;
    
    assign valid_ip = valid_conv && (!end_conv);*/
	 
	 wire [N-1:0] conv_out_0, conv_out_1;
	 wire valid_0, valid_1;
	 wire end_0, end_1;
	 
	 reg [N-1:0] linebuf [0:k-1];
	 integer y;
	 always @(posedge clk) if (ce) begin
		linebuf[0] <= activation;
		for (y=1; y<k-1; y=y+1)
			linebuf[y] <= linebuf[y-1];
	 end

	 wire [N*k-1:0] window0 = {linebuf[2], linebuf[1], linebuf[0]};
	 wire [N*k-1:0] window1 = {linebuf[1], linebuf[0], activation};

	 convolver #(
		.MAP_SIZE(MAP_SIZE),
		.k(k),
		.s(s),
		.N(N),
		.Q(Q)
		) conv0 (
		.clk       (clk),
		.ce        (ce),
		.global_rst(global_rst),
		.activation(window0),    // first pixel’s window
		.weight1   (weight1),
		.conv_op   (conv_out_0),
		.valid_conv(valid_0),
		.end_conv  (end_0)
		);

		convolver #(
		.MAP_SIZE(MAP_SIZE),
		.k(k),
		.s(s),
		.N(N),
		.Q(Q)
		) conv1 (
		.clk       (clk),
		.ce        (ce),
		.global_rst(global_rst),
		.activation(window1),    // second pixel’s window (shifted by 1 in X)
		.weight1   (weight1),
		.conv_op   (conv_out_1),
		.valid_conv(valid_1),
		.end_conv  (end_1)
		);
	 
	   reg toggle;              // which half-cycle we’re on
		always @(posedge clk or posedge global_rst) begin
			if (global_rst) begin
				toggle <= 0;
			end else if (valid_0 & valid_1) begin
				// only advance once both engines have valid data
				toggle <= ~toggle;
			end
		end

		// choose between engine0 and engine1 each cycle
		wire [N-1:0] conv_op  = toggle ? conv_out_1  : conv_out_0;
		wire         conv_vld = toggle ? valid_1     : valid_0;
		wire         con_end = toggle ? end_1       : end_0;

		// feed the conv results to the rest of the pipeline:
		assign conv_out   = conv_op;
		assign conv_valid = conv_vld;
		assign conv_end   = con_end;     
		
		assign valid_ip = conv_valid && (!conv_end);
    
    relu #(.N(N)) act(                             // ReLu Activation function
            .din_relu(conv_op),
            .dout_relu(relu_op)
        );
        
    tanh_lut #(.AW(AW),.DW(DW),.N(N),.Q(Q)) tanh(  //Hyperbolic Tangent Activation function
            .clk(clk),
            .rst(global_rst),
            .phase(conv_op),
            .tanh(tanh_op)
        );
    
    assign pooler_ip = act_type ? tanh_op : relu_op;
    
    pooler #(.N(N),.Q(Q),.m(MAP_SIZE-k+1),.p(p),.ptype(ptype),.p_sqr_inv(p_sqr_inv)) pool( //Pooling Unit
            .clk(clk),
            .ce(valid_ip),
            .master_rst(global_rst),
            .data_in(pooler_ip),
            .data_out(pooler_op),
            .valid_op(valid_op),
            .end_op(end_op)
        );

    assign data_out = pooler_op;
    
endmodule