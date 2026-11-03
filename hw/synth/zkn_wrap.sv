// CVA6's Zkn unit (third_party/cva6/core/aes.sv) between registers, for
// synthesis on its own. In CVA6 it sits in the ALU stage: one result per cycle.
//
// ZkneOnly = 1: only the four instructions the AES-128 encryption uses can be
// selected (aes64es, aes64esm, aes64ks1i, aes64ks2), so synthesis drops the
// decryption and SHA-2 logic. ZkneOnly = 0: the full Zkn unit as in CVA6.
module zkn_wrap
  import ariane_pkg::*;
#(
  parameter bit ZkneOnly = 1
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  fu_op        op_i,        // used when ZkneOnly = 0
  input  logic [1:0]  zkne_sel_i,  // used when ZkneOnly = 1
  input  logic [63:0] operand_a_i,
  input  logic [63:0] operand_b_i,
  input  logic [63:0] imm_i,
  input  logic [5:0]  orig_instr_i,
  output logic [63:0] result_o
);
  localparam config_pkg::cva6_cfg_t CVA6Cfg =
      build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);

  // Same as fu_data_t in core/cva6.sv.
  typedef struct packed {
    fu_t                              fu;
    fu_op                             operation;
    logic [CVA6Cfg.XLEN-1:0]          operand_a;
    logic [CVA6Cfg.XLEN-1:0]          operand_b;
    logic [CVA6Cfg.XLEN-1:0]          imm;
    logic [CVA6Cfg.TRANS_ID_BITS-1:0] trans_id;
  } fu_data_t;

  fu_op op;
  always_comb begin
    if (ZkneOnly) begin
      unique case (zkne_sel_i)
        2'd0:    op = AES64ES;
        2'd1:    op = AES64ESM;
        2'd2:    op = AES64KS1I;
        default: op = AES64KS2;
      endcase
    end else begin
      op = op_i;
    end
  end

  fu_data_t          data_q;
  logic [5:0]        instr_q;
  logic [63:0]       result_d, result_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_q   <= '0;
      instr_q  <= '0;
      result_q <= '0;
    end else begin
      data_q   <= '{fu: ALU, operation: op, operand_a: operand_a_i,
                    operand_b: operand_b_i, imm: imm_i, trans_id: '0};
      instr_q  <= orig_instr_i;
      result_q <= result_d;
    end
  end

  aes #(
    .CVA6Cfg   ( CVA6Cfg   ),
    .fu_data_t ( fu_data_t )
  ) i_aes (
    .clk_i,
    .rst_ni,
    .fu_data_i      ( data_q   ),
    .orig_instr_aes ( instr_q  ),
    .result_o       ( result_d )
  );

  assign result_o = result_q;
endmodule

// The full Zkn unit, as CVA6 has it (a separate top so synthesis needs no
// parameter override).
module zkn_full (
  input  logic               clk_i,
  input  logic               rst_ni,
  input  ariane_pkg::fu_op   op_i,
  input  logic [63:0]        operand_a_i,
  input  logic [63:0]        operand_b_i,
  input  logic [63:0]        imm_i,
  input  logic [5:0]         orig_instr_i,
  output logic [63:0]        result_o
);
  zkn_wrap #(.ZkneOnly(1'b0)) i_zkn (.zkne_sel_i(2'b00), .*);
endmodule
