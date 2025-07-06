`timescale 1ns / 1ps
`define FIXED_POINT 1

module convolver #(
  parameter MAP_SIZE = 9'h00a,        // activation map size
  parameter k = 9'h003,        // kernel size
  parameter s = 1,             // stride
  parameter N = 8,            // total bit width
  parameter Q = 4             // fractional bits
)(
  input          clk,
  input          ce,
  input          global_rst,
  input [N-1:0]  activation,
  input [(k*k)*N-1:0] weight1,
  output [N-1:0]  conv_op,
  output          valid_conv,
  output          end_conv
);

  //reg [31:0] count,count2,count3,row_count;
  //reg en1,en2,en3;

  // Unpacked weight array + pipeline regs
  wire [N-1:0] weight [0:k*k-1];
  wire [N-1:0] tmp    [0:k*k];

  // Flattened→array unpack
  genvar l;
  generate
    for (l = 0; l < k*k; l = l + 1) begin : UNP
      assign weight[l] = weight1[N*l +: N];
    end
  endgenerate

  // seed
  assign tmp[0] = 'd0;

  // MAC chain + optional shift
  genvar i;
  generate
    for (i = 0; i < k*k; i = i + 1) begin : MAC
      if ((i+1) % k == 0) begin
        if (i == k*k-1) begin
          // final tap → drive conv_op
          mac_manual #(.N(N)) mac_end (
            .clk(clk), .ce(ce), .sclr(global_rst),
            .a(activation), .b(weight[i]), .c(tmp[i]),
            .p(conv_op)
          );
        end else begin
          // end–of–row but not last → MAC then shift
          wire [N-1:0] tmp2;
          mac_manual #(.N(N)) mac_mid (
            .clk(clk), .ce(ce), .sclr(global_rst),
            .a(activation), .b(weight[i]), .c(tmp[i]),
            .p(tmp2)
          );
          variable_shift_reg #(.WIDTH(N), .SIZE(MAP_SIZE-k)) SR (
            .clk(clk), .ce(ce), .rst(global_rst),
            .d(tmp2), .out(tmp[i+1])
          );
        end
      end else begin
        // mid–row taps
        mac_manual #(.N(N), .Q(Q)) mac_core (
          .clk(clk), .ce(ce), .sclr(global_rst),
          .a(activation), .b(weight[i]), .c(tmp[i]),
          .p(tmp[i+1])
        );
      end
    end
  endgenerate

  localparam integer OUT_H     = (MAP_SIZE - k)/s + 1;
  localparam integer OUT_W     = (MAP_SIZE - k)/s + 1;
  localparam integer TOTAL_OUT = OUT_H * OUT_W;

  // how many clocks until the very first conv_op appears?
  localparam integer FILL_CYCLES = (k-1)*MAP_SIZE + (k-1);

  // counters
  reg [$clog2(FILL_CYCLES+1)-1:0] count;
  reg [$clog2(TOTAL_OUT)-1:0]     out_cnt;

  // ready & valid qualifiers
  wire pipeline_ready = (count >= FILL_CYCLES);
  wire valid_here    = pipeline_ready && (((count - FILL_CYCLES) % s) == 0);

  // count logic
  always @(posedge clk or posedge global_rst) begin
    if (global_rst) begin
      count   <= 0;
      out_cnt <= 0;
    end else if (ce) begin
      count <= count + 1;
      if (valid_here)
        out_cnt <= out_cnt + 1;
    end
  end

  // outputs
  assign valid_conv = valid_here;
  assign end_conv   = valid_here && (out_cnt == TOTAL_OUT-1);

endmodule
