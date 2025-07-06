`timescale 1ns / 1ps

module variable_shift_reg #(
  parameter WIDTH = 8,
  parameter SIZE  = 3
)(
  input               clk,
  input               ce,
  input               rst,
  input  [WIDTH-1:0]  d,
  output [WIDTH-1:0]  out
);

  // shift-register array
  reg [WIDTH-1:0] sr [0:SIZE-1];

  genvar i;
  generate
    for (i = 0; i < SIZE; i = i + 1) begin : SR_LOOP
      always @(posedge clk or posedge rst) begin
        if (rst)
          sr[i] <= {WIDTH{1'b0}};
        else if (ce)
          sr[i] <= (i == 0 ? d : sr[i-1]);
      end
    end
  endgenerate

  assign out = sr[SIZE-1];

endmodule
