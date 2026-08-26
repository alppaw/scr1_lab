`include "scr1_memif.svh"
`include "scr1_arch_description.svh"

module d_cache #(
    parameter WIDTH_OF_D = 32,
    parameter COLUMNS    = 4,
    parameter ROWS       = 256
) (
    input   logic                          clk,
    input   logic                          rst_n,

    // Интерфейс Ядра (Core)
    input   logic                          core_req,
    input   logic [WIDTH_OF_D-1:0]         core_addr,
    input   type_scr1_mem_cmd_e            core_cmd,     
    input   type_scr1_mem_width_e          core_width,   
    input   logic [WIDTH_OF_D-1:0]         core_wdata,   
    output  logic                          core_req_ack,
    output  logic [WIDTH_OF_D-1:0]         core_rdata,
    output  type_scr1_mem_resp_e           core_resp,

    // Интерфейс Шины / Роутера (Bus)
    output  logic                          bus_req,
    output  logic [WIDTH_OF_D-1:0]         bus_addr,
    output  type_scr1_mem_cmd_e            bus_cmd,
    output  type_scr1_mem_width_e          bus_width,
    output  logic [WIDTH_OF_D-1:0]         bus_wdata,
    input   logic                          bus_req_ack,
    input   logic [WIDTH_OF_D-1:0]         bus_rdata,
    input   type_scr1_mem_resp_e           bus_resp
);

    localparam BYTE_OFFSET = $clog2(WIDTH_OF_D/8);
    localparam WORD_OFFSET = $clog2(COLUMNS);
    localparam INDEX       = $clog2(ROWS);
    localparam TAG         = WIDTH_OF_D - INDEX - WORD_OFFSET - BYTE_OFFSET;

    wire [INDEX-1:0] req_index = core_addr[BYTE_OFFSET+WORD_OFFSET +: INDEX];

    (* ram_style = "block" *) logic [WIDTH_OF_D*COLUMNS-1:0] cache_data [0:ROWS-1];
    (* ram_style = "block" *) logic [TAG-1:0]                cache_tags [0:ROWS-1];
    logic                                                    cache_valid[0:ROWS-1];

    // Защелкнутые сигналы текущей операции
    logic [WIDTH_OF_D-1:0]        lat_addr; 
    type_scr1_mem_cmd_e           lat_cmd;
    type_scr1_mem_width_e         lat_width;
    logic [WIDTH_OF_D-1:0]        lat_wdata;

    wire [TAG-1:0]         lat_tag    = lat_addr[WIDTH_OF_D-1 -: TAG];
    wire [INDEX-1:0]       lat_index  = lat_addr[BYTE_OFFSET+WORD_OFFSET +: INDEX];
    wire [WORD_OFFSET-1:0] lat_offset = lat_addr[BYTE_OFFSET +: WORD_OFFSET];
    wire [1:0]             lat_byte   = lat_addr[1:0];

    logic [WIDTH_OF_D*COLUMNS-1:0] line_data_read;
    logic [TAG-1:0]                tag_read;

    wire accept_new_req = (state == IDLE) || 
                          (state == CHECK && cache_hit && lat_cmd == SCR1_MEM_CMD_RD) || 
                          (state == WRITE_DONE);

    wire [INDEX-1:0] bram_read_idx = (accept_new_req && core_req) ? req_index : lat_index;

    always_ff @(posedge clk) begin
        line_data_read <= cache_data[bram_read_idx];
        tag_read       <= cache_tags[bram_read_idx];
    end

    wire valid_read = cache_valid[lat_index];
    wire cache_hit  = valid_read && (tag_read == lat_tag);

    typedef enum logic [2:0] {
        IDLE, CHECK, 
        REFILL_REQ, REFILL_WAIT, REFILL_DONE, 
        WRITE_REQ, WRITE_WAIT, WRITE_DONE
    } state_t;
    state_t state;

    logic [WORD_OFFSET-1:0]        word_counter;
    logic [WIDTH_OF_D-1:0]        words_buf [0:COLUMNS-2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state        <= IDLE;
            word_counter <= '0;
            lat_addr     <= '0;
            lat_cmd      <= SCR1_MEM_CMD_RD;
            lat_width    <= SCR1_MEM_WIDTH_WORD;
            lat_wdata    <= '0;
            for (int i = 0; i < ROWS; i++) cache_valid[i] <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    word_counter <= '0;
                    if (core_req) begin
                        lat_addr  <= core_addr;
                        lat_cmd   <= core_cmd;
                        lat_width <= core_width;
                        lat_wdata <= core_wdata;
                        state     <= CHECK;
                    end
                end

                CHECK: begin
                    if (lat_cmd == SCR1_MEM_CMD_WR) begin
                        state <= WRITE_REQ;
                    end 
                    else begin
                        if (!core_req) begin
                            state <= IDLE;
                        end else if (cache_hit) begin
                            lat_addr  <= core_addr;
                            lat_cmd   <= core_cmd;
                            lat_width <= core_width;
                            lat_wdata <= core_wdata;
                            state     <= CHECK;
                        end else begin
                            word_counter <= '0;
                            state        <= REFILL_REQ;
                        end
                    end
                end

                REFILL_REQ: begin
                    if (bus_req_ack) state <= REFILL_WAIT;
                end

                REFILL_WAIT: begin
                    if (bus_resp == SCR1_MEM_RESP_RDY_OK) begin
                        if (word_counter == COLUMNS-1) begin
                            cache_data[lat_index]  <= {bus_rdata, words_buf[2], words_buf[1], words_buf[0]};
                            cache_tags[lat_index]  <= lat_tag;
                            cache_valid[lat_index] <= 1'b1;
                            state <= REFILL_DONE;
                        end else begin
                            words_buf[word_counter] <= bus_rdata;
                            word_counter <= word_counter + 1'b1;
                            state        <= REFILL_REQ;
                        end
                    end else if (bus_resp == SCR1_MEM_RESP_RDY_ER) begin
                        state <= IDLE;
                    end
                end

                REFILL_DONE: state <= CHECK;

                WRITE_REQ: begin
                    if (bus_req_ack) state <= WRITE_WAIT;
                end

                WRITE_WAIT: begin
                    if (bus_resp == SCR1_MEM_RESP_RDY_OK || bus_resp == SCR1_MEM_RESP_RDY_ER) begin
                        if (cache_valid[lat_index] && (cache_tags[lat_index] == lat_tag)) begin
                            cache_valid[lat_index] <= 1'b0;
                        end
                        state <= WRITE_DONE;
                    end
                end

                WRITE_DONE: begin
                    if (core_req) begin
                        lat_addr  <= core_addr;
                        lat_cmd   <= core_cmd;
                        lat_width <= core_width;
                        lat_wdata <= core_wdata;
                        state     <= CHECK;
                    end else begin
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    
    logic [WIDTH_OF_D-1:0] full_word_read;
    assign full_word_read = line_data_read[lat_offset*WIDTH_OF_D +: WIDTH_OF_D];

    assign core_rdata = full_word_read >> (lat_byte * 8);

    assign core_req_ack = accept_new_req;

    assign core_resp = (state == CHECK && cache_hit && lat_cmd == SCR1_MEM_CMD_RD) ? SCR1_MEM_RESP_RDY_OK :
                       (state == WRITE_DONE)                                        ? SCR1_MEM_RESP_RDY_OK : 
                                                                                      SCR1_MEM_RESP_NOTRDY;

    
    wire is_write = (state == WRITE_REQ) || (state == WRITE_WAIT);

    assign bus_req   = (state == REFILL_REQ) || (state == WRITE_REQ);
    assign bus_cmd   = is_write ? SCR1_MEM_CMD_WR : SCR1_MEM_CMD_RD;
    assign bus_width = is_write ? lat_width : SCR1_MEM_WIDTH_WORD;
    assign bus_wdata = lat_wdata;
    assign bus_addr  = is_write ? lat_addr : {lat_tag, lat_index, word_counter, {BYTE_OFFSET{1'b0}}};

endmodule