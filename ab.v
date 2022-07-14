/*
 * Address Bus (and PC) generator
 *
 * Copyright (C) Arlet Ottens, 2022, <arlet@c-scape.nl>
 * 24-bit address changes (C) Luni Libes, <https://www.lunarmobiscuit.com/the-apple-4-or-the-mos-652402/>
 *
 */

module ab(
    input clk,
    input RST,
    input [9:0] ab_op,              // ab_op = bus_op[9:0]
    input [2:0] T,
    input [7:0] S,
    input [7:0] DI,
    input [7:0] DR,
    input [7:0] D3,
    input [7:0] XY,
    input ABWDTH,                   // address bus width = AB16 or AB24
    output [23:0] AB,
    input [23:0] PCT );

reg [7:0] AB3;
reg [7:0] ABH;
reg [7:0] ABL;
assign AB = { AB3, ABH, ABL };

/* 
 * ab_hold stores a copy of current address to be used
 * later.
 */
reg [23:0] ab_hold;

always @(posedge clk)
    if( ab_op[7] )                  // h 1'b
        ab_hold = AB;

/*
 * reset
 */
always @(posedge clk)
    if( RST ) begin
        AB3 = 8'hff;
    end

/*
 * determine base address
 */
reg [23:0] base;

always @* begin
    case( ab_op[4:3] )              // BS 2'b
       2'b00: base = {8'h00, 5'h00, T, S};
       2'b01: base = PCT;
       2'b10: if (ABWDTH == 1'b1) base = {DI, DR, D3};
              else base = {8'h00, DI, DR};
       2'b11: base = ab_hold;
    endcase
//$display("BASE:%0h ABW:%b DI:%0h DR:%0h D3:%0h OP:%b", base, ABWDTH, DI, DR, D3, ab_op[4:3]);
end

/*
 * add offset to the base address. We split the address into
 * two separate bytes, because sometimes the address should
 * wrap within the page, so we can't always let the carry 
 * go through.
 */

wire abl_ci = ab_op[0];     // carry input from operation
reg abl_co;                 // carry output from low byte (7:0)
reg abh_co;                 // carry output from high byte (15:8)

always @* begin
    case( ab_op[2:1] )              // +X 2'b
        2'b00: {abl_co, ABL} = base[7:0] + 00 + abl_ci;
        2'b01: {abl_co, ABL} = base[7:0] + XY + abl_ci;
        2'b10: {abl_co, ABL} = base[7:0] + DI + abl_ci;
        2'b11: {abl_co, ABL} = XY        + DI + abl_ci;
    endcase
//if (ab_op[2:1] == 2'b00) $display("+00 AB:%0h base:%0h X:%0h C:%b ABW:%b", AB, base, XY, abl_ci, ABWDTH);
//if (ab_op[2:1] == 2'b01) $display("+XY AB:%0h base:%0h X:%0h C:%b ABW:%b", AB, base, XY, abl_ci, ABWDTH);
//$display("ABL:%h", ABL);
end

/*
 * carry input for high byte 
 */
wire abh_ci = ab_op[9] & abl_co;    // + in +H 2'b

/* 
 * calculate address high byte
 */
always @* begin
    case( ab_op[9:8] )              // +H 2'b
        2'b00: {abh_co, ABH} = base[15:8] + 8'h00 + abh_ci;   // ci = 0
        2'b01: {abh_co, ABH} = base[15:8] + 8'h01 + abh_ci;   // ci = 0
        2'b10: {abh_co, ABH} = base[15:8] + 8'h00 + abh_ci;   // ci = abl_ci
        2'b11: {abh_co, ABH} = base[15:8] + 8'hff + abh_ci;   // ci = abl_ci
    endcase
//$display("ABH:%h", ABH);
end

/* 
 * calculate 3rd address byte
 */
always @* begin
    case( ab_op[9:8] )              // +H 2'b
        2'b11: AB3 = base[23:16] + 8'hff + abh_co;  // BACK
        default: AB3 = base[23:16] + abh_co;        // FORWARD
    endcase    
//$display("AB3:%h", AB3);
end

endmodule
