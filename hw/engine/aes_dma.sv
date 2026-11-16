// DMA with an AES streaming mode, for the OpenTitan AES block.
//
// The DMA is an AXI4 master on the system bus (64-bit data). It reads LEN
// bytes from SRC in bursts and, depending on MODE:
//   COPY  writes them unchanged to DST
//   AES   sends them through the AES block, 16 bytes at a time, and writes the
//         AES output to DST (ECB/CBC/CTR, whatever the CPU configured)
//   SINK  sends them through the AES block and drops the output (CBC-MAC: the
//         running tag stays in the AES block's IV register)
// It drives the AES block through its normal TL-UL register interface
// (DATA_IN, DATA_OUT, STATUS), exactly as software would, so the AES block is
// unchanged. The CPU sets key, mode and IV first through the same registers.
// Same idea as the "AES mode" of the Caliptra 2.1 AXI DMA.
//
// Registers (APB, 32-bit):
//   0x000-0x0ff  OpenTitan AES registers (passed through while the DMA is idle)
//   0x100 SRC    0x104 DST    0x108 LEN (bytes, multiple of 16; 8 for COPY)
//   0x10c CTRL   bit 0 start, bits 2:1 mode (0 COPY, 1 AES, 2 SINK)
//   0x110 STATUS bit 0 busy, bit 1 done, bit 2 error
// SRC and DST are 32-bit and must be 8-byte aligned.

