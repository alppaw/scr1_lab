`include "scr1_memif.svh"
`include "scr1_arch_description.svh"

// Blocking direct-mapped SCR1 data cache.
// Read allocate, write through, no write allocate, one outstanding request.
// cache_data_ram is intentionally coded as a synchronous, single-port RAM so
// that Xilinx Vivado can infer RAMB primitives.
module d_cache #(
    parameter int unsigned WIDTH_OF_D = 32,
    parameter int unsigned COLUMNS    = 4,
    parameter int unsigned ROWS       = 256,
    // Nexys 4 DDR: only the 128 MiB SDRAM window is cacheable. External
    // peripherals and boot SRAM accesses must preserve their original width
    // and must never be served from a cached copy.
    parameter logic [WIDTH_OF_D-1:0] CACHEABLE_ADDR_MASK    = 32'hF800_0000,
    parameter logic [WIDTH_OF_D-1:0] CACHEABLE_ADDR_PATTERN = 32'h0000_0000
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         core_req,
    input  logic [WIDTH_OF_D-1:0]        core_addr,
    input  type_scr1_mem_cmd_e           core_cmd,
    input  type_scr1_mem_width_e         core_width,
    input  logic [WIDTH_OF_D-1:0]        core_wdata,
    output logic                         core_req_ack,
    output logic [WIDTH_OF_D-1:0]        core_rdata,
    output type_scr1_mem_resp_e          core_resp,

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
localparam int unsigned LINE_WIDTH     = WIDTH_OF_D * COLUMNS;

typedef enum logic [2:0] {
    ST_IDLE,
    ST_LOOKUP,
    ST_BUS_REQ,
    ST_BUS_WAIT,
    ST_RESP
} state_t;

state_t state;

// 256 × 128 бит при стандартных параметрах.
// Не добавляй reset к этому массиву: иначе Vivado не выведет BRAM.
(* ram_style = "block" *)
logic [LINE_WIDTH-1:0] cache_data_ram [0:ROWS-1];

logic [LINE_WIDTH-1:0] cache_data_rdata;
logic [INDEX_BITS-1:0] cache_data_raddr;
logic [INDEX_BITS-1:0] cache_data_waddr;
logic [LINE_WIDTH-1:0] cache_data_wdata;
logic                  cache_data_we;

// Теги небольшие, поэтому пусть Vivado реализует их в distributed RAM.
(* ram_style = "distributed" *)
logic [TAG_BITS-1:0] cache_tag_ram [0:ROWS-1];

logic cache_valid [0:ROWS-1];

logic [WIDTH_OF_D-1:0] req_addr_q;
logic [WIDTH_OF_D-1:0] req_wdata_q;
type_scr1_mem_cmd_e    req_cmd_q;
type_scr1_mem_width_e  req_width_q;

logic [WORD_OFF_BITS-1:0] refill_word_q;
logic [LINE_WIDTH-1:0]    refill_line_q;
logic [WIDTH_OF_D-1:0]    response_data_q;
type_scr1_mem_resp_e      response_q;

wire [WORD_OFF_BITS-1:0] req_word =
    req_addr_q[BYTE_OFF_BITS +: WORD_OFF_BITS];

wire [INDEX_BITS-1:0] req_index =
    req_addr_q[LINE_OFF_BITS +: INDEX_BITS];

wire [TAG_BITS-1:0] req_tag =
    req_addr_q[WIDTH_OF_D-1 -: TAG_BITS];

wire req_hit =
    cache_valid[req_index] &&
    (cache_tag_ram[req_index] == req_tag);

wire req_cacheable =
    (req_addr_q & CACHEABLE_ADDR_MASK) == CACHEABLE_ADDR_PATTERN;

function automatic logic [WIDTH_OF_D-1:0] line_get_word(
    input logic [LINE_WIDTH-1:0] line,
    input logic [WORD_OFF_BITS-1:0] word_number
);
    line_get_word = line[word_number*WIDTH_OF_D +: WIDTH_OF_D];
endfunction

function automatic logic [LINE_WIDTH-1:0] line_put_word(
    input logic [LINE_WIDTH-1:0] line,
    input logic [WORD_OFF_BITS-1:0] word_number,
    input logic [WIDTH_OF_D-1:0] word_data
);
    logic [LINE_WIDTH-1:0] result;

    begin
        result = line;
        result[word_number*WIDTH_OF_D +: WIDTH_OF_D] = word_data;
        line_put_word = result;
    end
endfunction

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
    logic [WIDTH_OF_D-1:0] mask;
    logic [WIDTH_OF_D-1:0] shifted_data;

    begin
        case (width)
            SCR1_MEM_WIDTH_BYTE:
                mask = 32'h000000ff << (8 * byte_offset);

            SCR1_MEM_WIDTH_HWORD:
                mask = 32'h0000ffff << (8 * byte_offset);

            SCR1_MEM_WIDTH_WORD:
                mask = 32'hffffffff;

            default:
                mask = '0;
        endcase

        shifted_data = new_data << (8 * byte_offset);

        store_merge = (old_word & ~mask) | (shifted_data & mask);
    end
