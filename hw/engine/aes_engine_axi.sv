// Two AES engines (aes_engine.sv) in the CVA6 test harness, behind one
// AXI-to-APB bridge (the bridge the harness already uses for UART and PLIC):
//
//   0x4000_0000  unmasked engine    0x4000_0800  masked engine
//   (+0x000 AES registers, +0x100 DMA registers)
//
// Each engine has its own AXI master port on the crossbar. Simulation only:
// one build gives both variants; software picks one by address.
module aes_engine_axi #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 64,
  parameter int unsigned AxiIdWidth   = 4,   // at the configuration port
  parameter int unsigned AxiUserWidth = 1
) (
  input  logic   clk_i,
  input  logic   rst_ni,
  AXI_BUS.Slave  cfg,
  AXI_BUS.Master dma_unmasked,
  AXI_BUS.Master dma_masked
);

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
    .AWID_i     ( cfg.aw_id      ),
    .AWADDR_i   ( cfg.aw_addr    ),
    .AWLEN_i    ( cfg.aw_len     ),
    .AWSIZE_i   ( cfg.aw_size    ),
    .AWBURST_i  ( cfg.aw_burst   ),
    .AWLOCK_i   ( cfg.aw_lock    ),
    .AWCACHE_i  ( cfg.aw_cache   ),
    .AWPROT_i   ( cfg.aw_prot    ),
    .AWREGION_i ( cfg.aw_region  ),
    .AWUSER_i   ( cfg.aw_user    ),
    .AWQOS_i    ( cfg.aw_qos     ),
    .AWVALID_i  ( cfg.aw_valid   ),
    .AWREADY_o  ( cfg.aw_ready   ),
    .WDATA_i    ( cfg.w_data     ),
    .WSTRB_i    ( cfg.w_strb     ),
    .WLAST_i    ( cfg.w_last     ),
    .WUSER_i    ( cfg.w_user     ),
    .WVALID_i   ( cfg.w_valid    ),
    .WREADY_o   ( cfg.w_ready    ),
    .BID_o      ( cfg.b_id       ),
    .BRESP_o    ( cfg.b_resp     ),
    .BVALID_o   ( cfg.b_valid    ),
    .BUSER_o    ( cfg.b_user     ),
    .BREADY_i   ( cfg.b_ready    ),
    .ARID_i     ( cfg.ar_id      ),
    .ARADDR_i   ( cfg.ar_addr    ),
    .ARLEN_i    ( cfg.ar_len     ),
    .ARSIZE_i   ( cfg.ar_size    ),
    .ARBURST_i  ( cfg.ar_burst   ),
    .ARLOCK_i   ( cfg.ar_lock    ),
    .ARCACHE_i  ( cfg.ar_cache   ),
    .ARPROT_i   ( cfg.ar_prot    ),
    .ARREGION_i ( cfg.ar_region  ),
    .ARUSER_i   ( cfg.ar_user    ),
    .ARQOS_i    ( cfg.ar_qos     ),
    .ARVALID_i  ( cfg.ar_valid   ),
    .ARREADY_o  ( cfg.ar_ready   ),
    .RID_o      ( cfg.r_id       ),
    .RDATA_o    ( cfg.r_data     ),
    .RRESP_o    ( cfg.r_resp     ),
    .RLAST_o    ( cfg.r_last     ),
    .RUSER_o    ( cfg.r_user     ),
    .RVALID_o   ( cfg.r_valid    ),
    .RREADY_i   ( cfg.r_ready    ),
    .PENABLE    ( penable        ),
    .PWRITE     ( pwrite         ),
    .PADDR      ( paddr          ),
    .PSEL       ( psel           ),
    .PWDATA     ( pwdata         ),
    .PRDATA     ( prdata         ),
    .PREADY     ( pready         ),
    .PSLVERR    ( pslverr        )
  );

  logic [1:0]       sel, e_pready, e_pslverr;
  logic [1:0][31:0] e_prdata;
  assign sel     = {psel & paddr[11], psel & ~paddr[11]};
  assign prdata  = paddr[11] ? e_prdata[1]  : e_prdata[0];
  assign pready  = paddr[11] ? e_pready[1]  : e_pready[0];
  assign pslverr = paddr[11] ? e_pslverr[1] : e_pslverr[0];

  // Constant AXI fields of the two master ports.
  `define AES_ENGINE_AXI_TIEOFF(bus) \
    assign bus.aw_id = '0;     assign bus.aw_size = 3'd3;  assign bus.aw_burst = 2'b01; \
    assign bus.aw_lock = '0;   assign bus.aw_cache = '0;   assign bus.aw_prot = '0; \
    assign bus.aw_qos = '0;    assign bus.aw_region = '0;  assign bus.aw_atop = '0; \
    assign bus.aw_user = '0;   assign bus.w_strb = '1;     assign bus.w_user = '0; \
    assign bus.ar_id = '0;     assign bus.ar_size = 3'd3;  assign bus.ar_burst = 2'b01; \
    assign bus.ar_lock = '0;   assign bus.ar_cache = '0;   assign bus.ar_prot = '0; \
    assign bus.ar_qos = '0;    assign bus.ar_region = '0;  assign bus.ar_user = '0;

  `AES_ENGINE_AXI_TIEOFF(dma_unmasked)
  `AES_ENGINE_AXI_TIEOFF(dma_masked)

  aes_engine #(.Masked(1'b0)) i_unmasked (
    .clk_i, .rst_ni,
    .psel_i(sel[0]), .penable_i(penable), .pwrite_i(pwrite), .paddr_i(paddr[11:0]), .pwdata_i(pwdata),
    .prdata_o(e_prdata[0]), .pready_o(e_pready[0]), .pslverr_o(e_pslverr[0]),
    .ar_addr_o(dma_unmasked.ar_addr), .ar_len_o(dma_unmasked.ar_len), .ar_valid_o(dma_unmasked.ar_valid),
    .ar_ready_i(dma_unmasked.ar_ready), .r_data_i(dma_unmasked.r_data), .r_resp_i(dma_unmasked.r_resp),
    .r_last_i(dma_unmasked.r_last), .r_valid_i(dma_unmasked.r_valid), .r_ready_o(dma_unmasked.r_ready),
    .aw_addr_o(dma_unmasked.aw_addr), .aw_len_o(dma_unmasked.aw_len), .aw_valid_o(dma_unmasked.aw_valid),
    .aw_ready_i(dma_unmasked.aw_ready), .w_data_o(dma_unmasked.w_data), .w_last_o(dma_unmasked.w_last),
    .w_valid_o(dma_unmasked.w_valid), .w_ready_i(dma_unmasked.w_ready), .b_resp_i(dma_unmasked.b_resp),
    .b_valid_i(dma_unmasked.b_valid), .b_ready_o(dma_unmasked.b_ready), .done_o()
  );

  aes_engine #(.Masked(1'b1)) i_masked (
    .clk_i, .rst_ni,
    .psel_i(sel[1]), .penable_i(penable), .pwrite_i(pwrite), .paddr_i(paddr[11:0]), .pwdata_i(pwdata),
    .prdata_o(e_prdata[1]), .pready_o(e_pready[1]), .pslverr_o(e_pslverr[1]),
    .ar_addr_o(dma_masked.ar_addr), .ar_len_o(dma_masked.ar_len), .ar_valid_o(dma_masked.ar_valid),
    .ar_ready_i(dma_masked.ar_ready), .r_data_i(dma_masked.r_data), .r_resp_i(dma_masked.r_resp),
    .r_last_i(dma_masked.r_last), .r_valid_i(dma_masked.r_valid), .r_ready_o(dma_masked.r_ready),
    .aw_addr_o(dma_masked.aw_addr), .aw_len_o(dma_masked.aw_len), .aw_valid_o(dma_masked.aw_valid),
    .aw_ready_i(dma_masked.aw_ready), .w_data_o(dma_masked.w_data), .w_last_o(dma_masked.w_last),
    .w_valid_o(dma_masked.w_valid), .w_ready_i(dma_masked.w_ready), .b_resp_i(dma_masked.b_resp),
    .b_valid_i(dma_masked.b_valid), .b_ready_o(dma_masked.b_ready), .done_o()
  );

endmodule