module aes_dma #(
  parameter int unsigned MaxBurst  = 4,   // beats per AXI burst (two AES blocks)
  parameter int unsigned FifoDepth = 8    // beats, power of two, >= 2 * MaxBurst
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  // APB configuration port
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [11:0] paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  // TL-UL to the AES block
  output tlul_ot_pkg::tl_h2d_t tl_o,
  input  tlul_ot_pkg::tl_d2h_t tl_i,
  // AXI4 master: size 8 bytes, INCR bursts, ID 0
  output logic [63:0] ar_addr_o,
  output logic [7:0]  ar_len_o,
  output logic        ar_valid_o,
  input  logic        ar_ready_i,
  input  logic [63:0] r_data_i,
  input  logic [1:0]  r_resp_i,
  input  logic        r_last_i,
  input  logic        r_valid_i,
  output logic        r_ready_o,
  output logic [63:0] aw_addr_o,
  output logic [7:0]  aw_len_o,
  output logic        aw_valid_o,
  input  logic        aw_ready_i,
  output logic [63:0] w_data_o,
  output logic        w_last_o,
  output logic        w_valid_o,
  input  logic        w_ready_i,
  input  logic [1:0]  b_resp_i,
  input  logic        b_valid_i,
  output logic        b_ready_o,
  output logic        done_o
);

  localparam int unsigned CntW = $clog2(FifoDepth) + 1;

  typedef enum logic [1:0] {ModeCopy = 2'd0, ModeAes = 2'd1, ModeSink = 2'd2} mode_e;

  // AES register offsets and STATUS bits (aes_reg_pkg).
  localparam logic [7:0] AesDataIn  = 8'h54;
  localparam logic [7:0] AesDataOut = 8'h64;
  localparam logic [7:0] AesStatus  = 8'h84;
  localparam int unsigned StOutputValid = 3;
  localparam int unsigned StInputReady  = 4;

  // -------------------------
  // Registers and APB access
  // -------------------------
  logic [31:0] src_q, dst_q, len_q;
  mode_e       mode_q;
  logic        busy_q, done_q, err_q;

  logic aes_sel, dma_sel, apb_wr, start, aes_mode, finished;
  assign aes_sel  = psel_i & ~paddr_i[8];
  assign dma_sel  = psel_i & paddr_i[8];
  assign apb_wr   = dma_sel & penable_i & pwrite_i;
  assign start    = apb_wr & (paddr_i[7:0] == 8'h0c) & pwdata_i[0] & ~busy_q;
  assign aes_mode = busy_q & (mode_q != ModeCopy);  // the DMA owns the AES block

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      src_q  <= '0;
      dst_q  <= '0;
      len_q  <= '0;
      mode_q <= ModeCopy;
      busy_q <= 1'b0;
      done_q <= 1'b0;
      err_q  <= 1'b0;
    end else begin
      if (apb_wr && !busy_q) begin
        unique case (paddr_i[7:0])
          8'h00:   src_q  <= pwdata_i;
          8'h04:   dst_q  <= pwdata_i;
          8'h08:   len_q  <= pwdata_i;
          8'h0c:   mode_q <= mode_e'(pwdata_i[2:1]);
          default: ;
        endcase
      end
      if (start) begin
        busy_q <= 1'b1;
        done_q <= 1'b0;
        err_q  <= 1'b0;
      end else if (finished) begin
        busy_q <= 1'b0;
        done_q <= 1'b1;
      end
      if (busy_q && ((r_valid_i && r_ready_o && r_resp_i[1]) || (b_valid_i && b_ready_o && b_resp_i[1])
                     || (aes_mode && tl_i.d_valid && tl_i.d_error))) begin
        err_q <= 1'b1;
      end
    end
  end

  assign done_o = done_q;

  logic [31:0] dma_rdata;
  always_comb begin
    unique case (paddr_i[7:0])
      8'h00:   dma_rdata = src_q;
      8'h04:   dma_rdata = dst_q;
      8'h08:   dma_rdata = len_q;
      8'h0c:   dma_rdata = {29'b0, mode_q, 1'b0};
      8'h10:   dma_rdata = {29'b0, err_q, done_q, busy_q};
      default: dma_rdata = '0;
    endcase
  end

  // -------------------------
  // TL-UL to the AES block
  // -------------------------
  // One request at a time: the AES register interface answers one cycle after
  // it accepts a request, so every access takes two cycles.
  logic        t_req, t_we, t_phase_q, t_done;
  logic [7:0]  t_addr;
  logic [31:0] t_wdata;

  tlul_ot_pkg::tl_h2d_t tl_pre;
  always_comb begin
    tl_pre          = '0;
    tl_pre.a_size   = 2'h2;
    tl_pre.a_mask   = 4'hf;
    tl_pre.a_user   = tlul_ot_pkg::TL_A_USER_DEFAULT;
    tl_pre.d_ready  = 1'b1;
    if (aes_mode) begin
      tl_pre.a_valid   = t_req;
      tl_pre.a_opcode  = t_we ? tlul_ot_pkg::PutFullData : tlul_ot_pkg::Get;
      tl_pre.a_address = {24'b0, t_addr};
      tl_pre.a_data    = t_wdata;
    end else begin
      tl_pre.a_valid   = aes_sel & penable_i;
      tl_pre.a_opcode  = pwrite_i ? tlul_ot_pkg::PutFullData : tlul_ot_pkg::Get;
      tl_pre.a_address = {24'b0, paddr_i[7:2], 2'b00};
      tl_pre.a_data    = pwdata_i;
    end
  end

  // The AES block checks an integrity code on every request.
  tlul_cmd_intg_gen i_intg_gen (
    .tl_i ( tl_pre ),
    .tl_o ( tl_o   )
  );

  always_comb begin
    if (dma_sel) begin
      prdata_o  = dma_rdata;
      pready_o  = 1'b1;
      pslverr_o = 1'b0;
    end else if (aes_mode) begin   // AES registers are busy with the DMA
      prdata_o  = '0;
      pready_o  = 1'b1;
      pslverr_o = 1'b1;
    end else begin
      prdata_o  = tl_i.d_data;
      pready_o  = tl_i.d_valid;
      pslverr_o = tl_i.d_error;
    end
  end

  // -------------------------
  // FIFOs
  // -------------------------
  logic            in_push, in_pop, out_push, out_pop;
  logic [63:0]     in_rdata, out_wdata, out_rdata;
  logic [CntW-1:0] in_cnt, out_cnt;
  logic            in_empty, out_full;
  assign in_empty = (in_cnt == '0);
  assign out_full = (out_cnt == CntW'(FifoDepth));

  aes_dma_fifo #(.Depth(FifoDepth)) i_in_fifo (
    .clk_i, .rst_ni, .clr_i(start),
    .push_i(in_push), .data_i(r_data_i), .pop_i(in_pop), .data_o(in_rdata), .cnt_o(in_cnt)
  );
  aes_dma_fifo #(.Depth(FifoDepth)) i_out_fifo (
    .clk_i, .rst_ni, .clr_i(start),
    .push_i(out_push), .data_i(out_wdata), .pop_i(out_pop), .data_o(out_rdata), .cnt_o(out_cnt)
  );

  // Beats until the next 4 KB boundary (a burst must not cross it).
  function automatic logic [9:0] to_4k(input logic [31:0] addr);
    return 10'((13'd4096 - {1'b0, addr[11:0]}) >> 3);
  endfunction

  function automatic logic [CntW-1:0] burst_len(input logic [28:0] rem, input logic [31:0] addr);
    logic [28:0] n;
    n = rem;
    if (n > 29'(MaxBurst))    n = 29'(MaxBurst);
    if (n > 29'(to_4k(addr))) n = 29'(to_4k(addr));
    return CntW'(n);
  endfunction

  // -------------------------
  // AXI read side
  // -------------------------
  typedef enum logic [1:0] {RdIdle, RdAddr, RdData} rd_state_e;
  rd_state_e       rd_q;
  logic [31:0]     rd_addr_q;
  logic [28:0]     rd_rem_q;      // beats still to request
  logic [CntW-1:0] rd_burst_q, rd_burst;

  assign rd_burst   = burst_len(rd_rem_q, rd_addr_q);
  assign ar_addr_o  = {32'b0, rd_addr_q};
  assign ar_len_o   = 8'(rd_burst_q - 1'b1);
  assign ar_valid_o = (rd_q == RdAddr);
  assign r_ready_o  = (rd_q == RdData);   // space was reserved before the request
  assign in_push    = r_valid_i & r_ready_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_q       <= RdIdle;
      rd_addr_q  <= '0;
      rd_rem_q   <= '0;
      rd_burst_q <= '0;
    end else if (start) begin
      rd_q      <= RdIdle;
      rd_addr_q <= src_q;
      rd_rem_q  <= len_q[31:3];
    end else begin
      unique case (rd_q)
        RdIdle: if (busy_q && rd_rem_q != '0 && (CntW'(FifoDepth) - in_cnt) >= rd_burst) begin
          rd_burst_q <= rd_burst;
          rd_q       <= RdAddr;
        end
        RdAddr: if (ar_ready_i) rd_q <= RdData;
        RdData: if (r_valid_i && r_last_i) begin
          rd_addr_q <= rd_addr_q + {rd_burst_q, 3'b000};
          rd_rem_q  <= rd_rem_q - 29'(rd_burst_q);
          rd_q      <= RdIdle;
        end
        default: rd_q <= RdIdle;
      endcase
    end
  end

  // -------------------------
  // AXI write side
  // -------------------------
  typedef enum logic [1:0] {WrIdle, WrAddr, WrData, WrResp} wr_state_e;
  wr_state_e       wr_q;
  logic [31:0]     wr_addr_q;
  logic [28:0]     wr_rem_q;      // beats still to write
  logic [CntW-1:0] wr_burst_q, wr_burst, wr_cnt_q;

  assign wr_burst   = burst_len(wr_rem_q, wr_addr_q);
  assign aw_addr_o  = {32'b0, wr_addr_q};
  assign aw_len_o   = 8'(wr_burst_q - 1'b1);
  assign aw_valid_o = (wr_q == WrAddr);
  assign w_valid_o  = (wr_q == WrData);   // the whole burst is in the FIFO already
  assign w_data_o   = out_rdata;
  assign w_last_o   = (wr_cnt_q == wr_burst_q - 1'b1);
  assign out_pop    = w_valid_o & w_ready_i;
  assign b_ready_o  = (wr_q == WrResp);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_q       <= WrIdle;
      wr_addr_q  <= '0;
      wr_rem_q   <= '0;
      wr_burst_q <= '0;
      wr_cnt_q   <= '0;
    end else if (start) begin
      wr_q      <= WrIdle;
      wr_addr_q <= dst_q;
      wr_rem_q  <= (mode_e'(pwdata_i[2:1]) == ModeSink) ? '0 : len_q[31:3];
    end else begin
      unique case (wr_q)
        WrIdle: if (busy_q && wr_rem_q != '0 && out_cnt >= wr_burst) begin
          wr_burst_q <= wr_burst;
          wr_cnt_q   <= '0;
          wr_q       <= WrAddr;
        end
        WrAddr: if (aw_ready_i) wr_q <= WrData;
        WrData: if (w_ready_i) begin
          wr_cnt_q <= wr_cnt_q + 1'b1;
          if (w_last_o) wr_q <= WrResp;
        end
        WrResp: if (b_valid_i) begin
          wr_addr_q <= wr_addr_q + {wr_burst_q, 3'b000};
          wr_rem_q  <= wr_rem_q - 29'(wr_burst_q);
          wr_q      <= WrIdle;
        end
        default: wr_q <= WrIdle;
      endcase
    end
  end

  // -------------------------
  // Between the FIFOs
  // -------------------------
  // COPY: move beats straight across. AES/SINK: the block sequencer below
  // takes two beats (one AES block) from the input FIFO into nb_q, and puts
  // each AES output block from ob_q into the output FIFO.
  logic         copy_move, nb_pop, nb_clear, ob_push;
  logic [127:0] nb_q, ob_q;
  logic [1:0]   nb_cnt_q;
  logic         ob_valid_q, ob_idx_q, ob_set;
  logic         nb_full;

  assign copy_move = busy_q & (mode_q == ModeCopy) & ~in_empty & ~out_full;
  assign nb_full   = (nb_cnt_q == 2'd2);
  assign nb_pop    = aes_mode & ~nb_full & ~in_empty;
  assign ob_push   = ob_valid_q & ~out_full;
  assign in_pop    = copy_move | nb_pop;
  assign out_push  = copy_move | ob_push;
  assign out_wdata = copy_move ? in_rdata : ob_q[64*ob_idx_q+:64];

  // Block sequencer: follows "Block Operation" in the AES programmer's guide.
  // Block i+1 is written while block i is being encrypted.
  typedef enum logic [2:0] {EIdle, EWrite, EPollIn, EPollOut, ERead} e_state_e;
  e_state_e    e_q;
  logic [1:0]  word_q;
  logic [27:0] blk_total_q, blk_in_q, blk_out_q;
  logic        e_done_q;

  always_comb begin
    t_req   = 1'b0;
    t_we    = 1'b0;
    t_addr  = AesStatus;
    t_wdata = nb_q[32*word_q+:32];
    unique case (e_q)
      EWrite: begin
        t_req  = nb_full & ~t_phase_q;
        t_we   = 1'b1;
        t_addr = AesDataIn + {4'b0, word_q, 2'b00};
      end
      EPollIn, EPollOut: t_req = ~t_phase_q;
      ERead: begin
        t_req  = ~ob_valid_q & ~t_phase_q;
        t_addr = AesDataOut + {4'b0, word_q, 2'b00};
      end
      default: ;
    endcase
  end

  assign t_done   = aes_mode & t_phase_q & tl_i.d_valid;
  assign nb_clear = t_done & (e_q == EWrite) & (word_q == 2'd3);
  assign ob_set   = t_done & (e_q == ERead) & (word_q == 2'd3) & (mode_q == ModeAes);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      e_q         <= EIdle;
      t_phase_q   <= 1'b0;
      word_q      <= '0;
      blk_total_q <= '0;
      blk_in_q    <= '0;
      blk_out_q   <= '0;
      e_done_q    <= 1'b0;
      nb_q        <= '0;
      nb_cnt_q    <= '0;
      ob_q        <= '0;
      ob_valid_q  <= 1'b0;
      ob_idx_q    <= 1'b0;
    end else if (start) begin
      e_q         <= (mode_e'(pwdata_i[2:1]) != ModeCopy && len_q[31:4] != '0) ? EWrite : EIdle;
      e_done_q    <= (len_q[31:4] == '0);
      t_phase_q   <= 1'b0;
      word_q      <= '0;
      blk_total_q <= len_q[31:4];
      blk_in_q    <= '0;
      blk_out_q   <= '0;
      nb_cnt_q    <= '0;
      ob_valid_q  <= 1'b0;
      ob_idx_q    <= 1'b0;
    end else begin
      // TL-UL request / response phase
      if (aes_mode && t_req && tl_i.a_ready) t_phase_q <= 1'b1;
      else if (t_done)                       t_phase_q <= 1'b0;

      // next input block
      if (nb_pop) begin
        nb_q[64*nb_cnt_q[0]+:64] <= in_rdata;
        nb_cnt_q                 <= nb_cnt_q + 2'd1;
      end else if (nb_clear) begin
        nb_cnt_q <= '0;
      end

      // output block to the FIFO, low half first
      if (ob_set) begin
        ob_valid_q <= 1'b1;
        ob_idx_q   <= 1'b0;
      end else if (ob_push) begin
        ob_idx_q <= 1'b1;
        if (ob_idx_q) ob_valid_q <= 1'b0;
      end

      if (t_done) begin
        unique case (e_q)
          EWrite: begin
            word_q <= word_q + 2'd1;
            if (word_q == 2'd3) begin
              blk_in_q <= blk_in_q + 28'd1;
              // After the first block, wait until it has been taken before
              // writing the second one.
              e_q <= (blk_in_q == '0 && blk_total_q > 28'd1) ? EPollIn : EPollOut;
            end
          end
          EPollIn:  if (tl_i.d_data[StInputReady])  e_q <= EWrite;
          EPollOut: if (tl_i.d_data[StOutputValid]) e_q <= ERead;
          ERead: begin
            ob_q[32*word_q+:32] <= tl_i.d_data;
            word_q              <= word_q + 2'd1;
            if (word_q == 2'd3) begin
              blk_out_q <= blk_out_q + 28'd1;
              if (blk_in_q < blk_total_q)                e_q <= EWrite;
              else if (blk_out_q + 28'd1 < blk_total_q)  e_q <= EPollOut;
              else begin
                e_q      <= EIdle;
                e_done_q <= 1'b1;
              end
            end
          end
          default: ;
        endcase
      end
    end
  end

  // Finished when everything has been read and written (and, for SINK, all
  // blocks have gone through the AES block).
  assign finished = busy_q & (rd_q == RdIdle) & (rd_rem_q == '0) & (wr_q == WrIdle) & (wr_rem_q == '0)
                    & ((mode_q == ModeCopy) | e_done_q) & ~ob_valid_q;

endmodule

// Small synchronous FIFO with a fill counter. data_o is the oldest entry.
module aes_dma_fifo #(
  parameter int unsigned Depth = 32,
  parameter int unsigned Width = 64
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clr_i,
  input  logic                   push_i,
  input  logic [Width-1:0]       data_i,
  input  logic                   pop_i,
  output logic [Width-1:0]       data_o,
  output logic [$clog2(Depth):0] cnt_o
);
  localparam int unsigned Aw = $clog2(Depth);
  logic [Width-1:0] mem_q[Depth];
  logic [Aw-1:0]    rptr_q, wptr_q;
  logic [Aw:0]      cnt_q;

  assign data_o = mem_q[rptr_q];
  assign cnt_o  = cnt_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rptr_q <= '0;
      wptr_q <= '0;
      cnt_q  <= '0;
    end else if (clr_i) begin
      rptr_q <= '0;
      wptr_q <= '0;
      cnt_q  <= '0;
    end else begin
      if (push_i) wptr_q <= wptr_q + 1'b1;
      if (pop_i)  rptr_q <= rptr_q + 1'b1;
      cnt_q <= cnt_q + (Aw+1)'(push_i) - (Aw+1)'(pop_i);
    end
  end

  always_ff @(posedge clk_i) begin
    if (push_i) mem_q[wptr_q] <= data_i;
  end
endmodule
