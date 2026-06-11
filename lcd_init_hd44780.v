// lcd init - atv do lab

// ---------------------------------------------------------------------------
// Módulo: lcd_init_hd44780
// Versão compacta: FSM genérica com estados SETUP, PULSE e WAIT
// usando um contador de comandos e ROM de comandos/delays.
//
// Sequência de comandos (cmd_rom):
//   0) 0x38 - Function Set        (8 bits, 2 linhas, 5x8)
//   1) 0x0C - Display ON          (display ON, cursor OFF, blink OFF)
//   2) 0x01 - Clear Display       (limpa display - delay maior)
//   3) 0x06 - Entry Mode Set      (incrementa cursor, sem shift do display)
// ---------------------------------------------------------------------------
module lcd_init_hd44780 (
    input  wire       clk,
    input  wire       rst,    // reset assíncrono, ativo em '1'
    input  wire       start,
    output reg        done,

    output reg  [7:0] lcd_data,
    output reg        lcd_rs,
    output reg        lcd_rw,
    output reg        lcd_e
);

    // -----------------------------------------------------------------------
    // Comandos do HD44780
    // -----------------------------------------------------------------------
    localparam [7:0] CMD_FUNCTION_SET  = 8'h38; // 8 bits, 2 linhas, 5x8
    localparam [7:0] CMD_DISPLAY_ON    = 8'h0C; // display ON, cursor OFF, blink OFF
    localparam [7:0] CMD_DISPLAY_CLEAR = 8'h01; // clear display
    localparam [7:0] CMD_ENTRY_MODE    = 8'h06; // entry mode: incrementa cursor, sem shift

    // Número de comandos na sequência
    localparam integer NUM_CMDS = 4;

    // -----------------------------------------------------------------------
    // Temporizações (ajustar conforme clock real)
    // Exemplo: clock de 50 MHz (20 ns)
    // -----------------------------------------------------------------------
    localparam [31:0] DELAY_POWER_ON  = 32'd750_000; // ~15 ms
    localparam [31:0] DELAY_STD_CMD   = 32'd2_000;   // ~40 us (com folga)
    localparam [31:0] DELAY_CLEAR_CMD = 32'd90_000;  // ~1,8 ms
    localparam [31:0] DELAY_PULSE_E   = 32'd50;      // ~1 us

    // -----------------------------------------------------------------------
    // Estados da FSM
    // -----------------------------------------------------------------------
    localparam [2:0]
        S_IDLE       = 3'd0,
        S_POWER_WAIT = 3'd1,
        S_SETUP      = 3'd2,
        S_PULSE      = 3'd3,
        S_WAIT       = 3'd4,
        S_DONE       = 3'd5;

    reg [2:0]  state, next_state;
    reg [31:0] delay_cnt, next_delay_cnt;
    reg [2:0]  cmd_idx, next_cmd_idx; // suporta até 8 comandos
	 // valor do comando atual (proteção se cmd_idx >= NUM_CMDS)
    reg [7:0] current_cmd;

    // -----------------------------------------------------------------------
    // ROM de comandos e ROM de delays pós-comando
    // -----------------------------------------------------------------------
    reg [7:0]  cmd_rom       [0:NUM_CMDS-1];
    reg [31:0] cmd_delay_rom [0:NUM_CMDS-1];

    integer i;
    initial begin
        // Comandos
        cmd_rom[0] = CMD_FUNCTION_SET;
        cmd_rom[1] = CMD_DISPLAY_ON;
        cmd_rom[2] = CMD_DISPLAY_CLEAR;
        cmd_rom[3] = CMD_ENTRY_MODE;

        // Delays pós-comando (exceto power-on, que é separado)
        cmd_delay_rom[0] = DELAY_STD_CMD;   // FUNCTION_SET
        cmd_delay_rom[1] = DELAY_STD_CMD;   // DISPLAY_ON
        cmd_delay_rom[2] = DELAY_CLEAR_CMD; // DISPLAY_CLEAR (maior)
        cmd_delay_rom[3] = DELAY_STD_CMD;   // ENTRY_MODE
    end

    // =======================================================================
    // 1) BLOCO SEQUENCIAL: registra estado, contador de delay e índice de cmd
    // =======================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_IDLE;
            delay_cnt  <= 32'd0;
            cmd_idx    <= 3'd0;
        end else begin
            state      <= next_state;
            delay_cnt  <= next_delay_cnt;
            cmd_idx    <= next_cmd_idx;
        end
    end

    // =======================================================================
    // 2) BLOCO COMBINACIONAL: cálculo do próximo estado / cmd / delay
    // =======================================================================
    always @(*) begin
        // valores padrão (mantém)
        next_state     = state;
        next_delay_cnt = delay_cnt;
        next_cmd_idx   = cmd_idx;

        case (state)
            // ---------------------------------------------------------------
            // Espera pelo start
            // ---------------------------------------------------------------
            S_IDLE: begin
                if (start) begin
                    next_state     = S_POWER_WAIT;
                    next_delay_cnt = DELAY_POWER_ON;
                    next_cmd_idx   = 3'd0;  // começa do primeiro comando
                end
            end

            // ---------------------------------------------------------------
            // Espera inicial de power-on
            // ---------------------------------------------------------------
            S_POWER_WAIT: begin
                if (delay_cnt > 0) begin
                    next_delay_cnt = delay_cnt - 1;
                end else begin
                    next_state     = S_SETUP;
                end
            end

            // ---------------------------------------------------------------
            // SETUP: coloca o comando atual no barramento (em termos de estado),
            // próximo passo é gerar o pulso de E
            // ---------------------------------------------------------------
            S_SETUP: begin
                if (cmd_idx < NUM_CMDS) begin
                    next_state     = S_PULSE;
                    next_delay_cnt = DELAY_PULSE_E;
                end else begin
                    next_state = S_DONE; // todos os comandos enviados
                end
            end

            // ---------------------------------------------------------------
            // PULSE: gera pulso de Enable para o comando atual
            // ---------------------------------------------------------------
            S_PULSE: begin
                if (delay_cnt > 0) begin
                    next_delay_cnt = delay_cnt - 1;
                end else begin
                    next_state     = S_WAIT;
                    // usa delay específico para este comando
                    next_delay_cnt = cmd_delay_rom[cmd_idx];
                end
            end

            // ---------------------------------------------------------------
            // WAIT: espera o comando terminar internamente no LCD
            // ---------------------------------------------------------------
            S_WAIT: begin
                if (delay_cnt > 0) begin
                    next_delay_cnt = delay_cnt - 1;
                end else begin
                    // avança para o próximo comando
                    next_cmd_idx = cmd_idx + 1;
                    next_state   = S_SETUP;
                end
            end

            // ---------------------------------------------------------------
            // DONE: inicialização concluída, permanece aqui até reset
            // ---------------------------------------------------------------
            S_DONE: begin
                // permanece
                next_state = S_DONE;
            end

            default: begin
                next_state     = S_IDLE;
                next_delay_cnt = 32'd0;
                next_cmd_idx   = 3'd0;
            end
        endcase
    end

    // =======================================================================
    // 3) BLOCO COMBINACIONAL: geração das saídas (FSM Moore)
    // =======================================================================
    always @(*) begin
        // valores padrão
        lcd_data = 8'h00;
        lcd_rs   = 1'b0;
        lcd_rw   = 1'b0;
        lcd_e    = 1'b0;
        done     = 1'b0;

        if (cmd_idx < NUM_CMDS)
            current_cmd = cmd_rom[cmd_idx];
        else
            current_cmd = 8'h00;

        case (state)
            S_IDLE: begin
                // tudo inativo
            end

            S_POWER_WAIT: begin
                // só espera, sem gerar comando
            end

            // Em SETUP, PULSE e WAIT, sempre estamos trabalhando
            // com o "current_cmd" como comando a ser enviado.
            S_SETUP: begin
                lcd_data = current_cmd;
                lcd_rs   = 1'b0; // comando
                lcd_rw   = 1'b0; // escrita
                lcd_e    = 1'b0;
            end

            S_PULSE: begin
                lcd_data = current_cmd;
                lcd_rs   = 1'b0;
                lcd_rw   = 1'b0;
                lcd_e    = 1'b1; // pulso de enable
            end

            S_WAIT: begin
                lcd_data = current_cmd;
                lcd_rs   = 1'b0;
                lcd_rw   = 1'b0;
                lcd_e    = 1'b0;
            end

            S_DONE: begin
                done   = 1'b1;
                lcd_e  = 1'b0;
                lcd_rw = 1'b0;
                lcd_rs = 1'b0;
                // lcd_data pode ficar 0 ou último comando, pouco relevante aqui
            end
        endcase
    end

endmodule