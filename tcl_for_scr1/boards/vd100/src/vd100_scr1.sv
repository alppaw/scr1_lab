
`include "scr1_arch_description.svh"

module vd100_scr1 (
    input  logic [0:0]  sys_clk_p,
    input  logic [0:0]  sys_clk_n,

    input  logic        PL_KEY1,
    output logic        PL_LED1,

    output wire  [0:0]  DDR4_act_n,
    output wire  [16:0] DDR4_adr,
    output wire  [1:0]  DDR4_ba,
    output wire  [0:0]  DDR4_bg,
    output wire  [0:0]  DDR4_ck_c,
    output wire  [0:0]  DDR4_ck_t,
    output wire  [0:0]  DDR4_cke,
    output wire  [0:0]  DDR4_cs_n,
    inout  wire  [7:0]  DDR4_dm_n,
    inout  wire  [63:0] DDR4_dq,
    inout  wire  [7:0]  DDR4_dqs_c,
    inout  wire  [7:0]  DDR4_dqs_t,
    output wire  [0:0]  DDR4_odt,
    output wire  [0:0]  DDR4_reset_n,
    
    input               PMOD_UART_RXD,
    output              PMOD_UART_TXD
);


logic        cpu_clk;
logic        pwrup_resetn;
logic        soc_resetn;


logic [3:0]  axi_imem_arid;
logic [31:0] axi_imem_araddr;
logic [7:0]  axi_imem_arlen;
logic [2:0]  axi_imem_arsize;
logic [1:0]  axi_imem_arburst;
logic        axi_imem_arlock;
logic [3:0]  axi_imem_arcache;
logic [2:0]  axi_imem_arprot;
logic [3:0]  axi_imem_arqos;
logic        axi_imem_arvalid;
logic        axi_imem_arready;
logic [3:0]  axi_imem_rid;
logic [31:0] axi_imem_rdata;
logic [1:0]  axi_imem_rresp;
logic        axi_imem_rlast;
logic        axi_imem_rvalid;
logic        axi_imem_rready;


logic [3:0]  axi_dmem_awid;
logic [31:0] axi_dmem_awaddr;
logic [7:0]  axi_dmem_awlen;
logic [2:0]  axi_dmem_awsize;
logic [1:0]  axi_dmem_awburst;
logic        axi_dmem_awlock;
logic [3:0]  axi_dmem_awcache;
logic [2:0]  axi_dmem_awprot;
logic [3:0]  axi_dmem_awqos;
logic        axi_dmem_awvalid;
logic        axi_dmem_awready;
logic [31:0] axi_dmem_wdata;
logic [3:0]  axi_dmem_wstrb;
logic        axi_dmem_wlast;
logic        axi_dmem_wvalid;
logic        axi_dmem_wready;
logic [3:0]  axi_dmem_bid;
logic [1:0]  axi_dmem_bresp;
logic        axi_dmem_bvalid;
logic        axi_dmem_bready;
logic [3:0]  axi_dmem_arid;
logic [31:0] axi_dmem_araddr;
logic [7:0]  axi_dmem_arlen;
logic [2:0]  axi_dmem_arsize;
logic [1:0]  axi_dmem_arburst;
logic        axi_dmem_arlock;
logic [3:0]  axi_dmem_arcache;
logic [2:0]  axi_dmem_arprot;
logic [3:0]  axi_dmem_arqos;
logic        axi_dmem_arvalid;
logic        axi_dmem_arready;
logic [3:0]  axi_dmem_rid;
logic [31:0] axi_dmem_rdata;
logic [1:0]  axi_dmem_rresp;
logic        axi_dmem_rlast;
logic        axi_dmem_rvalid;
logic        axi_dmem_rready;


logic [24:0] heartbeat_counter;
always_ff @(posedge cpu_clk or negedge soc_resetn) begin
        if (!soc_resetn) begin
                heartbeat_counter <= '0;
        end else begin
                heartbeat_counter <= heartbeat_counter + 1'b1;
        end
end
assign PL_LED1 = soc_resetn & heartbeat_counter[24];


scr1_top_axi i_scr1 (
        .pwrup_rst_n          (pwrup_resetn),
        .rst_n                (soc_resetn),
        .cpu_rst_n            (soc_resetn),
        .test_mode            (1'b0),
        .test_rst_n           (1'b1),
        .clk                  (cpu_clk),
        .rtc_clk              (1'b0),
        `ifdef SCR1_DBG_EN
        .sys_rst_n_o          (),
        .sys_rdc_qlfy_o       (),
        `endif

        .fuse_mhartid         ('0),
        `ifdef SCR1_DBG_EN
        .fuse_idcode          (`SCR1_TAP_IDCODE),
        `endif

        `ifdef SCR1_IPIC_EN
        .irq_lines            ('0),
        `else
        .ext_irq              (1'b0),
        `endif
        .soft_irq             (1'b0),


        `ifdef SCR1_DBG_EN
        .trst_n               (1'b1),
        .tck                  (1'b0),
        .tms                  (1'b0),
        .tdi                  (1'b0),
        .tdo                  (),
        .tdo_en               (),
        `endif

        .io_axi_imem_awid     (),
        .io_axi_imem_awaddr   (),
        .io_axi_imem_awlen    (),
        .io_axi_imem_awsize   (),
        .io_axi_imem_awburst  (),
        .io_axi_imem_awlock   (),
        .io_axi_imem_awcache  (),
        .io_axi_imem_awprot   (),
        .io_axi_imem_awregion (),
        .io_axi_imem_awuser   (),
        .io_axi_imem_awqos    (),
        .io_axi_imem_awvalid  (),
        .io_axi_imem_awready  (1'b0),
        .io_axi_imem_wdata    (),
        .io_axi_imem_wstrb    (),
        .io_axi_imem_wlast    (),
        .io_axi_imem_wuser    (),
        .io_axi_imem_wvalid   (),
        .io_axi_imem_wready   (1'b0),
        .io_axi_imem_bid      ('0),
        .io_axi_imem_bresp    ('0),
        .io_axi_imem_bvalid   (1'b0),
        .io_axi_imem_buser    ('0),
        .io_axi_imem_bready   (),

        .io_axi_imem_arid     (axi_imem_arid),
        .io_axi_imem_araddr   (axi_imem_araddr),
        .io_axi_imem_arlen    (axi_imem_arlen),
        .io_axi_imem_arsize   (axi_imem_arsize),
        .io_axi_imem_arburst  (axi_imem_arburst),
        .io_axi_imem_arlock   (axi_imem_arlock),
        .io_axi_imem_arcache  (axi_imem_arcache),
        .io_axi_imem_arprot   (axi_imem_arprot),
        .io_axi_imem_arregion (),
        .io_axi_imem_aruser   (),
        .io_axi_imem_arqos    (axi_imem_arqos),
        .io_axi_imem_arvalid  (axi_imem_arvalid),
        .io_axi_imem_arready  (axi_imem_arready),
        .io_axi_imem_rid      (axi_imem_rid),
        .io_axi_imem_rdata    (axi_imem_rdata),
        .io_axi_imem_rresp    (axi_imem_rresp),
        .io_axi_imem_rlast    (axi_imem_rlast),
        .io_axi_imem_ruser    ('0),
        .io_axi_imem_rvalid   (axi_imem_rvalid),
        .io_axi_imem_rready   (axi_imem_rready),

        .io_axi_dmem_awid     (axi_dmem_awid),
        .io_axi_dmem_awaddr   (axi_dmem_awaddr),
        .io_axi_dmem_awlen    (axi_dmem_awlen),
        .io_axi_dmem_awsize   (axi_dmem_awsize),
        .io_axi_dmem_awburst  (axi_dmem_awburst),
        .io_axi_dmem_awlock   (axi_dmem_awlock),
        .io_axi_dmem_awcache  (axi_dmem_awcache),
        .io_axi_dmem_awprot   (axi_dmem_awprot),
        .io_axi_dmem_awregion (),
        .io_axi_dmem_awuser   (),
        .io_axi_dmem_awqos    (axi_dmem_awqos),
        .io_axi_dmem_awvalid  (axi_dmem_awvalid),
        .io_axi_dmem_awready  (axi_dmem_awready),
        .io_axi_dmem_wdata    (axi_dmem_wdata),
        .io_axi_dmem_wstrb    (axi_dmem_wstrb),
        .io_axi_dmem_wlast    (axi_dmem_wlast),
        .io_axi_dmem_wuser    (),
        .io_axi_dmem_wvalid   (axi_dmem_wvalid),
        .io_axi_dmem_wready   (axi_dmem_wready),
        .io_axi_dmem_bid      (axi_dmem_bid),
        .io_axi_dmem_bresp    (axi_dmem_bresp),
        .io_axi_dmem_bvalid   (axi_dmem_bvalid),
        .io_axi_dmem_buser    ('0),
        .io_axi_dmem_bready   (axi_dmem_bready),
        .io_axi_dmem_arid     (axi_dmem_arid),
        .io_axi_dmem_araddr   (axi_dmem_araddr),
        .io_axi_dmem_arlen    (axi_dmem_arlen),
        .io_axi_dmem_arsize   (axi_dmem_arsize),
        .io_axi_dmem_arburst  (axi_dmem_arburst),
        .io_axi_dmem_arlock   (axi_dmem_arlock),
        .io_axi_dmem_arcache  (axi_dmem_arcache),
        .io_axi_dmem_arprot   (axi_dmem_arprot),
        .io_axi_dmem_arregion (),
        .io_axi_dmem_aruser   (),
        .io_axi_dmem_arqos    (axi_dmem_arqos),
        .io_axi_dmem_arvalid  (axi_dmem_arvalid),
        .io_axi_dmem_arready  (axi_dmem_arready),
        .io_axi_dmem_rid      (axi_dmem_rid),
        .io_axi_dmem_rdata    (axi_dmem_rdata),
        .io_axi_dmem_rresp    (axi_dmem_rresp),
        .io_axi_dmem_rlast    (axi_dmem_rlast),
        .io_axi_dmem_ruser    ('0),
        .io_axi_dmem_rvalid   (axi_dmem_rvalid),
        .io_axi_dmem_rready   (axi_dmem_rready)
        );


        vd100_scr1_subsystem_wrapper i_subsystem (
        .sys_clk_p              (sys_clk_p),
        .sys_clk_n              (sys_clk_n),
        .pl_resetn              (PL_KEY1),
        .cpu_clk_o              (cpu_clk),
        .pwrup_resetn_o         (pwrup_resetn),
        .soc_resetn_o           (soc_resetn),

        .DDR4_act_n             (DDR4_act_n),
        .DDR4_adr               (DDR4_adr),
        .DDR4_ba                (DDR4_ba),
        .DDR4_bg                (DDR4_bg),
        .DDR4_ck_c              (DDR4_ck_c),
        .DDR4_ck_t              (DDR4_ck_t),
        .DDR4_cke               (DDR4_cke),
        .DDR4_cs_n              (DDR4_cs_n),
        .DDR4_dm_n              (DDR4_dm_n),
        .DDR4_dq                (DDR4_dq),
        .DDR4_dqs_c             (DDR4_dqs_c),
        .DDR4_dqs_t             (DDR4_dqs_t),
        .DDR4_odt               (DDR4_odt),
        .DDR4_reset_n           (DDR4_reset_n),

        .UART_0_baudoutn        (),
        .UART_0_ctsn            (1'b0),
        .UART_0_dcdn            (1'b0),
        .UART_0_ddis            (),
        .UART_0_dsrn            (1'b0),
        .UART_0_dtrn            (),
        .UART_0_out1n           (),
        .UART_0_out2n           (),
        .UART_0_ri              (1'b1),
        .UART_0_rtsn            (),
        .UART_0_rxd             (PMOD_UART_RXD),    
        .UART_0_rxrdyn          (),
        .UART_0_txd             (PMOD_UART_TXD),
        .UART_0_txrdyn          (),

        .axi_imem_arid          (axi_imem_arid),
        .axi_imem_araddr        (axi_imem_araddr),
        .axi_imem_arlen         (axi_imem_arlen),
        .axi_imem_arsize        (axi_imem_arsize),
        .axi_imem_arburst       (axi_imem_arburst),
        .axi_imem_arlock        (axi_imem_arlock),
        .axi_imem_arcache       (axi_imem_arcache),
        .axi_imem_arprot        (axi_imem_arprot),
        .axi_imem_arqos         (axi_imem_arqos),
        .axi_imem_arvalid       (axi_imem_arvalid),
        .axi_imem_arready       (axi_imem_arready),
        .axi_imem_rid           (axi_imem_rid),
        .axi_imem_rdata         (axi_imem_rdata),
        .axi_imem_rresp         (axi_imem_rresp),
        .axi_imem_rlast         (axi_imem_rlast),
        .axi_imem_rvalid        (axi_imem_rvalid),
        .axi_imem_rready        (axi_imem_rready),

        .axi_dmem_awid          (axi_dmem_awid),
        .axi_dmem_awaddr        (axi_dmem_awaddr),
        .axi_dmem_awlen         (axi_dmem_awlen),
        .axi_dmem_awsize        (axi_dmem_awsize),
        .axi_dmem_awburst       (axi_dmem_awburst),
        .axi_dmem_awlock        (axi_dmem_awlock),
        .axi_dmem_awcache       (axi_dmem_awcache),
        .axi_dmem_awprot        (axi_dmem_awprot),
        .axi_dmem_awqos         (axi_dmem_awqos),
        .axi_dmem_awvalid       (axi_dmem_awvalid),
        .axi_dmem_awready       (axi_dmem_awready),
        .axi_dmem_wdata         (axi_dmem_wdata),
        .axi_dmem_wstrb         (axi_dmem_wstrb),
        .axi_dmem_wlast         (axi_dmem_wlast),
        .axi_dmem_wvalid        (axi_dmem_wvalid),
        .axi_dmem_wready        (axi_dmem_wready),
        .axi_dmem_bid           (axi_dmem_bid),
        .axi_dmem_bresp         (axi_dmem_bresp),
        .axi_dmem_bvalid        (axi_dmem_bvalid),
        .axi_dmem_bready        (axi_dmem_bready),
        .axi_dmem_arid          (axi_dmem_arid),
        .axi_dmem_araddr        (axi_dmem_araddr),
        .axi_dmem_arlen         (axi_dmem_arlen),
        .axi_dmem_arsize        (axi_dmem_arsize),
        .axi_dmem_arburst       (axi_dmem_arburst),
        .axi_dmem_arlock        (axi_dmem_arlock),
        .axi_dmem_arcache       (axi_dmem_arcache),
        .axi_dmem_arprot        (axi_dmem_arprot),
        .axi_dmem_arqos         (axi_dmem_arqos),
        .axi_dmem_arvalid       (axi_dmem_arvalid),
        .axi_dmem_arready       (axi_dmem_arready),
        .axi_dmem_rid           (axi_dmem_rid),
        .axi_dmem_rdata         (axi_dmem_rdata),
        .axi_dmem_rresp         (axi_dmem_rresp),
        .axi_dmem_rlast         (axi_dmem_rlast),
        .axi_dmem_rvalid        (axi_dmem_rvalid),
        .axi_dmem_rready        (axi_dmem_rready)
);

endmodule : vd100_scr1
