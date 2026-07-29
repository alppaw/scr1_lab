`include "scr1_memif.svh"
`include "scr1_arch_description.svh"
`include "scr1_riscv_isa_decoding.svh"


module i_cache #(
    parameter WIDTH_OF_I  = 32,
    parameter COLUMNS     = 4,
    parameter ROWS        = 256
) (
    input   logic clk,
    input   logic rst_n,

    // Интерфейс Ядра
    input   logic                    core_req,
    input   logic [WIDTH_OF_I-1:0]   core_addr,
    input   type_scr1_mem_cmd_e      core_cmd,
    output  logic                    core_req_ack,
    output  logic [WIDTH_OF_I-1:0]   core_rdata,
    output  type_scr1_mem_resp_e     core_resp,

    input  type_scr1_exu_cmd_s       idu2exu_cmd,                // IDU command (see scr1_riscv_isa_decoding.svh)


    // Интерфейс Шины (AXI / Router)
    output  logic                    bus_req,
    output  logic [WIDTH_OF_I-1:0]   bus_addr,
    output  type_scr1_mem_cmd_e      bus_cmd,
    input   logic                    bus_req_ack,
    input   logic [WIDTH_OF_I-1:0]   bus_rdata,
    input   type_scr1_mem_resp_e     bus_resp
);

localparam BYTES_PER_WORD = WIDTH_OF_I/8;
localparam BYTE_OFFSET    = $clog2(BYTES_PER_WORD);
localparam WORD_OFFSET    = $clog2(COLUMNS);
localparam INDEX          = $clog2(ROWS);
localparam TAG            = WIDTH_OF_I - INDEX - WORD_OFFSET - BYTE_OFFSET;

wire [WORD_OFFSET-1:0] req_offset = core_addr[BYTE_OFFSET +: WORD_OFFSET];
wire [INDEX-1:0]       req_index  = core_addr[BYTE_OFFSET+WORD_OFFSET +: INDEX];
wire [TAG-1:0]         req_tag    = core_addr[WIDTH_OF_I-1 -: TAG];

(* ram_style = "block" *) logic [WIDTH_OF_I*COLUMNS-1:0] cache_data [0:ROWS-1];
(* ram_style = "block" *) logic [TAG-1:0]                cache_tags [0:ROWS-1];
logic                                                    cache_valid[0:ROWS-1];

logic [TAG-1:0]         lat_tag;
logic [INDEX-1:0]       lat_index;
logic [WORD_OFFSET-1:0] lat_offset;

logic [WIDTH_OF_I*COLUMNS-1:0] line_data_read;
logic [TAG-1:0]                tag_read;
logic                          valid_read;


wire accept_new_req = (state == IDLE) || (state == CHECK && cache_hit);
wire [INDEX-1:0] bram_read_idx = (accept_new_req && core_req) ? req_index : lat_index;

always_ff @(posedge clk) begin
    line_data_read  <= cache_data[bram_read_idx];
    tag_read        <= cache_tags[bram_read_idx];
    valid_read      <= cache_valid[bram_read_idx];
end

wire cache_hit  = refill_just_done ? 1'b1 : (valid_read && (tag_read == lat_tag));
wire [WIDTH_OF_I*COLUMNS-1:0] hit_line = refill_just_done ? refill_just_data : line_data_read;

assign bus_cmd = SCR1_MEM_CMD_RD;

typedef enum logic [2:0] {IDLE, CHECK, REFILL_REQ, REFILL_WAIT, REFILL_DONE} state_t;
state_t state;

logic [WORD_OFFSET-1:0]         word_counter;
logic [WIDTH_OF_I*COLUMNS-1:0]  refill_buffer;

logic                           refill_just_done;
logic [WIDTH_OF_I*COLUMNS-1:0]  refill_just_data;
logic [TAG-1:0]                 refill_just_tag;

always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        state         <= IDLE;
        word_counter  <= '0;
        refill_buffer <= '0;
        lat_tag       <= '0;
        lat_index     <= '0;
        lat_offset    <= '0;
        refill_just_done <= 1'b0;
        for (int i = 0; i < ROWS; i++) cache_valid[i] <= 1'b0;
    end else begin
        if (idu2exu_cmd.fencei_req) begin
            for (int i = 0; i < ROWS; i++) cache_valid[i] <= 1'b0;
        end 
        refill_just_done <= 1'b0;
        case (state)
            IDLE: begin
                word_counter <= '0;
                if (core_req) begin
                    lat_tag <= req_tag;
                    lat_index <= req_index;
                    lat_offset <= req_offset;
                    state <= CHECK;
                end
            end

            CHECK: begin
                if (cache_hit) begin
                    if (core_req) begin
                        lat_tag <= req_tag;
                        lat_index <= req_index;
                        lat_offset <= req_offset;
                        state <= CHECK;
                    end else begin
                        state <= IDLE;
                    end
                end else begin
                    word_counter <= '0;
                    state <= REFILL_REQ;
                end
            end

            REFILL_REQ: begin
                if (bus_req_ack) state <= REFILL_WAIT;
            end

            REFILL_WAIT: begin
                if (bus_resp == SCR1_MEM_RESP_RDY_OK) begin
                    refill_buffer <= {bus_rdata, refill_buffer[WIDTH_OF_I*COLUMNS-1 : WIDTH_OF_I]};

                    if (&word_counter) begin
                        cache_data[lat_index]  <= {bus_rdata, refill_buffer[WIDTH_OF_I*COLUMNS-1 : WIDTH_OF_I]};
                        cache_tags[lat_index]  <= lat_tag;
                        cache_valid[lat_index] <= 1'b1;

                        refill_just_done <= 1'b1;
                        refill_just_data <= {bus_rdata, refill_buffer[WIDTH_OF_I*COLUMNS-1 : WIDTH_OF_I]};
                        refill_just_tag  <= lat_tag;

                        state <= CHECK;
                    end else begin
                        word_counter <= word_counter + 1'b1;
                        state <= REFILL_REQ;
                    end
                end else if (bus_resp == SCR1_MEM_RESP_RDY_ER) begin
                    state <= IDLE;
                end
            end
        endcase
    end
end

assign core_req_ack = (state == IDLE) || (state == CHECK && cache_hit);
assign core_resp    = (state == CHECK && cache_hit) ? SCR1_MEM_RESP_RDY_OK : SCR1_MEM_RESP_NOTRDY;
assign core_rdata   = hit_line[lat_offset*WIDTH_OF_I +: WIDTH_OF_I];


assign bus_req      = (state == REFILL_REQ);
assign bus_addr     = {lat_tag, lat_index, word_counter, {BYTE_OFFSET{1'b0}}};

endmodule