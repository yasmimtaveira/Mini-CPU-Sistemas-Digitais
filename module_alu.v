// (ULA) funcionando

module module_alu (
    input [2:0] op_code,                 // Código da instrução (000 a 111)
    input signed [15:0] reg_a_val,       // Valor lido do Registrador 1 (16 bits)
    input signed [15:0] reg_b_val,       // Valor lido do Registrador 2 (16 bits)
    output reg signed [15:0] alu_out  // Resultado LCD
);

    // Opcodes padronizados de acordo com a tabela do projeto
    localparam [2:0] LOAD=0, ADD=1, ADDI=2, SUB=3, SUBI=4, MUL=5, CLEAR=6, DISPLAY=7;
    
    always @(*) begin
        case (op_code)
            LOAD:    alu_out = reg_b_val;          // Carrega imediato convertido
            ADD:     alu_out = reg_a_val + reg_b_val;         // Soma de registradores (Reg1 + Reg2)
            ADDI:    alu_out = reg_a_val + reg_b_val;  // Reg + Imediato convertido
            SUB:     alu_out = reg_a_val - reg_b_val;         // Subtração de registradores (Reg1 - Reg2)
            SUBI:    alu_out = reg_a_val - reg_b_val;  // Reg - Imediato convertido
            MUL:     alu_out = reg_a_val * reg_b_val;  // Reg * Imediato convertido
            CLEAR:   alu_out = 16'sd0;                  // Zera o resultado
            DISPLAY: alu_out = reg_a_val;                  // Repassa o valor para o LCD
            default: alu_out = 16'sd0;
        endcase
    end	

endmodule