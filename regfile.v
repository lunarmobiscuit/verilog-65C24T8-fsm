/*
 * regfile.v 
 *
 * (C) Arlet Ottens, <arlet@c-scape.nl>
 * 24-bit address changes & threads (C) Luni Libes, <https://www.lunarmobiscuit.com/the-apple-4-or-the-mos-652402/>
 *
 */

module regfile(
    input clk,
    input reg_we,
    input [2:0] reg_thr,
    input [1:0] reg_src,
    input [1:0] reg_dst,
    input [1:0] reg_idx,
    output [7:0] src,
    output [7:0] idx,
    input [7:0] dst,
    input txs,
    input push,
    input pull,
    input variation );

`include "define.i"

/*
 * register file
 */
reg [7:0] X[7:0];       // X register(s)
reg [7:0] Y[7:0];       // Y register(s)
reg [7:0] A[7:0];       // A register(s)
reg [7:0] S[7:0];       // S register(s)

/* 
 * initial values for easy debugging, not required
 */
initial begin
    for (integer i = 0; i < NUM_THREADS; i++) begin
        X[i] = 1+i;
        Y[i] = 2+i*2;
        A[i] = 8'h40 + i;
        S[i] = 8'hff;
    end 
end

/*
 * 1st read port: source register
 *
 */
assign src = (reg_src == SEL_X) ? X[reg_thr] :
             (reg_src == SEL_Y) ? Y[reg_thr] :
             (reg_src == SEL_A) ? A[reg_thr] : 0;

/*
 * 2nd read port: index register
 */
assign idx = (reg_idx == IDX_X_) ? X[reg_thr] :
             (reg_idx == IDX__Y) ? Y[reg_thr] :
             (reg_idx == IDX_XY) ? A[reg_thr] : 0;

/*
 * write port: destination register. 
 */
always @(posedge clk)
    if( reg_we )
        case (reg_dst)
            SEL_X: X[reg_thr] <= dst;
            SEL_Y: Y[reg_thr] <= dst;
            SEL_A: A[reg_thr] <= dst;
            default:;
        endcase

/*
 * update stack pointer
 */
always @(posedge clk)
    if( txs )       S[reg_thr] <= src;
    else if( push ) S[reg_thr] <= S[reg_thr] - 1;
    else if( pull ) S[reg_thr] <= S[reg_thr] + 1;

/*
 * store CPU stats in A
 */
always @(posedge clk)
    if( variation ) A[reg_thr] = {AB24, R08, 4'h8};    // 24-bit address bus, 8-bit registers, 8 threads

endmodule
