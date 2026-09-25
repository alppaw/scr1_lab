// Run with SCR1_CFG_RV32IMC_MAX or the default custom configuration.
`include "scr1_arch_description.svh"
`include "scr1_memif.svh"
`include "scr1_riscv_isa_decoding.svh"
`ifdef SCR1_DBG_EN
`include "scr1_hdu.svh"
`endif

module scr1_branch_predictor_tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic imem_req;
    type_scr1_mem_cmd_e imem_cmd;
    logic [`SCR1_IMEM_AWIDTH-1:0] imem_addr;
    logic imem_ack;
    logic [`SCR1_IMEM_DWIDTH-1:0] imem_data;
    type_scr1_mem_resp_e imem_resp;
    logic [`SCR1_IMEM_AWIDTH-1:0] imem_resp_addr;
    logic [31:0] rom [0:15];
    integer early_predictions = 0;
    integer correct_predictions = 0;
    integer backward_recovery = 0;
    integer compressed_recovery = 0;
    integer forward_recovery = 0;
    integer wrong_path_retired = 0;
    integer cycles = 0;

    assign imem_data = (imem_resp_addr >= 32'h200 && imem_resp_addr < 32'h240)
                     ? rom[(imem_resp_addr - 32'h200) >> 2] : 32'h00000013;

`ifdef SCR1_BP_PERF
    // Accept a request each cycle and respond in order two cycles later.
    logic [1:0] imem_valid;
    logic [`SCR1_IMEM_AWIDTH-1:0] imem_addr_pipe [0:1];
    assign imem_ack = imem_req;
    assign imem_resp = imem_valid[1] ? SCR1_MEM_RESP_RDY_OK : SCR1_MEM_RESP_NOTRDY;
    assign imem_resp_addr = imem_addr_pipe[1];
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            imem_valid <= '0;
            imem_addr_pipe[0] <= '0;
            imem_addr_pipe[1] <= '0;
        end else begin
            imem_valid[0] <= imem_ack;
            imem_valid[1] <= imem_valid[0];
            if (imem_ack) imem_addr_pipe[0] <= imem_addr;
            imem_addr_pipe[1] <= imem_addr_pipe[0];
        end
    end
`else
    logic imem_pending = 1'b0;
    logic [`SCR1_IMEM_AWIDTH-1:0] imem_addr_saved;
    assign imem_ack = imem_req & ~imem_pending;
    assign imem_resp = imem_pending ? SCR1_MEM_RESP_RDY_OK : SCR1_MEM_RESP_NOTRDY;
    assign imem_resp_addr = imem_addr_saved;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            imem_pending <= 1'b0;
            imem_addr_saved <= '0;
        end else begin
            imem_pending <= imem_ack;
            if (imem_ack) imem_addr_saved <= imem_addr;
        end
    end
`endif

    scr1_pipe_top dut (
        .pipe_rst_n(rst_n), .clk(clk),
`ifdef SCR1_DBG_EN
        .dbg_rst_n(rst_n), .pipe2hdu_rdc_qlfy_i(1'b1),
        .dbg_en(1'b0), .dm2pipe_active_i(1'b0),
        .dm2pipe_cmd_req_i(1'b0), .dm2pipe_cmd_i(SCR1_HDU_DBGSTATE_RUN),
        .dm2pipe_pbuf_instr_i('0),
        .dm2pipe_dreg_resp_i(1'b0), .dm2pipe_dreg_fail_i(1'b0),
        .dm2pipe_dreg_rdata_i('0),
`endif
        .pipe2imem_req_o(imem_req), .pipe2imem_cmd_o(imem_cmd),
        .pipe2imem_addr_o(imem_addr),
        .imem2pipe_req_ack_i(imem_ack), .imem2pipe_rdata_i(imem_data),
        .imem2pipe_resp_i(imem_resp),
        .dmem2pipe_req_ack_i(1'b0), .dmem2pipe_rdata_i('0),
        .dmem2pipe_resp_i(SCR1_MEM_RESP_NOTRDY),
`ifdef SCR1_IPIC_EN
        .soc2pipe_irq_lines_i('0),
`else
        .soc2pipe_irq_ext_i(1'b0),
`endif
        .soc2pipe_irq_soft_i(1'b0), .soc2pipe_irq_mtimer_i(1'b0),
        .soc2pipe_mtimer_val_i('0), .soc2pipe_fuse_mhartid_i('0)
`ifdef SCR1_CLKCTRL_EN
        , .clkctl2pipe_clk_alw_on_i(clk), .clkctl2pipe_clk_dbgc_i(clk),
        .clkctl2pipe_clk_en_i(1'b1)
`endif
    );

    initial begin
        foreach (rom[i]) rom[i] = 32'h00000013; // ADDI x0, x0, 0
`ifdef SCR1_BP_PERF
        rom[0] = 32'h04000093; // ADDI x1, x0, 64
`else
        rom[0] = 32'h00300093; // ADDI x1, x0, 3
`endif
        rom[1] = 32'hfff08093; // ADDI x1, x1, -1
        rom[2] = 32'hfe009ee3; // BNE x1, x0, -4 (taken twice, then not taken)
        rom[3] = 32'h00000463; // BEQ x0, x0, +8 (forward, taken)
        rom[4] = 32'h06300113; // ADDI x2, x0, 99 (wrong path)
        rom[5] = 32'h00700193; // ADDI x3, x0, 7
        rom[6] = 32'h00200413; // ADDI x8, x0, 2
        rom[7] = 32'hfff40413; // ADDI x8, x8, -1
        rom[8] = 32'h0001fc75; // C.BNEZ x8, -4; C.NOP
        rom[9] = 32'h00500493; // ADDI x9, x0, 5
        rom[10] = 32'h0000006f; // JAL x0, 0
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (imem_ack && imem_cmd != SCR1_MEM_CMD_RD)
                $fatal(1, "unexpected instruction memory write");
            if (dut.i_pipe_ifu.bp_req_taken && imem_ack)
                early_predictions = early_predictions + 1;
            if (dut.instret && dut.curr_pc == 32'h208 &&
                dut.i_pipe_exu.branch_predicted && dut.i_pipe_exu.branch_taken)
                correct_predictions = correct_predictions + 1;
            if (dut.instret && dut.curr_pc == 32'h210)
                wrong_path_retired = wrong_path_retired + 1;
            if (dut.new_pc_req && dut.i_pipe_exu.exu_queue_vd &&
                dut.i_pipe_exu.exu_queue.branch_req) begin
                if (dut.curr_pc == 32'h208) backward_recovery = backward_recovery + 1;
                if (dut.curr_pc == 32'h220) compressed_recovery = compressed_recovery + 1;
                if (dut.curr_pc == 32'h20c) forward_recovery = forward_recovery + 1;
            end
            if (dut.instret && dut.curr_pc == 32'h224) begin
                #1;
                if (dut.i_pipe_mprf.mprf_int[1] !== 32'd0 ||
                    dut.i_pipe_mprf.mprf_int[3] !== 32'd7 ||
                    dut.i_pipe_mprf.mprf_int[8] !== 32'd0 ||
                    dut.i_pipe_mprf.mprf_int[9] !== 32'd5 ||
`ifndef SCR1_BP_DISABLE
                    early_predictions == 0 || correct_predictions == 0 ||
`endif
                    backward_recovery < 1 ||
                    compressed_recovery < 1 || forward_recovery != 1 ||
                    wrong_path_retired != 0)
                    $fatal(1, "branch test failed: x1=%h x3=%h x8=%h x9=%h early=%0d correct=%0d backward=%0d compressed=%0d forward=%0d wrong=%0d",
                           dut.i_pipe_mprf.mprf_int[1], dut.i_pipe_mprf.mprf_int[3],
                           dut.i_pipe_mprf.mprf_int[8], dut.i_pipe_mprf.mprf_int[9],
                           early_predictions, correct_predictions,
                           backward_recovery, compressed_recovery, forward_recovery,
                           wrong_path_retired);
                $display("PASS: cycles=%0d early=%0d correct=%0d backward_recovery=%0d compressed=%0d forward=%0d",
                         cycles, early_predictions, correct_predictions,
                         backward_recovery, compressed_recovery, forward_recovery);
                $finish;
            end
            if (cycles > 1000) $fatal(1, "timeout waiting for branch program");
        end
    end
endmodule
