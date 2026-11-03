// OpenTitan AES as a memory-mapped peripheral of the CVA6 test harness.
//
//   CVA6 --AXI--> axi2apb_64_32 --APB--> (this file) --TL-UL--> OpenTitan aes
//
// The AXI-to-APB bridge is the one the harness already uses for the UART and
// PLIC, so CVA6 reaches the AES registers the way it reaches any peripheral.
// AES is kept at its OpenTitan defaults (first-order masking, DOM S-box), as
// in Carfield's security island. Module renamed ot_aes by gen_flist.py (CVA6
// already has a module called aes).
//
// Not real hardware here, only tie-offs: a stand-in entropy source (EDN) for
// the masking PRNG, no key manager, no life-cycle escalation, alerts ignored.

module aes_periph #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 64,
  parameter int unsigned AxiIdWidth   = 4,
  parameter int unsigned AxiUserWidth = 1
) (
  input  logic  clk_i,
  input  logic  rst_ni,
  AXI_BUS.Slave axi
);

  // ---------------
  // AXI -> APB
  // ---------------
  logic        penable, pwrite, psel, pready, pslverr;
  logic [31:0] paddr, pwdata, prdata;

  axi2apb_64_32 #(
    .AXI4_ADDRESS_WIDTH ( AxiAddrWidth ),
    .AXI4_RDATA_WIDTH   ( AxiDataWidth ),
    .AXI4_WDATA_WIDTH   ( AxiDataWidth ),
    .AXI4_ID_WIDTH      ( AxiIdWidth   ),
    .AXI4_USER_WIDTH    ( AxiUserWidth ),
    .BUFF_DEPTH_SLAVE   ( 2            ),
    .APB_ADDR_WIDTH     ( 32           )
  ) i_axi2apb (
    .ACLK       ( clk_i          ),
    .ARESETn    ( rst_ni         ),
    .test_en_i  ( 1'b0           ),
    .AWID_i    ( axi.aw_id      ),
    .AWADDR_i  ( axi.aw_addr    ),
    .AWLEN_i   ( axi.aw_len     ),
    .AWSIZE_i  ( axi.aw_size    ),
    .AWBURST_i ( axi.aw_burst   ),
    .AWLOCK_i  ( axi.aw_lock    ),
    .AWCACHE_i ( axi.aw_cache   ),
    .AWPROT_i  ( axi.aw_prot    ),
    .AWREGION_i( axi.aw_region  ),
    .AWUSER_i  ( axi.aw_user    ),
    .AWQOS_i   ( axi.aw_qos     ),
    .AWVALID_i ( axi.aw_valid   ),
    .AWREADY_o ( axi.aw_ready   ),
    .WDATA_i   ( axi.w_data     ),
    .WSTRB_i   ( axi.w_strb     ),
    .WLAST_i   ( axi.w_last     ),
    .WUSER_i   ( axi.w_user     ),
    .WVALID_i  ( axi.w_valid    ),
    .WREADY_o  ( axi.w_ready    ),
    .BID_o     ( axi.b_id       ),
    .BRESP_o   ( axi.b_resp     ),
    .BVALID_o  ( axi.b_valid    ),
    .BUSER_o   ( axi.b_user     ),
    .BREADY_i  ( axi.b_ready    ),
    .ARID_i    ( axi.ar_id      ),
    .ARADDR_i  ( axi.ar_addr    ),
    .ARLEN_i   ( axi.ar_len     ),
    .ARSIZE_i  ( axi.ar_size    ),
    .ARBURST_i ( axi.ar_burst   ),
    .ARLOCK_i  ( axi.ar_lock    ),
    .ARCACHE_i ( axi.ar_cache   ),
    .ARPROT_i  ( axi.ar_prot    ),
    .ARREGION_i( axi.ar_region  ),
    .ARUSER_i  ( axi.ar_user    ),
    .ARQOS_i   ( axi.ar_qos     ),
    .ARVALID_i ( axi.ar_valid   ),
    .ARREADY_o ( axi.ar_ready   ),
    .RID_o     ( axi.r_id       ),
    .RDATA_o   ( axi.r_data     ),
    .RRESP_o   ( axi.r_resp     ),
    .RLAST_o   ( axi.r_last     ),
    .RUSER_o   ( axi.r_user     ),
    .RVALID_o  ( axi.r_valid    ),
    .RREADY_i  ( axi.r_ready    ),
    .PENABLE    ( penable        ),
    .PWRITE     ( pwrite         ),
    .PADDR      ( paddr          ),
    .PSEL       ( psel           ),
    .PWDATA     ( pwdata         ),
    .PRDATA     ( prdata         ),
    .PREADY     ( pready         ),
    .PSLVERR    ( pslverr        )
  );

  // ---------------
  // APB -> TL-UL
  // ---------------
  // Same as register_interface's apb_to_reg + reg_to_tlul (Carfield uses the
  // latter for its watchdog): one 32-bit access at a time, held until d_valid.
  tlul_ot_pkg::tl_h2d_t tl_h2d, tl_h2d_intg;
  tlul_ot_pkg::tl_d2h_t tl_d2h;

  always_comb begin
    tl_h2d           = '0;
    tl_h2d.a_valid   = psel & penable;
    tl_h2d.a_opcode  = pwrite ? tlul_ot_pkg::PutFullData : tlul_ot_pkg::Get;
    tl_h2d.a_size    = 2'h2;
    tl_h2d.a_address = {paddr[31:2], 2'b00};
    tl_h2d.a_mask    = 4'hf;
    tl_h2d.a_data    = pwdata;
    tl_h2d.a_user    = tlul_ot_pkg::TL_A_USER_DEFAULT;
    tl_h2d.d_ready   = 1'b1;
  end

  // AES checks an error code on every request, so add it here.
  tlul_cmd_intg_gen i_intg_gen (
    .tl_i ( tl_h2d      ),
    .tl_o ( tl_h2d_intg )
  );

  assign pready  = tl_d2h.d_valid;
  assign prdata  = tl_d2h.d_data;
  assign pslverr = tl_d2h.d_error;

  // ---------------
  // Entropy stand-in
  // ---------------
  // AES asks the EDN for 32-bit words to reseed its masking PRNG. Answer with
  // LFSR words: fine for timing, not a real entropy source. One word per 4
  // cycles of request; the word is held 2 cycles before and 1 after the ack,
  // as prim_sync_reqack_data's assertions require. A real EDN is slower.
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

  // ---------------
  // OpenTitan AES
  // ---------------
  prim_alert_pkg::alert_rx_t [aes_reg_pkg::NumAlerts-1:0] alert_rx;
  assign alert_rx = {aes_reg_pkg::NumAlerts{prim_alert_pkg::ALERT_RX_DEFAULT}};

  ot_aes i_aes (
    .clk_i            ( clk_i                            ),
    .rst_ni           ( rst_ni                           ),
    .rst_shadowed_ni  ( rst_ni                           ),
    .idle_o           (                                  ),
    .lc_escalate_en_i ( lc_ctrl_pkg::Off                 ),
    .clk_edn_i        ( clk_i                            ),
    .rst_edn_ni       ( rst_ni                           ),
    .edn_o            ( edn_req                          ),
    .edn_i            ( edn_rsp                          ),
    .keymgr_key_i     ( keymgr_pkg::HW_KEY_REQ_DEFAULT   ),
    .tl_i             ( tl_h2d_intg                      ),
    .tl_o             ( tl_d2h                           ),
    .alert_rx_i       ( alert_rx                         ),
    .alert_tx_o       (                                  )
  );

endmodule
