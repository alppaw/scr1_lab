`include "scr1_memif.svh"
`include "scr1_arch_description.svh"

// Blocking direct-mapped cache for the native SCR1 memory interface.
// Policy: read-allocate, write-through, no-write-allocate, one request at a time.
module d_cache #(
    parameter int unsigned WIDTH_OF_D = 32,
    parameter int unsigned COLUMNS    = 4,
    parameter int unsigned ROWS       = 256
) (
    input  logic                         clk,
    input  logic                         rst_n,

    // Interface from scr1_dmem_router
    input  logic                         core_req,
    input  logic [WIDTH_OF_D-1:0]        core_addr,
    input  type_scr1_mem_cmd_e           core_cmd,
    input  type_scr1_mem_width_e         core_width,
    input  logic [WIDTH_OF_D-1:0]        core_wdata,
    output logic                         core_req_ack,
    output logic [WIDTH_OF_D-1:0]        core_rdata,
    output type_scr1_mem_resp_e          core_resp,

    // Interface to scr1_mem_axi
    output logic                         bus_req,
    output logic [WIDTH_OF_D-1:0]        bus_addr,
    output type_scr1_mem_cmd_e           bus_cmd,
    output type_scr1_mem_width_e         bus_width,
    output logic [WIDTH_OF_D-1:0]        bus_wdata,
    input  logic                         bus_req_ack,
    input  logic [WIDTH_OF_D-1:0]        bus_rdata,
    input  type_scr1_mem_resp_e          bus_resp
);

localparam int unsigned BYTES_PER_WORD = WIDTH_OF_D / 8;
localparam int unsigned BYTE_OFF_BITS  = $clog2(BYTES_PER_WORD);
localparam int unsigned WORD_OFF_BITS  = $clog2(COLUMNS);
localparam int unsigned INDEX_BITS     = $clog2(ROWS);
localparam int unsigned LINE_OFF_BITS  = BYTE_OFF_BITS + WORD_OFF_BITS;
localparam int unsigned TAG_BITS       = WIDTH_OF_D - INDEX_BITS - LINE_OFF_BITS;

typedef enum logic [2:0] {
    ST_IDLE,
    ST_LOOKUP,
    ST_BUS_REQ,
    ST_BUS_WAIT,
    ST_RESP
} state_t;

state_t state;

logic [WIDTH_OF_D-1:0] cache_data  [0:ROWS-1][0:COLUMNS-1];
logic [TAG_BITS-1:0]   cache_tag   [0:ROWS-1];
logic                  cache_valid [0:ROWS-1];

logic [WIDTH_OF_D-1:0] req_addr_q;
logic [WIDTH_OF_D-1:0] req_wdata_q;
type_scr1_mem_cmd_e    req_cmd_q;
type_scr1_mem_width_e  req_width_q;

logic [WORD_OFF_BITS-1:0] refill_word_q;
logic [WIDTH_OF_D-1:0]   refill_result_q;
logic [WIDTH_OF_D-1:0]   response_data_q;
type_scr1_mem_resp_e     response_q;

wire [WORD_OFF_BITS-1:0] req_word =
    req_addr_q[BYTE_OFF_BITS +: WORD_OFF_BITS];

wire [INDEX_BITS-1:0] req_index =
    req_addr_q[LINE_OFF_BITS +: INDEX_BITS];

wire [TAG_BITS-1:0] req_tag =
    req_addr_q[WIDTH_OF_D-1 -: TAG_BITS];

wire req_hit =
    cache_valid[req_index] && (cache_tag[req_index] == req_tag);

function automatic logic [WIDTH_OF_D-1:0] load_align(
    input logic [WIDTH_OF_D-1:0] word,
    input logic [BYTE_OFF_BITS-1:0] byte_offset
);
    load_align = word >> (8 * byte_offset);
endfunction

function automatic logic [WIDTH_OF_D-1:0] store_merge(
    input logic [WIDTH_OF_D-1:0] old_word,
    input logic [WIDTH_OF_D-1:0] new_data,
    input type_scr1_mem_width_e  width,
    input logic [BYTE_OFF_BITS-1:0] byte_offset
);
    logic [WIDTH_OF_D-1:0] result;

    begin
        result = old_word;

        case (width)
            SCR1_MEM_WIDTH_BYTE:
                result[byte_offset*8 +: 8] = new_data[7:0];

            SCR1_MEM_WIDTH_HWORD:
                result[byte_offset[1]*16 +: 16] = new_data[15:0];

            SCR1_MEM_WIDTH_WORD:
                result = new_data;

            default:
                result = old_word;
        endcase

        store_merge = result;
    end
endfunction

