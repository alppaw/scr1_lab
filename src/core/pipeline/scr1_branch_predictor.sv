

module scr1_branch_predictor (
    input  logic        clk,
    input  logic        rst_n,
    
    input  logic [31:0] curr_pc_i,
    
    input  logic        exu_branch_resolved_i,
    input  logic        exu_branch_taken_i,
    input  logic [31:0] exu_branch_pc_i,
    input  logic [31:0] exu_target_pc_i,
    
    output logic        predict_taken_o,
    output logic [31:0] predict_pc_o
);

    localparam BTB_SIZE    = 16;
    localparam INDEX_WIDTH = 4;
    localparam TAG_WIDTH   = 32 - INDEX_WIDTH - 1;

    localparam SNT = 2'b00;
    localparam WNT = 2'b01;
    localparam WT  = 2'b10;
    localparam ST  = 2'b11;

    logic [TAG_WIDTH-1:0] btb_tag    [BTB_SIZE-1:0] = '{default: '0};
    logic [31:0]          btb_target [BTB_SIZE-1:0] = '{default: '0};
    logic                 btb_valid  [BTB_SIZE-1:0] = '{default: 1'b0};
    logic [1:0]           bht_state  [BTB_SIZE-1:0] = '{default: WNT};

    logic [INDEX_WIDTH-1:0] read_index;
    logic [TAG_WIDTH-1:0]   read_tag;
    logic                   btb_hit;

    assign read_index = curr_pc_i[INDEX_WIDTH:1];
    assign read_tag   = curr_pc_i[31:INDEX_WIDTH+1];

    assign btb_hit = btb_valid[read_index] && (btb_tag[read_index] == read_tag);

   assign predict_taken_o =
    btb_hit &&
    bht_state[read_index][1] &&
    (btb_target[read_index][1:0] == 2'b00);
    assign predict_pc_o    = btb_target[read_index];

    logic [INDEX_WIDTH-1:0] write_index;
    logic [TAG_WIDTH-1:0]   write_tag;

    assign write_index = exu_branch_pc_i[INDEX_WIDTH:1];
    assign write_tag   = exu_branch_pc_i[31:INDEX_WIDTH+1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < BTB_SIZE; i = i + 1) begin
                btb_valid[i] <= 1'b0;
            end
        end else if (exu_branch_resolved_i) begin
            btb_valid[write_index]  <= 1'b1;
            btb_tag[write_index]    <= write_tag;
            btb_target[write_index] <= exu_target_pc_i;

            if (exu_branch_taken_i) begin
                if (bht_state[write_index] != ST) begin
                    bht_state[write_index] <= bht_state[write_index] + 1'b1;
                end
            end else begin
                if (bht_state[write_index] != SNT) begin
                    bht_state[write_index] <= bht_state[write_index] - 1'b1;
                end
            end
        end
    end
endmodule
