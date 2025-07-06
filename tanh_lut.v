`timescale 1ns / 1ps
`define INTERPOLATE 1

module tanh_lut #(
    parameter AW = 8,         // address width → size of your ROM
    parameter DW = 8,         // data width out of ROM
    parameter N  = 8,         // full phase width (MSB=sign)
    parameter Q  = 4          // fractional bits for interpolation math
)(
    input                 clk,
    input                 rst,
    input  [N-1:0]        phase,
    output [DW-1:0]       tanh
);

    // --- ROM
    (* ram_style = "block" *) reg [DW-1:0] mem [(1<<AW)-1:0];
    initial begin
        $readmemb("tanh_data.mem", mem);
    end

    // --- address registers for pipelining
    reg [AW-1:0] addra_reg;
`ifdef INTERPOLATE
    reg [AW-1:0] addrb_reg;
`endif

    always @(posedge clk) begin
        if (rst) begin
            addra_reg <= 0;
    `ifdef INTERPOLATE
            addrb_reg <= 0;
    `endif
        end else begin
            addra_reg <= phase[AW-1:0];
    `ifdef INTERPOLATE
            addrb_reg <= phase[AW-1:0] + 1'b1;
    `endif
        end
    end

    // --- fetch from ROM
    wire [DW-1:0] tanh_a = mem[addra_reg];
`ifdef INTERPOLATE
    wire [DW-1:0] tanh_b = mem[addrb_reg];
`endif

    // --- extract Q-bit fractional part, form 1.0 in Q-format
    wire [Q-1:0] frac           = phase[Q-1:0];
    localparam [Q-1:0] ONE_Q   = {1'b1, {(Q-1){1'b0}}};
    wire [Q-1:0] one_minus_frac = ONE_Q - frac;

    // --- two multiplies for linear interpolation
    wire [N-1:0] p1, p2;
    wire         ov1, ov2;
    qmult #( .N(N), .Q(Q) ) mul1 (
        .clk(clk), .rst(rst),
        .a(tanh_a), .b(frac),
        .q_result(p1), .overflow(ov1)
    );
`ifdef INTERPOLATE
    qmult #( .N(N), .Q(Q) ) mul2 (
        .clk(clk), .rst(rst),
        .a(tanh_b), .b(one_minus_frac),
        .q_result(p2), .overflow(ov2)
    );
`else
    // if INTERPOLATE not defined, just pass tanh_a through
    assign p2 = { {(N){1'b0}} };
`endif

    // --- interpolated result
    wire [DW-1:0] tanh_temp = p1 + p2;

    // --- saturation constants at ±1.0 (in DW,Q)
    localparam [DW-1:0] SAT_POS = { 1'b0, {(DW-Q-1){1'b0}}, 1'b1, {(Q-1){1'b0}} };
    localparam [DW-1:0] SAT_NEG = { 1'b1, {(DW-Q-1){1'b1}}, 1'b0, {(Q-1){1'b0}} };

    // --- final output: saturate outside ±3 and sign-extend/negate as needed
    assign tanh = phase[N-1]
        ? ( phase[N-2] ? SAT_NEG   // phase < –3 → –1.0
                        : (~tanh_temp + 1'b1) ) // –3 < phase < 0 → –interp
        : ( phase[N-2] ? SAT_POS   // phase > +3 → +1.0
                        : tanh_temp ); // 0 ≤ phase ≤ +3 → +interp

endmodule