endfunction

wire [LINE_WIDTH-1:0] refill_line_with_bus_word =
    line_put_word(refill_line_q, refill_word_q, bus_rdata);

wire [WIDTH_OF_D-1:0] store_merged_word =
    store_merge(
        line_get_word(cache_data_rdata, req_word),
        req_wdata_q,
        req_width_q,
        req_addr_q[BYTE_OFF_BITS-1:0]
    );

// Единственное место чтения и записи data RAM.
always_ff @(posedge clk) begin
    if (cache_data_we) begin
        cache_data_ram[cache_data_waddr] <= cache_data_wdata;
    end

    cache_data_rdata <= cache_data_ram[cache_data_raddr];
end

always_comb begin
    // При принятии core-запроса адрес подаётся на BRAM.
    // В ST_LOOKUP данные уже будут на cache_data_rdata.
    cache_data_raddr = (state == ST_IDLE)
                     ? core_addr[LINE_OFF_BITS +: INDEX_BITS]
                     : req_index;

    cache_data_we    = 1'b0;
    cache_data_waddr = req_index;
    cache_data_wdata = refill_line_with_bus_word;

    if ((state == ST_BUS_WAIT) &&
        (bus_resp == SCR1_MEM_RESP_RDY_OK)) begin

        // После получения всех 4 слов строка записывается в BRAM одним разом.
        if ((req_cmd_q == SCR1_MEM_CMD_RD) && req_cacheable &&
            (refill_word_q == COLUMNS - 1)) begin

            cache_data_we    = 1'b1;
            cache_data_wdata = refill_line_with_bus_word;

        // Write-hit: обновляется вся строка за одну операцию записи.
        end else if ((req_cmd_q == SCR1_MEM_CMD_WR) &&
                     req_cacheable && req_hit) begin
            cache_data_we    = 1'b1;
            cache_data_wdata = line_put_word(
                cache_data_rdata,
                req_word,
                store_merged_word
            );
        end
    end
end

always_comb begin
    core_req_ack = (state == ST_IDLE);
    core_rdata   = response_data_q;
    core_resp    = SCR1_MEM_RESP_NOTRDY;
    if (state == ST_RESP) begin
        core_resp = response_q;
    end

    bus_req   = (state == ST_BUS_REQ);
    bus_cmd   = req_cmd_q;
    bus_width = req_width_q;
    bus_addr  = req_addr_q;
    bus_wdata = req_wdata_q;

    // Refill: четыре выровненных 32-битных чтения.
    if ((req_cmd_q == SCR1_MEM_CMD_RD) && req_cacheable) begin
        bus_cmd   = SCR1_MEM_CMD_RD;
        bus_width = SCR1_MEM_WIDTH_WORD;
        bus_addr  = {
            req_addr_q[WIDTH_OF_D-1:LINE_OFF_BITS],
            refill_word_q,
            {BYTE_OFF_BITS{1'b0}}
        };
        bus_wdata = '0;
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
        refill_line_q   <= '0;
        response_data_q <= '0;
        response_q      <= SCR1_MEM_RESP_NOTRDY;

        // Сбрасываются только valid-биты.
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

                    if (!req_cacheable) begin
                        // A line fill from MMIO could consume UART data and
                        // would make a polled status register permanently stale.
                        state <= ST_BUS_REQ;

                    end else if (req_hit) begin
                        response_data_q <= load_align(
                            line_get_word(cache_data_rdata, req_word),
                            req_addr_q[BYTE_OFF_BITS-1:0]
                        );
                        response_q <= SCR1_MEM_RESP_RDY_OK;
                        state      <= ST_RESP;

                    end else begin
                        cache_valid[req_index] <= 1'b0;
                        refill_word_q          <= '0;
                        refill_line_q          <= '0;
                        state                  <= ST_BUS_REQ;
                    end

                end else begin
                    // Write-through, no-write-allocate.
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
                        response_data_q <= '0;
                        response_q      <= SCR1_MEM_RESP_RDY_OK;
                        state           <= ST_RESP;

                    end else if (!req_cacheable) begin
                        // scr1_mem_axi has already aligned sub-word reads.
                        response_data_q <= bus_rdata;
                        response_q      <= SCR1_MEM_RESP_RDY_OK;
                        state           <= ST_RESP;

                    end else begin
                        refill_line_q <= refill_line_with_bus_word;

                        if (refill_word_q == COLUMNS - 1) begin
                            cache_tag_ram[req_index] <= req_tag;
                            cache_valid[req_index]   <= 1'b1;

                            response_data_q <= load_align(
                                line_get_word(
                                    refill_line_with_bus_word,
                                    req_word
                                ),
                                req_addr_q[BYTE_OFF_BITS-1:0]
                            );

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