always_comb begin
    core_req_ack = (state == ST_IDLE);
    core_rdata   = response_data_q;
    core_resp    = (state == ST_RESP)
                 ? response_q
                 : SCR1_MEM_RESP_NOTRDY;

    bus_req      = (state == ST_BUS_REQ);
    bus_cmd      = req_cmd_q;
    bus_width    = req_width_q;
    bus_wdata    = req_wdata_q;
    bus_addr     = req_addr_q;

    // Refill: always read a complete aligned 32-bit word.
    if (req_cmd_q == SCR1_MEM_CMD_RD) begin
        bus_cmd   = SCR1_MEM_CMD_RD;
        bus_width = SCR1_MEM_WIDTH_WORD;
        bus_wdata = '0;
        bus_addr  = {
            req_addr_q[WIDTH_OF_D-1:LINE_OFF_BITS],
            refill_word_q,
            {BYTE_OFF_BITS{1'b0}}
        };
    end
end

always_ff @(posedge clk or negedge rst_n) begin : cache_fsm
    integer i;

    if (!rst_n) begin
        state           <= ST_IDLE;
        req_addr_q      <= '0;
        req_wdata_q     <= '0;
        req_cmd_q       <= SCR1_MEM_CMD_RD;
        req_width_q     <= SCR1_MEM_WIDTH_WORD;
        refill_word_q   <= '0;
        refill_result_q <= '0;
        response_data_q <= '0;
        response_q      <= SCR1_MEM_RESP_NOTRDY;

        for (i = 0; i < ROWS; i = i + 1) begin
            cache_valid[i] <= 1'b0;
        end
    end else begin
        case (state)

            ST_IDLE: begin
                response_q <= SCR1_MEM_RESP_NOTRDY;

                if (core_req) begin
                    req_addr_q  <= core_addr;
                    req_wdata_q <= core_wdata;
                    req_cmd_q   <= core_cmd;
                    req_width_q <= core_width;
                    state       <= ST_LOOKUP;
                end
            end

            ST_LOOKUP: begin
                if (req_cmd_q == SCR1_MEM_CMD_RD) begin

                    if (req_hit) begin
                        response_data_q <= load_align(
                            cache_data[req_index][req_word],
                            req_addr_q[BYTE_OFF_BITS-1:0]
                        );
                        response_q <= SCR1_MEM_RESP_RDY_OK;
                        state      <= ST_RESP;

                    end else begin
                        // Prevent a partially loaded line becoming valid.
                        cache_valid[req_index] <= 1'b0;
                        refill_word_q          <= '0;
                        refill_result_q        <= '0;
                        state                  <= ST_BUS_REQ;
                    end

                end else begin
                    // Write-through. No line refill on write miss.
                    state <= ST_BUS_REQ;
                end
            end

            ST_BUS_REQ: begin
                if (bus_req_ack) begin
                    state <= ST_BUS_WAIT;
                end
            end

            ST_BUS_WAIT: begin
                if (bus_resp == SCR1_MEM_RESP_RDY_ER) begin
                    response_data_q <= '0;
                    response_q      <= SCR1_MEM_RESP_RDY_ER;
                    state           <= ST_RESP;

                end else if (bus_resp == SCR1_MEM_RESP_RDY_OK) begin

                    if (req_cmd_q == SCR1_MEM_CMD_WR) begin
                        // Update cached data only after successful AXI write.
                        if (req_hit) begin
                            cache_data[req_index][req_word] <= store_merge(
                                cache_data[req_index][req_word],
                                req_wdata_q,
                                req_width_q,
                                req_addr_q[BYTE_OFF_BITS-1:0]
                            );
                        end

                        response_data_q <= '0;
                        response_q      <= SCR1_MEM_RESP_RDY_OK;
                        state           <= ST_RESP;

                    end else begin
                        cache_data[req_index][refill_word_q] <= bus_rdata;

                        if (refill_word_q == req_word) begin
                            refill_result_q <= load_align(
                                bus_rdata,
                                req_addr_q[BYTE_OFF_BITS-1:0]
                            );
                        end

                        if (refill_word_q == COLUMNS - 1) begin
                            cache_tag[req_index]   <= req_tag;
                            cache_valid[req_index] <= 1'b1;

                            response_data_q <= (refill_word_q == req_word)
                                ? load_align(
                                    bus_rdata,
                                    req_addr_q[BYTE_OFF_BITS-1:0]
                                )
                                : refill_result_q;

                            response_q <= SCR1_MEM_RESP_RDY_OK;
                            state      <= ST_RESP;

                        end else begin
                            refill_word_q <= refill_word_q + 1'b1;
                            state         <= ST_BUS_REQ;
                        end
                    end
                end
            end

            ST_RESP: begin
                state <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule : d_cache