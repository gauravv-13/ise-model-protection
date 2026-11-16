// Option B: OpenTitan AES block + DMA (aes_dma.sv). This is the unit that is
// synthesized for area: an APB configuration port and an AXI4 master.
//
// Masked = 1: OpenTitan default (first-order masking, DOM S-box), as in
//             Carfield's security island. 56 cycles per block.
// Masked = 0: no masking, Canright S-box. 12 cycles per block. Like for like
//             with the Zkne instructions, which are not masked either.
// The AES module is called ot_aes here (renamed by gen_flist.py; CVA6 already
// has a module called aes).
//
// Tie-offs, not real hardware: a stand-in entropy source for the masking PRNG,
// no key manager, no life-cycle escalation, alerts ignored.
module aes_engine #(
  parameter bit Masked = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [11:0] paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
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

  tlul_ot_pkg::tl_h2d_t tl_h2d;
  tlul_ot_pkg::tl_d2h_t tl_d2h;

  aes_dma i_dma (
    .tl_o ( tl_h2d ),
    .tl_i ( tl_d2h ),
    .*
  );

  // Entropy stand-in: the AES block asks for 32-bit words to reseed its PRNGs.
  // Answer with LFSR words: fine for timing and area, not a real entropy
  // source. One word per 4 cycles of request; the word is held 2 cycles before
  // and 1 after the ack, as prim_sync_reqack_data expects.
  edn_pkg::edn_req_t edn_req;
  edn_pkg::edn_rsp_t edn_rsp;
  logic [31:0]       lfsr_q;
  logic [1:0]        cnt_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      lfsr_q <= 32'h1;
      cnt_q  <= '0;
    end else if (edn_req.edn_req) begin
      cnt_q <= cnt_q + 2'd1;
      if (cnt_q == 2'd3) lfsr_q <= {lfsr_q[30:0], lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
    end
  end

  assign edn_rsp = '{edn_ack: edn_req.edn_req && cnt_q == 2'd2, edn_fips: 1'b0, edn_bus: lfsr_q};

  prim_alert_pkg::alert_rx_t [aes_reg_pkg::NumAlerts-1:0] alert_rx;
  assign alert_rx = {aes_reg_pkg::NumAlerts{prim_alert_pkg::ALERT_RX_DEFAULT}};

  ot_aes #(
    .SecMasking  ( Masked ),
    .SecSBoxImpl ( Masked ? ot_aes_pkg::SBoxImplDom : ot_aes_pkg::SBoxImplCanright )
  ) i_aes (
    .clk_i,
    .rst_ni,
    .rst_shadowed_ni  ( rst_ni                         ),
    .idle_o           (                                ),
    .lc_escalate_en_i ( lc_ctrl_pkg::Off               ),
    .clk_edn_i        ( clk_i                          ),
    .rst_edn_ni       ( rst_ni                         ),
    .edn_o            ( edn_req                        ),
    .edn_i            ( edn_rsp                        ),
    .keymgr_key_i     ( keymgr_pkg::HW_KEY_REQ_DEFAULT ),
    .tl_i             ( tl_h2d                         ),
    .tl_o             ( tl_d2h                         ),
    .alert_rx_i       ( alert_rx                       ),
    .alert_tx_o       (                                )
  );

endmodule

// Synthesis tops (no parameter override needed).
module aes_engine_unmasked (
  input  logic clk_i, input logic rst_ni,
  input  logic psel_i, input logic penable_i, input logic pwrite_i,
  input  logic [11:0] paddr_i, input logic [31:0] pwdata_i,
  output logic [31:0] prdata_o, output logic pready_o, output logic pslverr_o,
  output logic [63:0] ar_addr_o, output logic [7:0] ar_len_o, output logic ar_valid_o, input logic ar_ready_i,
  input  logic [63:0] r_data_i, input logic [1:0] r_resp_i, input logic r_last_i, input logic r_valid_i,
  output logic r_ready_o,
  output logic [63:0] aw_addr_o, output logic [7:0] aw_len_o, output logic aw_valid_o, input logic aw_ready_i,
  output logic [63:0] w_data_o, output logic w_last_o, output logic w_valid_o, input logic w_ready_i,
  input  logic [1:0] b_resp_i, input logic b_valid_i, output logic b_ready_o, output logic done_o
);
  aes_engine #(.Masked(1'b0)) i_engine (.*);
endmodule

module aes_engine_masked (
  input  logic clk_i, input logic rst_ni,
  input  logic psel_i, input logic penable_i, input logic pwrite_i,
  input  logic [11:0] paddr_i, input logic [31:0] pwdata_i,
  output logic [31:0] prdata_o, output logic pready_o, output logic pslverr_o,
  output logic [63:0] ar_addr_o, output logic [7:0] ar_len_o, output logic ar_valid_o, input logic ar_ready_i,
  input  logic [63:0] r_data_i, input logic [1:0] r_resp_i, input logic r_last_i, input logic r_valid_i,
  output logic r_ready_o,
  output logic [63:0] aw_addr_o, output logic [7:0] aw_len_o, output logic aw_valid_o, input logic aw_ready_i,
  output logic [63:0] w_data_o, output logic w_last_o, output logic w_valid_o, input logic w_ready_i,
  input  logic [1:0] b_resp_i, input logic b_valid_i, output logic b_ready_o, output logic done_o
);
  aes_engine #(.Masked(1'b1)) i_engine (.*);
endmodule
