// Unit test for aes_engine (OpenTitan AES + DMA) on its own: an APB driver and
// a small AXI memory. Checks COPY, AES (ECB, FIPS-197 vector) and SINK
// (CBC, running value read back through one more block).
//   scripts/engine_tb.sh [masked]
module aes_engine_tb;
  parameter bit Masked = 1'b0;
  localparam int unsigned MemWords = 1024;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        psel = 0, penable = 0, pwrite = 0, pready, pslverr;
  logic [11:0] paddr = 0;
  logic [31:0] pwdata = 0, prdata;
  logic [63:0] ar_addr, aw_addr, r_data, w_data;
  logic [7:0]  ar_len, aw_len;
  logic        ar_valid, ar_ready, r_last, r_valid, r_ready;
  logic        aw_valid, aw_ready, w_last, w_valid, w_ready, b_valid, b_ready, done;

  aes_engine #(.Masked(Masked)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .psel_i(psel), .penable_i(penable), .pwrite_i(pwrite), .paddr_i(paddr), .pwdata_i(pwdata),
    .prdata_o(prdata), .pready_o(pready), .pslverr_o(pslverr),
    .ar_addr_o(ar_addr), .ar_len_o(ar_len), .ar_valid_o(ar_valid), .ar_ready_i(ar_ready),
    .r_data_i(r_data), .r_resp_i(2'b00), .r_last_i(r_last), .r_valid_i(r_valid), .r_ready_o(r_ready),
    .aw_addr_o(aw_addr), .aw_len_o(aw_len), .aw_valid_o(aw_valid), .aw_ready_i(aw_ready),
    .w_data_o(w_data), .w_last_o(w_last), .w_valid_o(w_valid), .w_ready_i(w_ready),
    .b_resp_i(2'b00), .b_valid_i(b_valid), .b_ready_o(b_ready), .done_o(done)
  );

  // AXI memory: one read or write burst at a time, one beat per cycle.
  logic [63:0] mem[MemWords];
  logic [63:0] raddr, waddr;
  logic [8:0]  rcnt;
  logic        rbusy = 0, wbusy = 0, bpend = 0;
  assign ar_ready = !rbusy;
  assign r_valid  = rbusy;
  assign r_data   = mem[raddr[12:3]];
  assign r_last   = rbusy && rcnt == 0;
  assign aw_ready = !wbusy && !bpend;
  assign w_ready  = wbusy;
  assign b_valid  = bpend;
  always @(posedge clk) begin
    if (ar_valid && ar_ready) begin rbusy <= 1; raddr <= ar_addr; rcnt <= ar_len; end
    else if (r_valid && r_ready) begin raddr <= raddr + 8; rcnt <= rcnt - 1; if (r_last) rbusy <= 0; end
    if (aw_valid && aw_ready) begin wbusy <= 1; waddr <= aw_addr; end
    else if (w_valid && w_ready) begin mem[waddr[12:3]] <= w_data; waddr <= waddr + 8; if (w_last) begin wbusy <= 0; bpend <= 1; end end
    if (b_valid && b_ready) bpend <= 0;
  end

  task automatic apb(input logic we, input logic [11:0] addr, input logic [31:0] wd, output logic [31:0] rd);
    @(posedge clk); #1 psel = 1; pwrite = we; paddr = addr; pwdata = wd;
    @(posedge clk); #1 penable = 1;
    do @(posedge clk); while (!pready);
    rd = prdata;
    if (pslverr) $display("APB error at %h", addr);
    #1 psel = 0; penable = 0;
  endtask
  task automatic wr(input logic [11:0] addr, input logic [31:0] d); logic [31:0] x; apb(1, addr, d, x); endtask
  task automatic rdreg(input logic [11:0] addr, output logic [31:0] d); apb(0, addr, 0, d); endtask
  task automatic wait_status(input logic [31:0] bits);
    logic [31:0] s; int n = 0;
    do begin rdreg(12'h084, s); n++; end while ((s & bits) != bits && n < 2000);
    if (n >= 2000) begin $display("TIMEOUT waiting for AES status %h (status %h)", bits, s); $finish; end
  endtask
  task automatic setup(input logic [31:0] ctrl, input logic [127:0] key, input logic [127:0] iv);
    wait_status(32'h1);
    wr(12'h074, ctrl); wr(12'h074, ctrl);
    for (int i = 0; i < 8; i++) begin
      wr(12'h004 + 4*i, i < 4 ? key[32*i+:32] : 0);
      wr(12'h024 + 4*i, 0);
    end
    wait_status(32'h1);                               // a key write starts a PRNG reseed
    for (int i = 0; i < 4; i++) wr(12'h044 + 4*i, iv[32*i+:32]);
    wait_status(32'h11);
  endtask
  task automatic dma(input logic [31:0] src, input logic [31:0] dst, input logic [31:0] len, input logic [1:0] mode);
    logic [31:0] s; int n = 0; longint t0;
    wr(12'h100, src); wr(12'h104, dst); wr(12'h108, len); wr(12'h10c, {29'b0, mode, 1'b1});
    t0 = $time;
    do begin rdreg(12'h110, s); n++; end while (!s[1] && n < 100000);
    if (!s[1]) begin
      $display("TIMEOUT: DMA not done. e=%0d rd=%0d wr=%0d blk_in=%0d blk_out=%0d in_cnt=%0d out_cnt=%0d nb=%0d",
               dut.i_dma.e_q, dut.i_dma.rd_q, dut.i_dma.wr_q, dut.i_dma.blk_in_q, dut.i_dma.blk_out_q,
               dut.i_dma.in_cnt, dut.i_dma.out_cnt, dut.i_dma.nb_cnt_q);
      $finish;
    end
    $display("  DMA mode %0d, %0d bytes: %0d cycles%s", mode, len, ($time - t0) / 10, s[2] ? " ERROR FLAG" : "");
  endtask

  // Byte strings as memory holds them: byte 0 in the low bits.
  localparam logic [127:0] Key = 128'h0f0e0d0c0b0a09080706050403020100;
  localparam logic [127:0] Pt  = 128'hffeeddccbbaa99887766554433221100;
  localparam logic [127:0] Ct  = 128'h5ac5b47080b7cdd830047b6ad8e0c469;

  int errors = 0;
  logic [31:0] w;
  logic [127:0] blk;
  initial begin
    for (int i = 0; i < MemWords; i++) mem[i] = {32'hdead0000 + i, 32'h12340000 + i};
    repeat (5) @(posedge clk); rst_n = 1; repeat (5) @(posedge clk);

    $display("COPY 256 bytes");
    dma(32'h0000, 32'h1000, 256, 2'd0);
    for (int i = 0; i < 32; i++) if (mem[512 + i] !== mem[i]) errors++;

    $display("AES (ECB) 8 blocks of the FIPS-197 plaintext, in place");
    for (int i = 0; i < 8; i++) begin mem[2*i] = Pt[63:0]; mem[2*i+1] = Pt[127:64]; end
    setup(32'h2105, Key, '0);                       // ENC | ECB | AES-128 | PER_64
    dma(32'h0000, 32'h0000, 128, 2'd1);
    for (int i = 0; i < 8; i++) if ({mem[2*i+1], mem[2*i]} !== Ct) begin
      errors++; $display("  block %0d: %h", i, {mem[2*i+1], mem[2*i]});
    end

    $display("SINK (CBC) 4 zero blocks, then one more block by hand");
    for (int i = 0; i < 8; i++) mem[i] = '0;
    setup(32'h2109, Key, '0);                       // CBC
    dma(32'h0000, 32'h0000, 64, 2'd2);
    for (int i = 0; i < 8; i++) if (mem[i] !== '0) errors++;      // SINK must not write
    for (int i = 0; i < 4; i++) wr(12'h054 + 4*i, 0);
    wait_status(32'h8);
    for (int i = 0; i < 4; i++) begin rdreg(12'h064 + 4*i, w); blk[32*i+:32] = w; end
    if (blk !== 128'h0a1357305d36cdf0e3b769d00a55274b) begin errors++; $display("  CBC-MAC wrong: %h", blk); end

    $display("Timing: AES (ECB) 64 blocks, SINK (CBC) 256 blocks, AES (CTR) 256 blocks");
    setup(32'h2105, Key, '0);
    dma(32'h0000, 32'h1000, 1024, 2'd1);
    setup(32'h2109, Key, '0);
    dma(32'h0000, 32'h0000, 4096, 2'd2);
    setup(32'h2141, Key, '0);                       // CTR
    dma(32'h0000, 32'h1000, 4096, 2'd1);

    if (errors == 0) $display("ENGINE TB PASS");
    else             $display("ENGINE TB FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin #50ms; $display("TIMEOUT (global)"); $finish; end
endmodule
