// OpenTitan AES without masking (plain Canright S-box), to compare like with
// like against Zkne, which is not masked either. Default ot_aes is masked.
module ot_aes_unmasked (
  input  logic                                             clk_i,
  input  logic                                             rst_ni,
  input  logic                                             rst_shadowed_ni,
  output prim_mubi_pkg::mubi4_t                            idle_o,
  input  lc_ctrl_pkg::lc_tx_t                              lc_escalate_en_i,
  input  logic                                             clk_edn_i,
  input  logic                                             rst_edn_ni,
  output edn_pkg::edn_req_t                                edn_o,
  input  edn_pkg::edn_rsp_t                                edn_i,
  input  keymgr_pkg::hw_key_req_t                          keymgr_key_i,
  input  tlul_ot_pkg::tl_h2d_t                             tl_i,
  output tlul_ot_pkg::tl_d2h_t                             tl_o,
  input  prim_alert_pkg::alert_rx_t [aes_reg_pkg::NumAlerts-1:0] alert_rx_i,
  output prim_alert_pkg::alert_tx_t [aes_reg_pkg::NumAlerts-1:0] alert_tx_o
);
  ot_aes #(
    .SecMasking  ( 1'b0                           ),
    .SecSBoxImpl ( ot_aes_pkg::SBoxImplCanright   )
  ) i_aes (.*);
endmodule
