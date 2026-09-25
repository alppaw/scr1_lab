/// Copyright by Syntacore LLC © 2016-2021. See LICENSE for details
/// @file       <scr1_branch_predictor.sv>
/// @brief      Small branch target buffer for word-aligned branch starts

`include "scr1_arch_description.svh"

module scr1_branch_predictor (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       invalidate_i,
    input  logic [`SCR1_XLEN-1:0]      lookup_pc_i,
    output logic                       predict_taken_o,
    output logic [`SCR1_XLEN-1:0]      predict_target_o,
    input  logic                       train_valid_i,
    input  logic                       train_taken_i,
    input  logic [`SCR1_XLEN-1:0]      train_pc_i,
    input  logic [`SCR1_XLEN-1:0]      train_target_i
);

localparam int ENTRY_COUNT = 8;
localparam int INDEX_W = $clog2(ENTRY_COUNT);
localparam int TAG_W = `SCR1_XLEN - INDEX_W - 2;

logic [ENTRY_COUNT-1:0] valid;
logic [TAG_W-1:0] tag [ENTRY_COUNT];
logic [`SCR1_XLEN-1:0] target [ENTRY_COUNT];
logic [1:0] counter [ENTRY_COUNT];
logic [INDEX_W-1:0] lookup_index;
logic [INDEX_W-1:0] train_index;
logic [TAG_W-1:0] lookup_tag;
logic [TAG_W-1:0] train_tag;
logic train_hit;
logic train_word_branch;

assign lookup_index = lookup_pc_i[INDEX_W+1:2];
assign train_index = train_pc_i[INDEX_W+1:2];
assign lookup_tag = lookup_pc_i[`SCR1_XLEN-1:INDEX_W+2];
assign train_tag = train_pc_i[`SCR1_XLEN-1:INDEX_W+2];
assign train_hit = valid[train_index] && (tag[train_index] == train_tag);
assign train_word_branch = train_valid_i && (train_pc_i[1:0] == 2'b00)
                         && (train_target_i[1:0] == 2'b00);

// A tag match and the high bit of the saturating counter select taken.
`ifdef SCR1_BP_DISABLE
assign predict_taken_o = 1'b0;
`else
assign predict_taken_o = valid[lookup_index]
                       && (tag[lookup_index] == lookup_tag)
                       && counter[lookup_index][1];
`endif
assign predict_target_o = target[lookup_index];

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        valid <= '0;
    end else if (invalidate_i) begin
        valid <= '0;
    end else if (train_word_branch && !train_hit && train_taken_i) begin
        valid[train_index] <= 1'b1;
    end
end

// The data arrays do not need a reset: valid masks their contents until
// the first taken branch supplies a tag, a target and an initial counter.
always_ff @(posedge clk) begin
    if (rst_n && !invalidate_i && train_word_branch) begin
        if (train_hit) begin
            target[train_index] <= train_target_i;
            if (train_taken_i && counter[train_index] != 2'b11)
                counter[train_index] <= counter[train_index] + 1'b1;
            else if (!train_taken_i && counter[train_index] != 2'b00)
                counter[train_index] <= counter[train_index] - 1'b1;
        end else if (train_taken_i) begin
            tag[train_index] <= train_tag;
            target[train_index] <= train_target_i;
            counter[train_index] <= 2'b10;
        end
    end
end

endmodule
