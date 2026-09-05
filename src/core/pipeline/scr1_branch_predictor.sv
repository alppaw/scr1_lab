/// @file       scr1_branch_predictor.sv
/// @brief      Dynamic Branch Predictor with BTB and 2-bit BHT for SCR1 core
///

module scr1_branch_predictor (
    input  logic        clk,
    input  logic        rst_n,
    
    // Входные сигналы со стадии IFU (Выборка)
    input  logic [31:0] curr_pc_i,               // Текущий PC для поиска в BTB
    
    // Входные сигналы обратной связи от EXU (Разрешение перехода)
    input  logic        exu_branch_resolved_i,   // Сигнал: в EXU выполнилась инструкция перехода
    input  logic        exu_branch_taken_i,      // Сигнал: переход в EXU был совершен (Taken)
    input  logic [31:0] exu_branch_pc_i,         // Адрес инструкции перехода в EXU
    input  logic [31:0] exu_target_pc_i,         // Реальный целевой адрес перехода из EXU
    
    // Выходные сигналы предсказания для IFU
    output logic        predict_taken_o,         // Предсказание: 1 - Taken (прыгаем), 0 - Not Taken
    output logic [31:0] predict_pc_o             // Предсказанный адрес цели перехода из BTB
);

    //--------------------------------------------------------------------------
    // КОНСТАНТЫ И ПАРАМЕТРЫ ПРЕДСКАЗАТЕЛЯ
    //--------------------------------------------------------------------------
    localparam BTB_SIZE    = 16;                 // Размер буфера целей (16 записей оптимально для LUT ПЛИС)
    localparam INDEX_WIDTH = 4;                  // Ширина индекса для адресации 16 строк (2^4 = 16)
    localparam TAG_WIDTH   = 32 - INDEX_WIDTH - 1; // Ширина тега (исключая младший нулевой бит pc[0])

    // Состояния 2-битного насыщающего счетчика (BHT) [1]:
    localparam SNT = 2'b00;                      // Strongly Not Taken (Сильно против перехода)
    localparam WNT = 2'b01;                      // Weakly Not Taken (Слабо против перехода)
    localparam WT  = 2'b10;                      // Weakly Taken (Слабо за переход)
    localparam ST  = 2'b11;                      // Strongly Taken (Сильно за переход)

    //--------------------------------------------------------------------------
    // ВНУТРЕННЯЯ ПАМЯТЬ ПРЕДСКАЗАТЕЛЯ С НАЧАЛЬНОЙ ИНИЦИАЛИЗАЦИЕЙ ПЛИС
    //--------------------------------------------------------------------------
    // Инициализируем таблицы безопасными значениями по умолчанию при включении ПЛИС
    logic [TAG_WIDTH-1:0] btb_tag    [BTB_SIZE-1:0] = '{default: '0};
    logic [31:0]          btb_target [BTB_SIZE-1:0] = '{default: '0};
    logic                 btb_valid  [BTB_SIZE-1:0] = '{default: 1'b0};
    logic [1:0]           bht_state  [BTB_SIZE-1:0] = '{default: WNT};  // Инициализируем как Weakly Not Taken

    //--------------------------------------------------------------------------
    // ЛОГИКА ПОИСКА (Lookup Stage - IFU / Комбинационная схема)
    //--------------------------------------------------------------------------
    logic [INDEX_WIDTH-1:0] read_index;
    logic [TAG_WIDTH-1:0]   read_tag;
    logic                   btb_hit;

    // Выделяем индекс и тег из текущего PC. 
    // Поскольку инструкции выровнены по 2 байтам (RVC), бит curr_pc_i[0] всегда равен 0 и игнорируется.
    assign read_index = curr_pc_i[INDEX_WIDTH:1];           // Биты [4:1] для индекса
    assign read_tag   = curr_pc_i[31:INDEX_WIDTH+1];        // Биты [31:5] для тега

    // Проверяем, есть ли совпадение в буфере целей BTB
    assign btb_hit = btb_valid[read_index] && (btb_tag[read_index] == read_tag);

    // Принимаем решение о предсказании:
    // Мы предсказываем переход только если есть попадание в BTB (btb_hit) 
    // и двухбитный автомат находится в состоянии WT (2) или ST (3) [1].
    assign predict_taken_o = btb_hit && (bht_state[read_index] >= 2'b10);
    assign predict_pc_o    = btb_target[read_index];

    //--------------------------------------------------------------------------
    // ЛОГИКА ОБУЧЕНИЯ (Update Stage - EXU / Последовательностная схема)
    //--------------------------------------------------------------------------
    logic [INDEX_WIDTH-1:0] write_index;
    logic [TAG_WIDTH-1:0]   write_tag;

    assign write_index = exu_branch_pc_i[INDEX_WIDTH:1];
    assign write_tag   = exu_branch_pc_i[31:INDEX_WIDTH+1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ОПТИМИЗАЦИЯ СБРОСА ДЛЯ FPGA [3]:
            // Сбрасываем ТОЛЬКО 16 триггеров валидности. 
            // Это гарантирует отсутствие ложных попаданий при старте,
            // при этом освобождает ПЛИС от тяжелого асинхронного сброса массивов данных.
            for (int i = 0; i < BTB_SIZE; i = i + 1) begin
                btb_valid[i] <= 1'b0;
            end
        end else if (exu_branch_resolved_i) begin
            // Запись новой цели в BTB происходит при успешном разрешении перехода в EXU
            btb_valid[write_index]  <= 1'b1;
            btb_tag[write_index]    <= write_tag;
            btb_target[write_index] <= exu_target_pc_i;

            // Обновление 2-битного счетчика истории переходов
            if (exu_branch_taken_i) begin
                if (bht_state[write_index] != ST) begin
                    bht_state[write_index] <= bht_state[write_index] + 1'b1;
                end
            end else begin
                if (bht_state[write_index] != SNT) begin
                    bht_state[write_index] <= bht_state[write_index] - 1'b1;
                end
            end
        end
    end

endmodule